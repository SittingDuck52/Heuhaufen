# tray.ps1 - Symbol im Infobereich (Tray) statt sichtbarem Fenster. Geladen von puzzle.ps1 bei $Fenster = 'tray'.
#
# Das Symbol laeuft in einem eigenen Thread mit eigener Nachrichtenschleife (Menue und Klicks reagieren sofort,
# die Suche wird nicht aufgehalten). Menuebefehle landen in einer Warteschlange und werden in Read-Befehl wie
# Tasten behandelt. Linksklick zeigt/versteckt das Fenster, Minimieren schickt es wieder in den Tray.

if (-not ('Heu.Tray' -as [type])) {
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System;
using System.Collections.Concurrent;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace Heu {
public class Tray {
    [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);

    readonly IntPtr hwnd; readonly string iconPath;
    public readonly ConcurrentQueue<string> Befehle = new ConcurrentQueue<string>();
    public volatile string Text = "Heuhaufen";      // Tooltip (hoechstens 63 Zeichen)
    public volatile bool Suche, Auto, Web, AutoMoeglich, WebMoeglich;
    public volatile bool Bereit;                     // Symbol angelegt
    public volatile string Fehler = "";
    public volatile string AnzeigeText = "";         // was gerade im Tooltip steht
    public string TxtZeigen = "Fenster zeigen", TxtVerstecken = "Fenster verstecken", TxtSuche = "Suche", TxtAuto = "Auto-Pause", TxtWeb = "Webseite", TxtEnde = "Beenden";   // aus der Sprachdatei
    volatile bool stop;
    Thread thread;

    public Tray(IntPtr hwnd, string iconPath) { this.hwnd = hwnd; this.iconPath = iconPath; }
    public bool FensterSichtbar { get { return hwnd != IntPtr.Zero && IsWindowVisible(hwnd); } }
    public void Start() {
        thread = new Thread(Run); thread.IsBackground = true; thread.Name = "Tray";
        thread.SetApartmentState(ApartmentState.STA); thread.Start();
    }
    public void Zeigen() { if (hwnd == IntPtr.Zero) return; ShowWindow(hwnd, 9); SetForegroundWindow(hwnd); }   // SW_RESTORE
    public void ZeigenOhneFokus() { if (hwnd != IntPtr.Zero) ShowWindow(hwnd, 4); }                           // SW_SHOWNOACTIVATE
    public void Verstecken() { if (hwnd != IntPtr.Zero) ShowWindow(hwnd, 0); }                                // SW_HIDE
    public void Umschalten() { if (FensterSichtbar && !IsIconic(hwnd)) Verstecken(); else Zeigen(); }
    public void Stop() { stop = true; if (thread != null) thread.Join(1500); }

    void Run() {
        NotifyIcon icon = null;
        try {
            icon = new NotifyIcon();
            try { icon.Icon = File.Exists(iconPath) ? new Icon(iconPath, 16, 16) : SystemIcons.Application; }
            catch { icon.Icon = SystemIcons.Application; }
            icon.Text = "Heuhaufen";
            ContextMenuStrip menu = new ContextMenuStrip();
            ToolStripMenuItem fenster = new ToolStripMenuItem(TxtZeigen);
            ToolStripMenuItem suche = new ToolStripMenuItem(TxtSuche);
            ToolStripMenuItem auto = new ToolStripMenuItem(TxtAuto);
            ToolStripMenuItem web = new ToolStripMenuItem(TxtWeb);
            ToolStripMenuItem ende = new ToolStripMenuItem(TxtEnde);
            fenster.Font = new Font(fenster.Font, FontStyle.Bold);
            fenster.Click += delegate { Umschalten(); };
            suche.Click += delegate { Befehle.Enqueue(Suche ? "suche_aus" : "suche_an"); };
            auto.Click += delegate { Befehle.Enqueue(Auto ? "auto_aus" : "auto_an"); };
            web.Click += delegate { Befehle.Enqueue(Web ? "web_aus" : "web_an"); };
            ende.Click += delegate { Befehle.Enqueue("beenden"); };
            menu.Items.Add(fenster);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(suche); menu.Items.Add(auto); menu.Items.Add(web);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(ende);
            menu.Opening += delegate {
                fenster.Text = (FensterSichtbar && !IsIconic(hwnd)) ? TxtVerstecken : TxtZeigen;
                suche.Checked = Suche;
                auto.Checked = Auto; auto.Enabled = AutoMoeglich;
                web.Checked = Web; web.Enabled = WebMoeglich;
            };
            icon.ContextMenuStrip = menu;
            icon.MouseClick += delegate(object s, MouseEventArgs e) { if (e.Button == MouseButtons.Left) Umschalten(); };
            icon.Visible = true;
            Bereit = true;
            System.Windows.Forms.Timer timer = new System.Windows.Forms.Timer();
            timer.Interval = 250;
            timer.Tick += delegate {
                if (stop) { timer.Stop(); icon.Visible = false; Application.ExitThread(); return; }
                string t = Text ?? "Heuhaufen";
                if (t.Length > 63) t = t.Substring(0, 62) + "…";
                if (icon.Text != t) { icon.Text = t; AnzeigeText = t; }
                // Minimieren schickt das Fenster wieder in den Tray (keine Taskleisten-Schaltflaeche)
                if (hwnd != IntPtr.Zero && IsWindowVisible(hwnd) && IsIconic(hwnd)) ShowWindow(hwnd, 0);
            };
            timer.Start();
            Application.Run();
        } catch (Exception e) {
            Fehler = e.Message;
        } finally {
            if (icon != null) { try { icon.Visible = false; icon.Dispose(); } catch { } }
        }
    }
}
}
"@
}

