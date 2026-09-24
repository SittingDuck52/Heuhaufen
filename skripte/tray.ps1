# tray.ps1 - Symbol im Infobereich (Tray) statt sichtbarem Fenster. Geladen von puzzle.ps1 bei $Fenster = 'tray'.
#
# Das Symbol laeuft in einem eigenen Thread mit eigener Nachrichtenschleife (Menue und Klicks reagieren sofort,
# die Suche wird nicht aufgehalten). Menuebefehle landen in einer Warteschlange und werden in Read-Befehl wie
# Tasten behandelt. Linksklick zeigt/versteckt das Fenster, Minimieren schickt es wieder in den Tray.

if (-not ('Heu.Tray' -as [type])) {
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System;
using System.Collections.Concurrent;
using System.Diagnostics;
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
    public string TxtUeber = "Über …", TxtZweck = "", TxtSpenden = "Spenden", TxtOnchain = "Bitcoin", TxtLightning = "Lightning", TxtSchliessen = "Schließen";
    public string AppTitel = "Heuhaufen", GithubUrl = "", BtcAdresse = "", LnAdresse = "", BildOrdner = "";
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
    public void Stop() { try { if (aboutForm != null && !aboutForm.IsDisposed) aboutForm.BeginInvoke((MethodInvoker)delegate { aboutForm.Close(); }); } catch { } stop = true; if (thread != null) thread.Join(1500); }

    // ---------- Fenster "Ueber Heuhaufen" ----------
    // Laeuft im STA-Thread des Tray-Symbols, also nicht modal (Show statt ShowDialog) - sonst waere
    // das Menue blockiert, solange das Fenster offen ist. Die Suche laeuft in einem anderen Thread.
    Form aboutForm;
    PictureBox Bild(string datei, int x, int y, int px) {
        PictureBox b = new PictureBox();
        b.Location = new Point(x, y); b.Size = new Size(px, px);
        b.SizeMode = PictureBoxSizeMode.Zoom;
        try {
            string f = Path.Combine(BildOrdner ?? "", datei);
            if (File.Exists(f)) using (var s = new FileStream(f, FileMode.Open, FileAccess.Read)) b.Image = Image.FromStream(s);
        } catch { }
        return b;
    }
    Label Zeile(string s, int x, int y, int w, float pt, bool fett, ContentAlignment aus) {
        Label l = new Label();
        l.Text = s; l.Location = new Point(x, y); l.Size = new Size(w, (int)(pt * 2.2f));
        l.Font = new Font("Segoe UI", pt, fett ? FontStyle.Bold : FontStyle.Regular);
        l.TextAlign = aus; l.AutoSize = false;
        return l;
    }
    TextBox Adresse(string s, int x, int y, int w) {
        TextBox t = new TextBox();
        t.Text = s; t.Location = new Point(x, y); t.Size = new Size(w, 18);
        t.ReadOnly = true; t.BorderStyle = BorderStyle.None; t.TextAlign = HorizontalAlignment.Center;
        t.Font = new Font("Consolas", 8f); t.BackColor = Color.White;
        return t;
    }
    public void ZeigeAbout() {
        if (aboutForm != null && !aboutForm.IsDisposed) { aboutForm.Activate(); return; }
        Form f = new Form();
        f.Text = TxtUeber.Replace("…", "").Replace("...", "").Trim();
        f.FormBorderStyle = FormBorderStyle.FixedDialog;
        f.MaximizeBox = false; f.MinimizeBox = false; f.ShowInTaskbar = true;
        f.StartPosition = FormStartPosition.CenterScreen;
        f.ClientSize = new Size(400, 556);
        f.BackColor = Color.White;
        try { if (File.Exists(iconPath)) f.Icon = new Icon(iconPath, 32, 32); } catch { }

        f.Controls.Add(Bild("logo.png", 136, 12, 128));
        f.Controls.Add(Zeile(AppTitel, 0, 148, 400, 13f, true, ContentAlignment.MiddleCenter));
        Label zweck = Zeile(TxtZweck, 20, 176, 360, 9f, false, ContentAlignment.TopCenter);
        zweck.Size = new Size(360, 36);
        f.Controls.Add(zweck);

        LinkLabel link = new LinkLabel();
        link.Text = GithubUrl; link.Location = new Point(0, 218); link.Size = new Size(400, 20);
        link.TextAlign = ContentAlignment.MiddleCenter; link.Font = new Font("Segoe UI", 9f);
        link.LinkClicked += delegate {
            try { Process.Start(new ProcessStartInfo(GithubUrl) { UseShellExecute = true }); } catch { }
        };
        f.Controls.Add(link);

        Label linie = new Label();
        linie.Location = new Point(20, 248); linie.Size = new Size(360, 1); linie.BorderStyle = BorderStyle.Fixed3D;
        f.Controls.Add(linie);

        f.Controls.Add(Zeile(TxtSpenden, 0, 258, 400, 10f, true, ContentAlignment.MiddleCenter));
        f.Controls.Add(Bild("btc-qr.png", 24, 286, 160));
        f.Controls.Add(Bild("ln-qr.png", 216, 286, 160));
        f.Controls.Add(Zeile(TxtOnchain, 24, 452, 160, 8.5f, false, ContentAlignment.MiddleCenter));
        f.Controls.Add(Zeile(TxtLightning, 216, 452, 160, 8.5f, false, ContentAlignment.MiddleCenter));
        f.Controls.Add(Adresse(BtcAdresse, 24, 476, 352));
        f.Controls.Add(Adresse(LnAdresse, 24, 496, 352));

        Button ok = new Button();
        ok.Text = TxtSchliessen; ok.Location = new Point(296, 520); ok.Size = new Size(84, 26);
        ok.Click += delegate { f.Close(); };
        f.Controls.Add(ok);
        f.AcceptButton = ok; f.CancelButton = ok;

        aboutForm = f;
        f.FormClosed += delegate { aboutForm = null; };
        f.Show(); f.Activate();
    }

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
            ToolStripMenuItem ueber = new ToolStripMenuItem(TxtUeber);
            ToolStripMenuItem ende = new ToolStripMenuItem(TxtEnde);
            fenster.Font = new Font(fenster.Font, FontStyle.Bold);
            fenster.Click += delegate { Umschalten(); };
            suche.Click += delegate { Befehle.Enqueue(Suche ? "suche_aus" : "suche_an"); };
            auto.Click += delegate { Befehle.Enqueue(Auto ? "auto_aus" : "auto_an"); };
            web.Click += delegate { Befehle.Enqueue(Web ? "web_aus" : "web_an"); };
            ueber.Click += delegate { ZeigeAbout(); };
            ende.Click += delegate { Befehle.Enqueue("beenden"); };
            menu.Items.Add(fenster);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(suche); menu.Items.Add(auto); menu.Items.Add(web);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add(ueber);
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
    # Fenster "Ueber Heuhaufen": Texte aus der Sprachdatei, Bilder aus skripte\about\
    $script:tray.TxtUeber = (T 'tray.menu.ueber'); $script:tray.TxtZweck = (T 'tray.about.zweck')
    $script:tray.TxtSpenden = (T 'tray.about.spenden'); $script:tray.TxtOnchain = (T 'tray.about.onchain')
    $script:tray.TxtLightning = (T 'tray.about.lightning'); $script:tray.TxtSchliessen = (T 'tray.about.schliessen')
    $script:tray.AppTitel = "$AppName $AppVersion"
    $script:tray.GithubUrl = 'https://github.com/SittingDuck52/Heuhaufen'
    $script:tray.BtcAdresse = 'bc1q63tve4ch6lfffavfr20nqf2vct4taac3r68enm'
    $script:tray.LnAdresse = 'heuhaufen@strike.me'
    $script:tray.BildOrdner = (Join-Path $PSScriptRoot 'about')
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
