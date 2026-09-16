# mqtt.ps1 - Werte an einen MQTT-Broker melden (Home Assistant) und Befehle von dort annehmen.
# Geladen von puzzle.ps1 per Dot-Sourcing. Ohne $MqttHost passiert nichts.
#
# Topics (Beispiel Rechner MEINPC, GPU 0, $MqttTopic = 'heuhaufen'):
#   heuhaufen/meinpc-gpu0/state           JSON wie status*.json (retained), bei jeder Zustandsaenderung, sonst alle $MqttSek s
#   heuhaufen/meinpc-gpu0/availability    online / offline (retained, offline auch als Last Will)
#   heuhaufen/meinpc-gpu0/set             Befehle: suche_an, suche_aus, web_an, web_aus, pause, weiter, start, auto_an, auto_aus (retained wird ignoriert)
# Home Assistant legt die Geraete ueber MQTT Discovery selbst an ($MqttDiscovery, leer = keine Discovery).
# Wie in der Statusdatei steht nie ein Schluessel in einer Nachricht, bei einem Treffer nur treffer:true.

if (-not ('Heu.Mqtt' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net.Sockets;
using System.Text;
using System.Threading;

namespace Heu {
// Kleiner MQTT-3.1.1-Client: QoS 0, Last Will, Abonnieren, Ping, Neuverbindung im eigenen Thread.
// Das Dashboard ruft nur Publish und liest Incoming - beides blockiert nicht, wenn der Broker fehlt.
public class Mqtt {
    readonly string host; readonly int port; readonly string clientId; readonly string willTopic;
    readonly object wlock = new object();
    readonly List<string[]> onConnect = new List<string[]>();
    readonly List<string> subs = new List<string>();
    // Eingang: { topic, payload, "1" wenn retained sonst "0" }
    public readonly ConcurrentQueue<string[]> Incoming = new ConcurrentQueue<string[]>();
    TcpClient tcp; NetworkStream ns;
    Thread thread; volatile bool stop;
    public volatile bool Connected;
    public volatile string LastError = "";
    public volatile int Connects;
    DateTime lastRx, lastTx, lastPing;
    int packetId;
    public string User = "";       // leer = anonym
    public string Password = "";

    public Mqtt(string host, int port, string clientId, string willTopic) {
        this.host = host; this.port = port; this.clientId = clientId; this.willTopic = willTopic ?? "";   // "" = ohne Last Will
    }
    public string WillTopic { get { return willTopic; } }
    // Nach jeder (Neu-)Verbindung retained senden: Discovery und "online"
    public void AddOnConnect(string topic, string payload) { lock (onConnect) onConnect.Add(new string[] { topic, payload }); }
    public void AddSubscription(string topic) { lock (subs) subs.Add(topic); }
    public void Start() {
        thread = new Thread(Run); thread.IsBackground = true; thread.Name = "MQTT"; thread.Start();
    }

    void Run() {
        int wait = 2000;
        while (!stop) {
            try { Open(); wait = 2000; Loop(); }
            catch (Exception e) { if (!stop) LastError = e.Message; }
            Connected = false; Shut();
            for (int t = 0; t < wait && !stop; t += 100) Thread.Sleep(100);
            wait = Math.Min(wait * 2, 60000);
        }
    }

    void Open() {
        TcpClient c = new TcpClient();
        IAsyncResult ar = c.BeginConnect(host, port, null, null);
        if (!ar.AsyncWaitHandle.WaitOne(5000)) {
            try { c.Close(); } catch { }
            throw new Exception(host + ":" + port + " antwortet nicht");
        }
        c.EndConnect(ar);
        c.NoDelay = true; c.SendTimeout = 5000; c.ReceiveTimeout = 10000;
        tcp = c; ns = c.GetStream();
        MemoryStream v = new MemoryStream();
        Str(v, "MQTT"); v.WriteByte(4);
        int cf = willTopic.Length > 0 ? 0x02 | 0x04 | 0x20 : 0x02;   // Clean Session, Will retained (QoS 0)
        if (!String.IsNullOrEmpty(User)) { cf |= 0x80; if (!String.IsNullOrEmpty(Password)) cf |= 0x40; }
        v.WriteByte((byte)cf);
        v.WriteByte(0); v.WriteByte(60);          // Keep Alive 60 s
        Str(v, clientId);
        if (willTopic.Length > 0) { Str(v, willTopic); Str(v, "offline"); }
        if ((cf & 0x80) != 0) Str(v, User);
        if ((cf & 0x40) != 0) Str(v, Password);
        Send(0x10, v.ToArray());
        int type, flags;
        byte[] body = ReadPacket(out type, out flags);
        if (type != 2 || body.Length < 2) throw new Exception("Broker antwortet nicht mit CONNACK");
        if (body[1] == 5) throw new Exception(String.IsNullOrEmpty(User) ? "Broker verlangt Anmeldung (MqttUser/MqttPass)" : "Broker lehnt die Anmeldung ab");
        if (body[1] == 4) throw new Exception("Benutzer oder Passwort falsch");
        if (body[1] != 0) throw new Exception("Broker lehnt ab (CONNACK " + body[1] + ")");
        Connected = true; Connects++; LastError = "";
        List<string> s; lock (subs) s = new List<string>(subs);
        foreach (string t in s) {
            MemoryStream b = new MemoryStream();
            int id = Interlocked.Increment(ref packetId) & 0xFFFF; if (id == 0) id = 1;
            b.WriteByte((byte)(id >> 8)); b.WriteByte((byte)id);
            Str(b, t); b.WriteByte(0);
            Send(0x82, b.ToArray());
        }
        List<string[]> oc; lock (onConnect) oc = new List<string[]>(onConnect);
        foreach (string[] p in oc) if (!Publish(p[0], p[1], true)) throw new Exception("Senden nach dem Verbinden ging nicht");
    }

    void Loop() {
        lastRx = DateTime.UtcNow; lastTx = DateTime.UtcNow; lastPing = DateTime.UtcNow;
        while (!stop) {
            TcpClient c = tcp;
            if (c == null) throw new Exception("Verbindung geschlossen");
            if (c.Client.Poll(200000, SelectMode.SelectRead)) {
                if (c.Client.Available == 0) throw new Exception("Broker hat die Verbindung getrennt");
                int type, flags;
                byte[] body = ReadPacket(out type, out flags);
                lastRx = DateTime.UtcNow;
                if (type == 3 && body.Length >= 2) {
                    int tl = (body[0] << 8) | body[1];
                    string topic = Encoding.UTF8.GetString(body, 2, tl);
                    int pos = 2 + tl;
                    if (((flags >> 1) & 3) > 0) pos += 2;
                    string payload = pos < body.Length ? Encoding.UTF8.GetString(body, pos, body.Length - pos) : "";
                    Incoming.Enqueue(new string[] { topic, payload, (flags & 1) == 1 ? "1" : "0" });
                }
            }
            // PINGREQ alle 30 s, auch wenn laufend gesendet wird: QoS-0-Nachrichten bestaetigt der Broker nicht. Ohne Ping
            // kaeme nie etwas zurueck, und die Pruefung darunter trennte nach 95 s (15.09.2026 im echten Lauf gesehen).
            if ((DateTime.UtcNow - lastPing).TotalSeconds >= 30) { Send(0xC0, new byte[0]); lastPing = DateTime.UtcNow; }
            if ((DateTime.UtcNow - lastRx).TotalSeconds >= 95) throw new Exception("Broker antwortet nicht mehr");
        }
    }

    byte[] ReadPacket(out int type, out int flags) {
        NetworkStream s = ns;
        if (s == null) throw new Exception("Verbindung geschlossen");
        int h = s.ReadByte();
        if (h < 0) throw new Exception("Verbindung beendet");
        type = h >> 4; flags = h & 0x0F;
        int len = 0, mul = 1, b;
        do {
            b = s.ReadByte();
            if (b < 0) throw new Exception("Verbindung beendet");
            len += (b & 127) * mul; mul *= 128;
            if (mul > 128 * 128 * 128 * 128) throw new Exception("Paketlaenge ungueltig");
        } while ((b & 128) != 0);
        if (len > (1 << 20)) throw new Exception("Paket zu gross");
        byte[] body = new byte[len];
        int got = 0;
        while (got < len) {
            int n = s.Read(body, got, len - got);
            if (n <= 0) throw new Exception("Verbindung beendet");
            got += n;
        }
        return body;
    }

    void Send(int header, byte[] body) {
        lock (wlock) {
            NetworkStream s = ns;
            if (s == null) throw new Exception("keine Verbindung");
            MemoryStream m = new MemoryStream(body.Length + 5);
            m.WriteByte((byte)header);
            int len = body.Length;
            do { int d = len % 128; len /= 128; if (len > 0) d |= 128; m.WriteByte((byte)d); } while (len > 0);
            m.Write(body, 0, body.Length);
            byte[] a = m.ToArray();
            s.Write(a, 0, a.Length);
            lastTx = DateTime.UtcNow;
        }
    }

    static void Str(Stream s, string t) {
        byte[] b = Encoding.UTF8.GetBytes(t);
        s.WriteByte((byte)(b.Length >> 8)); s.WriteByte((byte)b.Length); s.Write(b, 0, b.Length);
    }

    public bool Publish(string topic, string payload, bool retain) {
        if (!Connected) return false;
        try {
            MemoryStream b = new MemoryStream();
            Str(b, topic);
            byte[] p = Encoding.UTF8.GetBytes(payload ?? "");
            b.Write(p, 0, p.Length);
            Send(retain ? 0x31 : 0x30, b.ToArray());
            return true;
        } catch (Exception e) {
            LastError = e.Message; Connected = false; Shut();
            return false;
        }
    }

    // Sauber abmelden: "offline" selbst senden (bei DISCONNECT schickt der Broker den Last Will nicht)
    public void Stop() {
        if (Connected) {
            try { if (willTopic.Length > 0) Publish(willTopic, "offline", true); Send(0xE0, new byte[0]); } catch { }
        }
        stop = true; Connected = false; Shut();
        if (thread != null) thread.Join(1500);
    }

    void Shut() {
        NetworkStream s = ns; TcpClient c = tcp;
        ns = null; tcp = null;
        try { if (s != null) s.Close(); } catch { }
        try { if (c != null) c.Close(); } catch { }
    }
}
}
"@
}

# Protokoll fuer Verbindungswechsel (im Fenster ist dafuer nur die Statuszeile)
function Write-MqttLog([string]$text) {
    try {
        Add-Content -Encoding utf8 -Path (Join-Path $Daten 'mqtt.log') `
            -Value ('{0:yyyy-MM-dd HH:mm:ss}  GPU {1}  {2}' -f (Get-Date), $dev, $text)
    } catch { }
}

# Discovery-Nachrichten fuer Home Assistant: Liste aus Paaren { topic, json }
function Get-MqttDiscovery([string]$knoten) {
    $karte = "$gpuName" -replace '^NVIDIA\s+', ''
    $geraet = [ordered]@{
        identifiers = @($knoten); name = "Heuhaufen $pc GPU $dev"; manufacturer = 'Heuhaufen'
        model = $(if ($karte) { $karte } else { 'GPU' }); sw_version = "$AppVersion"
    }
    $zm = [ordered]@{ laeuft = (T 'mqtt.z.laeuft'); pause = (T 'mqtt.z.pause'); 'pause-hand' = (T 'mqtt.z.pause'); 'pause-vram' = (T 'mqtt.z.pauseVram'); 'pause-ollama' = (T 'mqtt.z.pauseOllama')
            'pause-wartet' = (T 'mqtt.z.bereit'); gestoppt = (T 'mqtt.z.gestoppt'); beendet = (T 'mqtt.z.beendet'); crash = (T 'mqtt.z.crash'); solved = (T 'mqtt.z.geloest'); found = (T 'mqtt.z.treffer') }
    $zustandTpl = '{{ {' + ((@($zm.Keys) | ForEach-Object { "'$_':'" + ($zm[$_] -replace "'", '') + "'" }) -join ',') + '}.get(value_json.zustand, value_json.zustand) }}'
    # (Zustandstexte stehen in sprache\de.psd1 und en.psd1 unter mqtt.z.*)

    # immer = ohne availability: bleibt auch nach dem Ende sichtbar (Zustand "beendet", Treffer, Stand des Shares)
    $liste = @(
        @{ a = 'sensor'; id = 'zustand'; name = (T 'mqtt.name.zustand'); tpl = $zustandTpl; icon = 'mdi:state-machine'; immer = $true }
        @{ a = 'sensor'; id = 'meldung'; name = (T 'mqtt.name.meldung'); tpl = '{{ value_json.meldung }}'; icon = 'mdi:message-text-outline'; immer = $true }
        @{ a = 'binary_sensor'; id = 'sucht'; name = (T 'mqtt.name.sucht'); tpl = "{{ 'ON' if value_json.zustand == 'laeuft' else 'OFF' }}"; dc = 'running'; immer = $true }
        @{ a = 'binary_sensor'; id = 'treffer'; name = (T 'mqtt.name.treffer'); tpl = "{{ 'ON' if value_json.treffer else 'OFF' }}"; icon = 'mdi:trophy'; immer = $true }
        @{ a = 'sensor'; id = 'share'; name = (T 'mqtt.name.share'); tpl = '{{ value_json.share }}'; icon = 'mdi:numeric'; immer = $true }
        @{ a = 'sensor'; id = 'fortschritt'; name = (T 'mqtt.name.fortschritt'); tpl = '{{ (value_json.anteil * 100) | round(3) }}'; unit = '%'; sc = 'measurement'; icon = 'mdi:progress-check'; immer = $true }
        @{ a = 'sensor'; id = 'abgesucht'; name = (T 'mqtt.name.abgesucht'); tpl = '{{ value_json.abgesucht }}'; icon = 'mdi:check-all'; cat = 'diagnostic'; immer = $true }
        @{ a = 'sensor'; id = 'tempo'; name = (T 'mqtt.name.tempo'); tpl = '{{ (value_json.tempo / 1000000) | int }}'; unit = 'MKey/s'; sc = 'measurement'; icon = 'mdi:speedometer' }
        @{ a = 'sensor'; id = 'rest'; name = (T 'mqtt.name.rest'); tpl = '{% if value_json.rest is number %}{{ (value_json.rest / 86400) | round(2) }}{% else %}None{% endif %}'; unit = 'd'; dc = 'duration'; prec = 1 }
        @{ a = 'sensor'; id = 'leistung'; name = (T 'mqtt.name.leistung'); tpl = '{{ value_json.watt }}'; unit = 'W'; dc = 'power'; sc = 'measurement' }
        @{ a = 'sensor'; id = 'temperatur'; name = (T 'mqtt.name.temperatur'); tpl = '{{ value_json.grad }}'; unit = '°C'; dc = 'temperature'; sc = 'measurement' }
        @{ a = 'sensor'; id = 'luefter'; name = (T 'mqtt.name.luefter'); tpl = '{{ value_json.luefter }}'; unit = '%'; sc = 'measurement'; icon = 'mdi:fan' }
        @{ a = 'sensor'; id = 'auslastung'; name = (T 'mqtt.name.auslastung'); tpl = '{{ value_json.last }}'; unit = '%'; sc = 'measurement'; icon = 'mdi:chip' }
        @{ a = 'sensor'; id = 'vram'; name = (T 'mqtt.name.vram'); tpl = '{{ value_json.vram }}'; unit = 'MB'; dc = 'data_size'; sc = 'measurement'; cat = 'diagnostic'; prec = 0 }
        @{ a = 'sensor'; id = 'vram_fremd'; name = (T 'mqtt.name.vramFremd'); tpl = '{{ value_json.vramFremd }}'; unit = 'MB'; dc = 'data_size'; sc = 'measurement'; cat = 'diagnostic'; prec = 0 }
        @{ a = 'sensor'; id = 'energie'; name = (T 'mqtt.name.energie'); tpl = '{{ value_json.kwh }}'; unit = 'kWh'; dc = 'energy'; sc = 'total_increasing'; prec = 3 }
        @{ a = 'sensor'; id = 'motor'; name = (T 'mqtt.name.motor'); tpl = '{{ value_json.motor }}'; icon = 'mdi:application-cog'; cat = 'diagnostic' }
        @{ a = 'switch'; id = 'suche'; name = (T 'mqtt.name.suche'); tpl = "{{ 'ON' if value_json.zustand == 'laeuft' else 'OFF' }}"; on = 'suche_an'; off = 'suche_aus'; icon = 'mdi:magnify' }
        # bis 15.09.2026 gab es statt des Schalters zwei Knoepfe (button pause/weiter) - Start-Mqtt loescht sie in HA
    )
    if ($VramPauseMB -gt 0 -or $OllamaApi) {
        $liste += @{ a = 'switch'; id = 'automatik'; name = (T 'mqtt.name.automatik'); tpl = "{{ 'ON' if value_json.automatik else 'OFF' }}"; on = 'auto_an'; off = 'auto_aus'; icon = 'mdi:robot' }
    }
    if ($OllamaApi) {
        $liste += @{ a = 'binary_sensor'; id = 'ollama'; name = (T 'mqtt.name.ollama'); tpl = "{{ 'ON' if value_json.ollama and value_json.ollama.aktiv else 'OFF' }}"; icon = 'mdi:head-cog' }
    }
    if ($WebPort -gt 0) {
        $liste += @{ a = 'switch'; id = 'webseite'; name = (T 'mqtt.name.webseite'); tpl = "{{ 'ON' if value_json.web else 'OFF' }}"; on = 'web_an'; off = 'web_aus'; icon = 'mdi:web' }
    }
    foreach ($x in $liste) {
        $c = [ordered]@{ name = $x.name; unique_id = "${knoten}_$($x.id)"; has_entity_name = $true; device = $geraet }
        if (-not $x.immer) { $c.availability_topic = $script:mqAvail }
        if ($x.a -eq 'button') {
            $c.command_topic = $script:mqSet; $c.payload_press = $x.press
        } else {
            $c.state_topic = $script:mqState; $c.value_template = $x.tpl
            if ($x.a -eq 'switch') { $c.command_topic = $script:mqSet; $c.payload_on = $x.on; $c.payload_off = $x.off; $c.state_on = 'ON'; $c.state_off = 'OFF' }
        }
        if ($x.unit) { $c.unit_of_measurement = $x.unit }
        if ($x.dc)   { $c.device_class = $x.dc }
        if ($x.sc)   { $c.state_class = $x.sc }
        if ($x.icon) { $c.icon = $x.icon }
        if ($x.cat)  { $c.entity_category = $x.cat }
        if ($null -ne $x.prec) { $c.suggested_display_precision = $x.prec }
        $topic = "$MqttDiscovery/$($x.a)/$knoten/$($x.id)/config"
        $json = $c | ConvertTo-Json -Depth 5 -Compress
        ,@($topic, $json)
    }
}

function Start-Mqtt {
    if (-not $MqttHost) { return }
    $name = (("$pc-gpu$dev").ToLower() -replace '[^a-z0-9_-]', '_')
    $knoten = 'heuhaufen_' + ($name -replace '-', '_')
    $script:mqBase  = "$MqttTopic/$name"
    $script:mqAvail = "$script:mqBase/availability"
    $script:mqState = "$script:mqBase/state"
    $script:mqSet   = "$script:mqBase/set"
    try {
        # Client-ID mit Prozessnummer: der Broker laesst je ID nur eine Verbindung zu und wirft die aeltere hinaus. Ohne PID
        # verdraengten sich zwei Dashboards desselben Rechners und derselben GPU gegenseitig (15.09.2026: echtes Dashboard
        # und Testordner). Ohne gespeicherte Sitzung (Clean Session) hat eine wechselnde ID keinen Nachteil.
        $script:mqtt = New-Object Heu.Mqtt -ArgumentList $MqttHost, ([int]$MqttPort), "hh-$pc-gpu$dev-$PID", $script:mqAvail
        if ($MqttDiscovery) {
            $disc = @(Get-MqttDiscovery $knoten)
            foreach ($d in $disc) { $script:mqtt.AddOnConnect($d[0], $d[1]) }
            # Eintraege, die es mit dieser Config nicht (mehr) gibt, in HA entfernen: leere retained Discovery-Nachricht.
            # Sonst bleiben sie stehen, z. B. Auto-Pause und "Ollama rechnet" nach dem Auskommentieren von $OllamaApi
            # (15.09.2026 bei zwei Karten gesehen), und die alten Knoepfe Pause/Weiter (bis 15.09.2026).
            $daTopics = @($disc | ForEach-Object { $_[0] })
            foreach ($alt in 'button/pause', 'button/weiter', 'switch/automatik', 'binary_sensor/ollama', 'switch/webseite') {
                $teil = $alt.Split('/')
                $tAlt = "$MqttDiscovery/$($teil[0])/$knoten/$($teil[1])/config"
                if ($daTopics -notcontains $tAlt) { $script:mqtt.AddOnConnect($tAlt, '') }
            }
        }
        if ($MqttUser) { $script:mqtt.User = "$MqttUser"; $script:mqtt.Password = "$MqttPass" }
        $script:mqtt.AddOnConnect($script:mqAvail, 'online')
        $script:mqtt.AddSubscription($script:mqSet)
        $script:mqtt.Start()
    } catch {
        $script:mqtt = $null
        Write-MqttLog (T 'mqtt.log.startFehler' $_.Exception.Message)
        $script:status = (T 'mqtt.status.startFehler')
    }
    $script:mqZustand = ''; $script:mqZeit = [datetime]::MinValue; $script:mqConnects = 0
    $script:mqFehler = ''; $script:mqLetzt = ''; $script:mqWarVerbunden = $false
}

# Fehlertexte aus Heu.Mqtt (dort deutsch) in der Sprache des Benutzers
function Get-MqttFehlerText([string]$f) {
    switch -Regex ($f) {
        '^Broker antwortet nicht mehr$'           { return (T 'mqtt.fehler.brokerStumm') }
        '^Broker hat die Verbindung getrennt$'    { return (T 'mqtt.fehler.getrennt') }
        '^Verbindung beendet$'                    { return (T 'mqtt.fehler.beendet') }
        '^Broker verlangt Anmeldung'              { return (T 'mqtt.fehler.anmeldung') }
        '^Broker lehnt die Anmeldung ab$'         { return (T 'mqtt.fehler.abgelehnt') }
        '^Benutzer oder Passwort falsch$'         { return (T 'mqtt.fehler.passwort') }
        '^(.+) antwortet nicht$'                  { return (T 'mqtt.fehler.hostStumm' $matches[1]) }
    }
    $f
}

# Aus Write-Status: Momentaufnahme senden - sofort bei neuem Zustand oder neuer Verbindung, sonst alle $MqttSek s
function Send-MqttStatus([string]$json, [string]$zustand) {
    $m = $script:mqtt
    if (-not $m) { return }
    $script:mqLetzt = $json
    if ($m.Connected -and -not $script:mqWarVerbunden) {
        $script:mqWarVerbunden = $true; $script:mqFehler = ''
        Write-MqttLog (T 'mqtt.log.verbunden' "${MqttHost}:$MqttPort" $script:mqBase)
        # nur, wenn nichts Wichtigeres dasteht (Startmeldung wie "Bereit - beim letzten Mal pausiert", Profil-Hinweis)
        if (-not $script:status -or $script:status -like 'MQTT*') { $script:status = (T 'mqtt.status.verbunden' "${MqttHost}:$MqttPort") }
    } elseif (-not $m.Connected -and $m.LastError -and $m.LastError -ne $script:mqFehler) {
        $script:mqFehler = $m.LastError
        Write-MqttLog (T 'mqtt.log.keineVerbindung' (Get-MqttFehlerText $m.LastError))
        $script:status = (T 'mqtt.status.keineVerbindung' (Get-MqttFehlerText $m.LastError))
        $script:mqWarVerbunden = $false
    }
    if (-not $m.Connected) { return }
    # "gestoppt" steht nur einen Augenblick zwischen zwei Bloecken an (Suchprogramm fertig, das naechste startet in der
    # folgenden Runde) - nicht melden, sonst flackert "Sucht" in Home Assistant. Echte Enden heissen beendet/crash.
    if ($zustand -eq 'gestoppt') { return }
    $jetzt = Get-Date
    # sofort senden, wenn sich etwas aendert, das Home Assistant gleich zeigen soll (Zustand, Automatik, Treffer) -
    # sonst springt z. B. der Schalter Auto-Pause bis zum naechsten Takt zurueck
    $kern = $zustand + '|' + [regex]::Match($json, '"automatik":(true|false)').Groups[1].Value + '|' + [regex]::Match($json, '"treffer":(true|false)').Groups[1].Value + '|' + [regex]::Match($json, '"web":(true|false)').Groups[1].Value
    if ($kern -ne $script:mqZustand -or $m.Connects -ne $script:mqConnects -or ($jetzt - $script:mqZeit).TotalSeconds -ge $MqttSek) {
        if ($m.Publish($script:mqState, $json, $true)) {
            $script:mqZustand = $kern; $script:mqZeit = $jetzt; $script:mqConnects = $m.Connects
        }
    }
}

# Aus Read-Befehl (alle 500 ms): Befehl von Home Assistant wie einen Tastendruck behandeln.
# Retained Befehle werden verworfen, sonst pausiert jeder Neustart erneut.
function Read-MqttBefehl {
    $m = $script:mqtt
    if (-not $m) { return '' }
    $e = $null
    while ($m.Incoming.TryDequeue([ref]$e)) {
        if ($e[2] -eq '1') { continue }
        switch ("$($e[1])".Trim().ToLower()) {
            'pause'    { if (-not $script:paused) { return 'P' } }
            'weiter'   { if ($script:paused) { return 'P' } }
            'start'    { if ($script:paused) { return 'P' } }
            'suche_an'  { if ($script:paused) { return 'P' } }        # Schalter Suche: wie Taste P, auch aus einer Auto-Pause
            'suche_aus' { if (-not $script:paused) { return 'P' } }   # Pause von Hand - die Automatik setzt sie nicht fort
            'web_an'   { if (-not $script:webAn) { return 'W' } }         # Schalter Webseite: wie Taste W
            'web_aus'  { if ($script:webAn) { return 'W' } }
            'auto_an'  { if (-not $script:vramAuto) { return 'V' } }
            'auto_aus' { if ($script:vramAuto) { return 'V' } }
        }
    }
    ''
}

# Ende: letzten Zustand senden (beim Schliessen mit X selbst gebaut, weil Write-Status dann nichts mehr tut),
# dann "offline" und abmelden. Ohne Aufruf (Absturz, Prozess beendet) meldet der Broker den Last Will.
function Stop-Mqtt([string]$meldungX) {
    $m = $script:mqtt
    if (-not $m) { return }
    $script:mqtt = $null
    try {
        if ($meldungX -and $m.Connected -and $script:mqLetzt) {
            $j = $script:mqLetzt -replace '"zustand":"[^"]*"', '"zustand":"beendet"'
            $j = $j -replace '"meldung":"(?:[^"\\]|\\.)*"', ('"meldung":"' + $meldungX + '"')
            $j = $j -replace '"zeit":"[^"]*"', ('"zeit":"' + (Get-Date).ToString('s') + '"')
            [void]$m.Publish($script:mqState, $j, $true)
        }
        $m.Stop()
    } catch { }
}