# Symbol anlegen und das Konsolenfenster verstecken
function Start-Tray {
    $h = [Heu.Tray]::GetConsoleWindow()
    $script:tray = New-Object Heu.Tray -ArgumentList $h, (Join-Path $PSScriptRoot 'puzzle.ico')
    $script:tray.TxtZeigen = (T 'tray.menu.zeigen'); $script:tray.TxtVerstecken = (T 'tray.menu.verstecken')
    $script:tray.TxtSuche = (T 'tray.menu.suche'); $script:tray.TxtAuto = (T 'tray.menu.auto'); $script:tray.TxtWeb = (T 'tray.menu.web'); $script:tray.TxtEnde = (T 'tray.menu.ende')
    $script:tray.Start()
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not $script:tray.Bereit -and -not $script:tray.Fehler -and $sw.ElapsedMilliseconds -lt 5000) { Start-Sleep -Milliseconds 50 }
    if (-not $script:tray.Bereit) {
        $script:status = (T 'dash.status.trayFehler' $(if ($script:tray.Fehler) { $script:tray.Fehler } else { (T 'tray.keineAntwort') }))
        $script:tray = $null
        return
    }
    $script:tray.Verstecken()
    # Unter Windows Terminal gibt es kein echtes Konsolenfenster - dann bleibt nur das Symbol
    if ($h -eq [IntPtr]::Zero) { $script:status = (T 'tray.keinFenster') }
}

# Aus Write-Status: Tooltip und Häkchen im Menü
function Update-Tray([string]$zustand) {
    $t = $script:tray
    if (-not $t) { return }
    $name = switch ($zustand) {
        'laeuft'       { (T 'mqtt.z.laeuft') }
        'gestoppt'     { (T 'mqtt.z.laeuft') }      # nur ein Augenblick zwischen zwei Blöcken
        'pause'        { (T 'mqtt.z.pause') }
        'pause-hand'   { (T 'mqtt.z.pause') }
        'pause-vram'   { (T 'mqtt.z.pauseVram') }
        'pause-ollama' { (T 'mqtt.z.pauseOllama') }
        'pause-wartet' { (T 'mqtt.z.bereit') }
        'crash'        { (T 'mqtt.z.crash') }
        'found'        { (T 'mqtt.z.treffer') }
        'solved'       { (T 'mqtt.z.geloest') }
        default        { $zustand }
    }
    $teile = @(("Heuhaufen GPU $dev"), $name)
    if ($zustand -eq 'laeuft' -and $script:speed -gt 0) { $teile += (F '{0:N0} MKey/s' ($script:speed / 1e6)) }
    $teile += (F '{0:N2} %' ($script:frac * 100))
    $t.Text = $teile -join ' · '
    $t.Suche = -not $script:paused
    $t.Auto = [bool]$script:vramAuto
    $t.Web = [bool]$script:webAn
    $t.AutoMoeglich = [bool](($VramPauseMB -gt 0 -or $OllamaApi) -and -not $script:paused)   # Taste V wirkt nur ohne Pause
    $t.WebMoeglich = [bool]($WebPort -gt 0)
}

# Aus Read-Befehl (alle 500 ms): Klick im Tray-Menü wie einen Tastendruck behandeln
function Read-TrayBefehl {
    $t = $script:tray
    if (-not $t) { return '' }
    $b = $null
    while ($t.Befehle.TryDequeue([ref]$b)) {
        switch ($b) {
            'beenden'   { return 'TrayEnde' }
            'suche_an'  { if ($script:paused) { return 'P' } }
            'suche_aus' { if (-not $script:paused) { return 'P' } }
            'auto_an'   { if (-not $script:vramAuto) { return 'V' } }
            'auto_aus'  { if ($script:vramAuto) { return 'V' } }
            'web_an'    { if (-not $script:webAn) { return 'W' } }
            'web_aus'   { if ($script:webAn) { return 'W' } }
        }
    }
    ''
}

# Symbol entfernen; -Zeigen macht das Fenster wieder sichtbar (ohne Fokus zu stehlen)
function Stop-Tray([switch]$Zeigen) {
    $t = $script:tray
    if (-not $t) { return }
    $script:tray = $null
    if ($Zeigen) { try { $t.ZeigenOhneFokus() } catch { } }
    try { $t.Stop() } catch { }
}
