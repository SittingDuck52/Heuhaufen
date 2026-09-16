# puzzle.ps1 - BitCrack Bitcoin-Puzzle-Suche mit Live-Dashboard (eine oder mehrere GPUs)
param(
    [string]$Device = 'all',   # 'all' = je GPU ein Fenster, sonst GPU-Index (0, 1, ...)
    [int]$Count = 1,           # intern: Anzahl der Fenster (Anordnung)
    [int]$Slot  = 0,           # intern: Position dieses Fensters
    [switch]$Sofort            # trotz $StartWartet gleich mit der Suche beginnen (nutzt solar.ps1)
)

# ================= Standard-Einstellungen =================
$PowerLimit  = 0                      # Watt pro Karte, 0 = Einstellung der Karte nicht anfassen (Standard seit 16.09.2026;
                                      # vorher 150 - auf fremder Hardware ohne Config unerwartet)
$Tuning      = '-b 32 -t 256 -p 512'
$Engine          = 'cyclone'          # Suchprogramm: 'cyclone' (CUDACyclone, deutlich schneller) oder 'bitcrack'
$CycloneGrid     = '512,512'          # CUDACyclone: --grid (Punkte je Paket, Pakete je Thread)
$CycloneSlices   = 0                  # CUDACyclone: --slices; 0 = Standard des Programms
$CycloneBlockSec = 240                # CUDACyclone: Ziel-Dauer eines Blocks in s (mehr geht bei einer Pause nicht verloren)
$CycloneResumeSec = 1800              # dasselbe, wenn CUDACyclone fortsetzen kann (--resume-batches): eine Pause kostet dann nur ein Haeppchen
$GpuProfiles = $null                  # Profile je Grafikkarte, siehe puzzle-config.ps1
$PricePerKwh = 0.30                   # EUR/kWh fuer die Kostenanzeige
$RefreshSec  = 1                       # Takt des Dashboards in s (seit 14.09.2026 1 statt 2; eine Runde kostet ~0,2 s Arbeit)
$Puzzle      = 71                     # Puzzle-Nummer: Adresse und Bereich werden daraus bestimmt
$Address     = ''                     # leer = aus der Tabelle unten; nur fuer Sonderfaelle/Tests setzen
$MempoolApi  = 'https://mempool.space/api'   # Adresspruefung (oder eigene Mempool-Instanz)
$CheckMin    = 15                     # Minuten zwischen den Pruefungen
$RangeStart  = ''                     # leer = 2^(Puzzle-1)
$RangeEnd    = ''                     # leer = 2^Puzzle - 1
$Shares      = 1000000
# VRAM-Automatik: pausiert, sobald andere Programme (z. B. Ollama) Speicher der Karte belegen
$VramPauseMB  = 2000                  # ab so viel fremdem VRAM (MB) pausieren; 0 = Automatik aus (Standard seit 15.09.2026)
$VramResumeMB = 0                     # darunter wieder starten; 0 = VramPauseMB - 500
$VramHoldSec  = 6                     # so lange muss der Speicher belegt sein, bevor pausiert wird
$VramBackSec  = 60                    # so lange muss er frei sein, bevor es weitergeht
$VramSelfMB   = 0                     # VRAM-Bedarf von BitCrack; 0 = beim Start selbst messen
$OllamaKeepAlive = ''                 # z. B. '1m': so lange hält Ollama ein Modell; '' = nicht anfassen
# Ollama direkt fragen, statt nur den Speicher zu messen: ein geparktes Modell darf liegen bleiben,
# pausiert wird erst, wenn Ollama wirklich rechnet.
$OllamaApi     = ''                   # z. B. 'http://localhost:11434'; leer = nicht abfragen
$OllamaIdleSec = 30                   # so lange muss Ollama ruhig sein, bevor die Suche weiterläuft
$WebPort       = 0                    # Port der Webseite (web.ps1), 0 = keine Webseite starten
$WebBind       = '+'                  # '+' = im Netz erreichbar, 'localhost' = nur dieser Rechner
$StartWartet   = $false               # $true: Fenster öffnet sich, sucht aber erst auf Knopfdruck
                                      # (für den Autostart beim Anmelden; -Sofort übergeht das)
# MQTT (z. B. Home Assistant): Werte melden und Befehle annehmen, siehe skripte\mqtt.ps1
$MqttHost      = ''                   # Broker, z. B. 'homeassistant.local' oder '192.168.1.10'; leer = kein MQTT
$MqttPort      = 1883
$MqttUser      = ''                   # nur wenn der Broker eine Anmeldung verlangt; leer = anonym
$MqttPass      = ''
$MqttTopic     = 'heuhaufen'          # Topics: <MqttTopic>/<rechner>-gpu<N>/state, /availability, /set
$MqttDiscovery = 'homeassistant'      # Präfix für Home Assistant Discovery; leer = keine Geräte anlegen
$MqttSek       = 10                   # Momentaufnahme mindestens alle so viele Sekunden (Zustandswechsel sofort)
$WinCols     = 66                   # Fenstergroesse in Zeichen (Rahmen endet in Spalte 64, links wie rechts 2 frei)
$WinRows     = 35
# Schrift des Fensters. Ohne das sieht es je nach Startweg anders aus: powershell.exe und cmd.exe
# haben in Windows getrennte Konsoleneinstellungen. '' = so lassen, wie Windows es vorgibt.
$ConsoleFont     = 'Consolas'         # Alternative: 'Lucida Console'
$ConsoleFontSize = 16                 # Zeichenhöhe in Pixel; 0 = die eingestellte behalten
$Sprache         = ''                 # 'de' oder 'en'; leer = Windows-Anzeigesprache (Deutsch bei deutschem Windows, sonst Englisch)
$Fenster         = 'normal'           # 'normal', 'minimiert' (Taskleiste) oder 'tray' (nur Symbol im Infobereich, skripte\tray.ps1)
# ==========================================================

# Ungeloeste Puzzles ohne bekannten Public Key (Adressen aus mehreren Quellen abgeglichen, Stand 09/2026)
$PuzzleTable = @{
    71 = '1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU'
    72 = '1JTK7s9YVYywfm5XUH7RNhHJH1LshCaRFR'
    73 = '12VVRNPi4SJqUTsp6FmqDqY5sGosDtysn4'
    74 = '1FWGcVDK3JGzCC3WtkYetULPszMaK2Jksv'
    76 = '1DJh2eHFYQfACPmrvpyWc8MSTYKh7w9eRF'
    77 = '1Bxk4CQdqL9p22JEtDfdXMsng1XacifUtE'
    78 = '15qF6X51huDjqTmF9BJgxXdt1xcj46Jmhb'
    79 = '1ARk8HWJMn8js8tQmGUJeQHjSE7KRkn2t8'
}

# Ordner: skripte\ (dieses Skript), programm\ (BitCrack), daten\ (Shares, Fortschritt, Logs, Treffer).
# puzzle-config.ps1 liegt eine Ebene hoeher, direkt im BitCrack-Ordner.
$Basis = Split-Path $PSScriptRoot -Parent
$Daten = Join-Path $Basis 'daten'

# Name und Versionsnummer für Titelzeile, Kopfzeile und Webseite
$AppName = 'Heuhaufen'; $AppVersion = '?'
if (Test-Path (Join-Path $PSScriptRoot 'version.ps1')) { . (Join-Path $PSScriptRoot 'version.ps1') }

# Rechnerspezifische Werte (optional) in puzzle-config.ps1 ueberschreiben die Standardwerte
$cfgFile = Join-Path $Basis 'puzzle-config.ps1'
if (-not (Test-Path $cfgFile)) { $cfgFile = Join-Path $Basis 'puzzle71-config.ps1' }   # alter Name
if (Test-Path $cfgFile) { . $cfgFile }
# Texte in der Sprache des Benutzers (skripte\sprache.ps1, sprache\de.psd1, sprache\en.psd1) - nach der Config, damit $Sprache wirkt
. (Join-Path $PSScriptRoot 'sprache.ps1')
if ($OllamaApi) { $WinRows += 1 }     # eine Zeile mehr für den Ollama-Zustand

$win = $env:SystemRoot
# Aus einem 32-Bit-Programm gestartet? Dann zuerst als 64-Bit-PowerShell neu starten.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    & "$win\Sysnative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "$PSCommandPath" -Device $Device -Count $Count -Slot $Slot
    exit
}
$psExe   = "$win\System32\WindowsPowerShell\v1.0\powershell.exe"
$argLine = "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$PSCommandPath`""
# Klassischer Konsolenhost: nur dort gibt es ein echtes Fenster, das sich anordnen laesst.
# Ist Windows Terminal als Standardterminal eingestellt, waere sonst keine Anordnung moeglich.
$conhost = "$win\System32\conhost.exe"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process $psExe -Verb RunAs -ArgumentList "$argLine -Device $Device -Count $Count -Slot $Slot"
    exit
}

if (-not (Test-Path $Daten)) { New-Item -ItemType Directory -Path $Daten -Force | Out-Null }
Set-Location $Daten
Add-Type -AssemblyName System.Numerics
$de  = $Kultur                        # Zahlen und Datum im Format der Sprache (de-DE bzw. en-US)

# ---------- Puzzle: Adresse und Bereich bestimmen ----------
$Puzzle = [int]$Puzzle
$fromTable = $false
if (-not $Address) {
    $Address = $PuzzleTable[$Puzzle]
    if (-not $Address) { Write-Host (T 'dash.start.keineAdresse' $Puzzle) -ForegroundColor Red; exit 1 }
    $fromTable = $true
}
if (-not $RangeStart) { $RangeStart = [Numerics.BigInteger]::Pow(2, $Puzzle - 1).ToString('x').TrimStart('0') }
if (-not $RangeEnd)   { $RangeEnd   = ([Numerics.BigInteger]::Pow(2, $Puzzle) - 1).ToString('x').TrimStart('0') }
$inv = [Globalization.CultureInfo]::InvariantCulture

$smi = @(
    (Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue).Source
    "$win\System32\nvidia-smi.exe"
    "$env:ProgramW6432\NVIDIA Corporation\NVSMI\nvidia-smi.exe"
) + @(Get-ChildItem "$win\System32\DriverStore\FileRepository\nv*\nvidia-smi.exe" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) |
    Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $smi) { Write-Host (T 'dash.start.keinSmi') -ForegroundColor Red; exit 1 }

# ---------- Alle GPUs: je Karte ein eigenes Fenster starten ----------
if ($Device -eq 'all') {
    $ids = @(& $smi --query-gpu=index --format=csv,noheader | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^\d+$' })
    if ($ids.Count -eq 0) { Write-Host (T 'dash.start.keineGpu') -ForegroundColor Red; exit 1 }
    if ($ids.Count -eq 1) {
        $Device = $ids[0]; $Count = 1; $Slot = 0
    } else {
        for ($i = 0; $i -lt $ids.Count; $i++) {
            $sub = "-Device $($ids[$i]) -Count $($ids.Count) -Slot $i" + $(if ($Sofort) { " -Sofort" } else { "" })
            if (Test-Path $conhost) { Start-Process $conhost -ArgumentList "`"$psExe`" $argLine $sub" }
            else                    { Start-Process $psExe   -ArgumentList "$argLine $sub" }
            Start-Sleep -Milliseconds 1500
        }
        [Environment]::Exit(0)
    }
}
if ($Device -notmatch '^\d+$') { Write-Host (T 'dash.start.ungueltigeGpu' $Device) -ForegroundColor Red; exit 1 }
$dev = [int]$Device

# ---------- Profil passend zur Grafikkarte ----------
$gpuName = "$(& $smi -i $dev --query-gpu=name --format=csv,noheader)".Trim()
$profileName = ''
if ($GpuProfiles) {
    foreach ($k in @($GpuProfiles.Keys)) {
        if ($gpuName -like "*$k*") {
            $pr = $GpuProfiles[$k]
            if (@($pr.Keys) -contains 'PowerLimit')  { $PowerLimit  = $pr['PowerLimit'] }
            if (@($pr.Keys) -contains 'Tuning')      { $Tuning      = $pr['Tuning'] }
            if (@($pr.Keys) -contains 'PricePerKwh') { $PricePerKwh = $pr['PricePerKwh'] }
            if (@($pr.Keys) -contains 'VramPauseMB')  { $VramPauseMB  = $pr['VramPauseMB'] }
            if (@($pr.Keys) -contains 'VramResumeMB') { $VramResumeMB = $pr['VramResumeMB'] }
            if (@($pr.Keys) -contains 'Engine')          { $Engine          = $pr['Engine'] }
            if (@($pr.Keys) -contains 'CycloneGrid')     { $CycloneGrid     = $pr['CycloneGrid'] }
            if (@($pr.Keys) -contains 'CycloneSlices')   { $CycloneSlices   = $pr['CycloneSlices'] }
            if (@($pr.Keys) -contains 'CycloneBlockSec') { $CycloneBlockSec = $pr['CycloneBlockSec'] }
            $profileName = $k
            break
        }
    }
}

# Rueckfall-Schwelle: 500 MB unter der Pausenschwelle, damit es nicht hin und her schaltet
if ($VramPauseMB -gt 0 -and $VramResumeMB -le 0) { $VramResumeMB = [int][math]::Max(0.0, [double]$VramPauseMB - 500.0) }

# ---------- Suchprogramm ----------
$Engine = "$Engine".Trim().ToLower()
if (@('bitcrack', 'cyclone') -notcontains $Engine) { Write-Host (T 'dash.start.unbekanntesProgramm' $Engine) -ForegroundColor Red; exit 1 }
# Standard ist CUDACyclone. Fehlt es (z. B. neue Skripte in einem alten Ordner), mit BitCrack suchen statt abzubrechen.
$motorHinweis = ''
if ($Engine -eq 'cyclone' -and -not (Test-Path (Join-Path $Basis 'programm\CUDACyclone.exe'))) {
    $Engine = 'bitcrack'
    $motorHinweis = (T 'dash.start.cycFehlt')
    Write-Host "   $motorHinweis" -ForegroundColor Yellow
}
$cyc   = ($Engine -eq 'cyclone')
$motor = if ($cyc) { 'CUDACyclone' } else { 'BitCrack' }
if ($cyc) {
    # CUDACyclone kann keine Karte waehlen und nimmt immer die erste sichtbare: nur diese GPU zeigen,
    # in derselben Reihenfolge wie nvidia-smi (PCI-Bus). Gilt fuer die Kindprozesse dieses Fensters.
    $env:CUDA_DEVICE_ORDER    = 'PCI_BUS_ID'
    $env:CUDA_VISIBLE_DEVICES = "$dev"
}

# ---------- Dateien dieser GPU auf diesem Rechner ----------
$pc     = $env:COMPUTERNAME
$sfx    = "-$pc-gpu$dev"
$fShare = "share$Puzzle$sfx.txt"
$fProg  = "progress$Puzzle$sfx.txt"
$fBak   = "progress$Puzzle$sfx.bak"
$fLog   = "bitcrack$Puzzle$sfx.log"
$fErr   = "bitcrack$Puzzle$sfx.err"
$fFound = "found$Puzzle$sfx.txt"
$fLock  = "bitcrack$sfx.lock"
$fDone  = "done$Puzzle$sfx.txt"       # abgesuchte Shares; alle done$Puzzle-*.txt im Ordner werden gemieden
$fStop  = 'solar-stop.flag'           # legt solar.ps1 an, wenn der Solarueberschuss weg ist
$fPause = "pause$sfx.flag"            # zeigt solar.ps1, dass hier von Hand pausiert wurde
$fStat  = "status$Puzzle$sfx.json"    # Momentaufnahme für web.ps1 (enthält nie einen Schlüssel)
$fCmd   = "befehl$Puzzle$sfx.txt"     # ein Wort von der Webseite: pause, weiter, start, auto
$fPid   = "motor$sfx.pid"             # PID von CUDACyclone, um es nach einem harten Abbruch wiederzufinden
$fHist  = "verlauf$Puzzle$sfx.csv"    # eine Zeile je Checkpoint für die Kurve auf der Webseite
$fMerk  = "merken$sfx.json"           # zuletzt gewählt: Webseite, Auto-Pause, ob gesucht wurde (Vorrang vor der Config)
$appTitel = "$AppName $AppVersion · GPU $dev"   # GPU bleibt drin: bei zwei Karten sonst gleiche Fenster in der Taskleiste
$Host.UI.RawUI.WindowTitle = (T 'dash.titel.normal' $appTitel)

# Aeltere Dateinamen dieses Rechners uebernehmen (share71.txt bzw. share71-gpu0.txt)
if (-not (Test-Path $fShare)) {
    $old = $null
    if (Test-Path "share$Puzzle-gpu$dev.txt") { $old = "$Puzzle-gpu$dev" }
    elseif ($Puzzle -eq 71 -and $dev -eq 0 -and (Test-Path share71.txt)) { $old = '71' }
    if ($old) {
        Move-Item "share$old.txt" $fShare
        if (Test-Path "progress$old.txt") { Move-Item "progress$old.txt" $fProg }
        if (Test-Path "progress$old.bak") { Move-Item "progress$old.bak" $fBak }
        Remove-Item "bitcrack$old.log", "bitcrack$old.err" -ErrorAction SilentlyContinue
        Write-Host (T 'dash.start.dateienUebernommen' $fShare $fProg) -ForegroundColor Yellow
    }
}
Remove-Item "bitcrack-gpu$dev.lock", "puzzle71-gpu$dev.lock" -ErrorAction SilentlyContinue
Remove-Item $fPause -ErrorAction SilentlyContinue   # liegengeblieben nach hartem Abbruch: beim Start gibt es keine Pause

$oldFound = Get-ChildItem found*.txt -ErrorAction SilentlyContinue | Select-Object -First 1
if ($oldFound) { Write-Host (T 'dash.start.foundExistiert' $oldFound.Name) -ForegroundColor Red; exit 1 }

# Nur ein Dashboard pro GPU
try { $lock = [IO.File]::Open((Join-Path $Daten $fLock), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
catch { Write-Host (T 'dash.start.dashboardLaeuft' $dev) -ForegroundColor Red; exit 1 }

# Verwaiste BitCrack-Instanz dieser GPU (z. B. nach Schliessen mit X) beenden
$bcExe   = Join-Path $Basis 'programm\cuBitCrack.exe'
$exePath = if ($cyc) { Join-Path $Basis 'programm\CUDACyclone.exe' } else { $bcExe }
if (-not (Test-Path $exePath)) { Write-Host (T 'dash.start.exeFehlt' (Split-Path $exePath -Leaf)) -ForegroundColor Red; exit 1 }
# Kann diese CUDACyclone.exe fortsetzen? Aeltere Fassungen kennen --resume-batches nicht und ignorieren
# unbekannte Optionen stillschweigend - darum am Programm selbst nachsehen (der Hilfetext steht in der exe).
$cycResume = $false
if ($cyc) { try { $cycResume = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($exePath)).Contains('--resume-batches') } catch { } }
function Get-BCProcs {
    @(Get-CimInstance Win32_Process -Filter "Name='cuBitCrack.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $cl = [string]$_.CommandLine
        ($cl -match "(^|\s)-d\s+$dev(\s|$)") -or ($dev -eq 0 -and $cl -notmatch '(^|\s)-d\s+\d')
    })
}
$orphans = @(Get-BCProcs | Where-Object { $_.ExecutablePath -and $_.ExecutablePath -ieq $bcExe })
if ($orphans.Count -gt 0) {
    Write-Host (T 'dash.start.verwaistBc' $dev) -ForegroundColor Yellow
    $orphans | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
}
if ((Get-BCProcs).Count -gt 0) { Write-Host (T 'dash.start.fremdesBc' $dev) -ForegroundColor Red; exit 1 }

# Verwaistes CUDACyclone dieser GPU: seine Kommandozeile nennt keine Karte, darum ueber die gemerkte PID
if ($cyc) {
    $pidFile = Join-Path $Daten $fPid
    $altPid = 0
    if ((Test-Path $pidFile) -and [int]::TryParse("$(Get-Content $pidFile -TotalCount 1)".Trim(), [ref]$altPid) -and $altPid -gt 0) {
        $ap = Get-Process -Id $altPid -ErrorAction SilentlyContinue
        if ($ap -and $ap.Path -and $ap.Path -ieq $exePath) {
            Write-Host (T 'dash.start.verwaistCyc' $dev) -ForegroundColor Yellow
            Stop-Process -Id $altPid -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
    }
}

# ---------- Power-Limit dieser GPU ----------
$plq = (& $smi -i $dev --query-gpu=power.default_limit,power.min_limit,power.max_limit --format=csv,noheader,nounits) -split ',\s*'
$defaultPl = [int][double]::Parse($plq[0].Trim(), $inv)
$minPl     = [int][double]::Parse($plq[1].Trim(), $inv)
$maxPl     = [int][double]::Parse($plq[2].Trim(), $inv)
$usePl = 0
if ($PowerLimit -gt 0) { $usePl = [math]::Max($minPl, [math]::Min($maxPl, [int]$PowerLimit)) }

# Schutz: BitCrack wird beim Schliessen des Fensters mitbeendet, Power-Limit zurueckgesetzt
if (-not ('P71.Guard' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;
namespace P71 {
public static class Guard {
    [StructLayout(LayoutKind.Sequential)]
    struct BASIC { public long PerProcessUserTimeLimit; public long PerJobUserTimeLimit; public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize; public UIntPtr MaximumWorkingSetSize; public uint ActiveProcessLimit;
        public UIntPtr Affinity; public uint PriorityClass; public uint SchedulingClass; }
    [StructLayout(LayoutKind.Sequential)]
    struct IOC { public ulong a, b, c, d, e, f; }
    [StructLayout(LayoutKind.Sequential)]
    struct EXT { public BASIC Basic; public IOC Io; public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed; }
    public delegate bool CtrlHandler(int ctrlType);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr attr, string name);
    [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr job, int cls, ref EXT info, uint len);
    [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll")] static extern bool SetConsoleCtrlHandler(CtrlHandler handler, bool add);
    [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr h, out uint mode);
    [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr h, uint mode);
    static uint savedMode;
    static bool modeSaved;
    public static void DisableQuickEdit() {   // Markieren mit der Maus haelt die Ausgabe sonst an
        IntPtr h = GetStdHandle(-10);
        uint m;
        if (GetConsoleMode(h, out m)) { savedMode = m; modeSaved = true; SetConsoleMode(h, (m & ~0x40u) | 0x80u); }
    }
    public static void RestoreConsoleMode() { if (modeSaved) SetConsoleMode(GetStdHandle(-10), savedMode); }
    static IntPtr job = IntPtr.Zero;
    static CtrlHandler handler;
    static string smiPath;
    static string resetArgs;
    static Process child;
    static string statusPath, pausePath;
    public static string ClosedText = "Fenster geschlossen um {0:HH:mm}";   // kommt aus der Sprachdatei
    public static volatile bool Closing;       // Fenster wird geschlossen: Write-Status schreibt nichts mehr
    public static void SetFiles(string status, string pause) { statusPath = status; pausePath = pause; }
    public static void Init(string smi, string reset) {
        smiPath = smi; resetArgs = reset;
        job = CreateJobObject(IntPtr.Zero, null);
        EXT info = new EXT();
        info.Basic.LimitFlags = 0x2000;   // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
        SetInformationJobObject(job, 9, ref info, (uint)Marshal.SizeOf(typeof(EXT)));
        handler = new CtrlHandler(OnCtrl);
        SetConsoleCtrlHandler(handler, true);
    }
    public static bool Attach(Process p) { child = p; return AssignProcessToJobObject(job, p.Handle); }
    static bool OnCtrl(int type) {
        if (type == 2 || type == 5 || type == 6) {   // Fenster schliessen, Abmelden, Herunterfahren
            Stopwatch uhr = Stopwatch.StartNew();
            Closing = true;
            try { if (child != null && !child.HasExited) child.Kill(); } catch { }
            MarkClosed();
            try {
                if (!String.IsNullOrEmpty(resetArgs)) {
                    ProcessStartInfo psi = new ProcessStartInfo(smiPath, resetArgs);
                    psi.UseShellExecute = false; psi.CreateNoWindow = true;
                    using (Process p = Process.Start(psi)) { p.WaitForExit(3000); }
                }
            } catch { }
            // Windows beendet den Prozess 5 s nach dem Schliessen. Bis dahin bedient das Fenster die Webseite
            // weiter, damit sie den Zustand "beendet" noch abholt (sie fragt alle 2 s).
            if (type == 2) { int rest = 3500 - (int)uhr.ElapsedMilliseconds; if (rest > 0) Thread.Sleep(rest); }
        }
        return false;
    }
    // Das finally von puzzle.ps1 kommt beim Schliessen nicht mehr dran. Darum hier die letzte Meldung
    // fuer die Webseite (zeit, zustand, meldung in der Statusdatei ersetzen) und das Pause-Flag loeschen.
    static void MarkClosed() {
        try { if (!String.IsNullOrEmpty(pausePath) && File.Exists(pausePath)) File.Delete(pausePath); } catch { }
        try {
            if (String.IsNullOrEmpty(statusPath) || !File.Exists(statusPath)) return;
            DateTime jetzt = DateTime.Now;
            string j = File.ReadAllText(statusPath);
            j = Regex.Replace(j, "\"zeit\":\"[^\"]*\"", "\"zeit\":\"" + jetzt.ToString("s") + "\"");
            j = Regex.Replace(j, "\"zustand\":\"[^\"]*\"", "\"zustand\":\"beendet\"");
            j = Regex.Replace(j, "\"meldung\":\"(?:[^\"\\\\]|\\\\.)*\"", "\"meldung\":\"" + String.Format(ClosedText, jetzt).Replace("\"", "'").Replace("\\", "/") + "\"");
            File.WriteAllText(statusPath + ".tmp", j);
            File.Copy(statusPath + ".tmp", statusPath, true);
            File.Delete(statusPath + ".tmp");
        } catch { }
    }
}
}
"@
}
[P71.Guard]::Init($smi, $(if ($usePl -gt 0) { "-i $dev -pl $defaultPl" } else { '' }))
[P71.Guard]::SetFiles((Join-Path $Daten $fStat), (Join-Path $Daten $fPause))
[P71.Guard]::ClosedText = (T 'dash.status.fensterGeschlossen')
[P71.Guard]::DisableQuickEdit()

# ---------- Hilfsfunktionen ----------
function Hex([string]$x) { [Numerics.BigInteger]::Parse('0' + $x, [Globalization.NumberStyles]::AllowHexSpecifier) }
function F([string]$fmt) { [string]::Format($de, $fmt, $args) }

# Alle schon abgesuchten Shares dieses Puzzles: jede Datei done<N>-*.txt im Ordner, erste Zahl je Zeile.
# So genuegt es, die done-Liste eines anderen Rechners hierher zu kopieren, damit beide nicht dieselben Shares suchen.
function Get-DoneShares {
    $h = @{}
    foreach ($f in @(Get-ChildItem (Join-Path $Daten "done$Puzzle-*.txt") -ErrorAction SilentlyContinue)) {
        foreach ($l in @(Get-Content $f.FullName -ErrorAction SilentlyContinue)) {
            if ($l -match '^\s*(\d+)') { $h[$matches[1]] = $true }
        }
    }
    $h
}

# Abgeschlossenen Share protokollieren (beide GPUs schreiben in getrennte Dateien, daher ohne Sperre)
function Add-DoneShare([int]$m) {
    $p = Join-Path $Daten $fDone
    if (-not (Test-Path $p)) {
        Set-Content -Encoding ascii -Path $p -Value "# Puzzle $Puzzle, $pc, GPU $dev - abgesuchte Shares von $Shares (Nummer, Datum, Dauer)"
    }
    $line = '{0,7}  {1:yyyy-MM-dd HH:mm}  {2}' -f $m, (Get-Date), (Fmt-Span $(if ($cpLast) { $cpLast.Elapsed / 1000.0 } else { 0.0 }))
    for ($i = 0; $i -lt 3; $i++) {
        try { Add-Content -Encoding ascii -Path $p -Value $line; return } catch { Start-Sleep -Milliseconds 200 }
    }
}

function Get-Share {
    $p = Join-Path $Daten $fShare
    if (-not (Test-Path $p)) {
        # weder den Share einer anderen GPU in diesem Ordner noch einen schon abgesuchten waehlen
        $used = @(Get-ChildItem (Join-Path $Daten "share$Puzzle-*gpu*.txt") -ErrorAction SilentlyContinue | ForEach-Object { "$(Get-Content $_.FullName -TotalCount 1)".Trim() })
        $done = Get-DoneShares
        $frei = $Shares - $done.Count - $used.Count
        do { $n = Get-Random -Minimum 1 -Maximum ($Shares + 1) } while ((($used -contains "$n") -or $done.ContainsKey("$n")) -and ($frei -gt 0))
        Set-Content -Encoding ascii -Path $p -Value $n
    }
    [int]"$(Get-Content $p -TotalCount 1)".Trim()
}

function Get-ShareRange([int]$m) {
    $s = Hex $RangeStart; $e = Hex $RangeEnd
    $size = [Numerics.BigInteger]::Divide($e - $s + 1, $Shares)
    $first = $s + $size * ($m - 1)
    $last = if ($m -lt $Shares) { $first + $size - 1 } else { $e }
    [pscustomobject]@{ Start = $first; End = $last; Size = $last - $first + 1 }
}

function Read-Checkpoint([string]$file) {
    if (-not $file) { $file = $fProg }
    $path = Join-Path $Daten $file
    try { $txt = [IO.File]::ReadAllText($path) } catch { return $null }
    $h = @{}
    foreach ($l in $txt -split "`r?`n") { if ($l -match '^(\w+)=(.+)$') { $h[$matches[1]] = $matches[2].Trim() } }
    if (-not ($h.start -and $h.next -and $h.end -and $h.elapsed)) { return $null }
    try {
        $next = Hex $h.next
        # CUDACyclone mit Fortsetzen: erledigte Pakete je Faden im laufenden Block. next bleibt dabei am
        # Blockanfang (BitCrack wiederholt den Block schlimmstenfalls), Pos ist die Stelle fuer Anzeige und Tempo.
        $bits = 0; $batches = 0.0; $threads = 0.0; $batch = 0.0
        if ($h.cyc_bits -and $h.cyc_batches -and $h.cyc_threads -and $h.cyc_batch) {
            $bits = [int]$h.cyc_bits
            $batches = [double]::Parse($h.cyc_batches, $inv)
            $threads = [double]::Parse($h.cyc_threads, $inv)
            $batch   = [double]::Parse($h.cyc_batch, $inv)
        }
        $keys = $batches * $batch * $threads
        $pos = $next
        if ($bits -gt 0 -and $keys -gt 0) {
            # Alle Faeden rechnen gleichzeitig ueber den ganzen Block (Kamm): der erledigte Anteil gilt
            # gleichmaessig fuer den neuen Teil des Blocks - ab next, hoechstens bis zum Share-Ende
            $size = [Numerics.BigInteger]::Pow(2, $bits)
            $bs = [Numerics.BigInteger]::Divide($next, $size) * $size
            $neuEnd = [Numerics.BigInteger]::Min($bs + $size - 1, (Hex $h.end))
            $neu = [double]($neuEnd - $next + 1)
            if ($neu -gt 0) { $pos = $next + [Numerics.BigInteger]([math]::Floor([math]::Min(1.0, $keys / [double]$size) * $neu)) }
        }
        [pscustomobject]@{
            Start = Hex $h.start; Next = $next; End = Hex $h.end
            Elapsed = [double]::Parse($h.elapsed, $inv); Raw = $txt
            Time = (Get-Item $path).LastWriteTime
            Pos = $pos; CycBits = $bits; CycBatches = $batches; CycThreads = $threads; CycBatch = $batch
            CycKeys = $keys; CycGrid = "$($h.cyc_grid)"
        }
    } catch { $null }
}

function Restore-Progress($range) {
    $cp = Read-Checkpoint
    if (-not $cp -or $cp.Start -ne $range.Start) {
        $bak = Read-Checkpoint $fBak
        if ($bak -and $bak.Start -eq $range.Start) { Copy-Item $fBak $fProg -Force }
    }
}

# ---------- CUDACyclone ----------
# CUDACyclone sucht nur Bereiche, deren Laenge eine Zweierpotenz ist und die daran ausgerichtet sind, und es
# kann nicht fortsetzen. Darum arbeitet es einen Share Block fuer Block ab. Nach jedem Block schreibt das Skript
# selbst einen Checkpoint im Format von BitCrack: Anzeige, Sicherung, Kurve und done-Liste bleiben gleich,
# und BitCrack koennte an derselben Stelle weitermachen.

function Hex64($v) { ([Numerics.BigInteger]$v).ToString('X').TrimStart('0').PadLeft(64, '0') }

function Write-CycCheckpoint($range, $next, [double]$elapsedMs, $fort = $null) {
    $tb = [regex]::Match($Tuning, '-b\s+(\d+)'); $tt = [regex]::Match($Tuning, '-t\s+(\d+)'); $tp = [regex]::Match($Tuning, '-p\s+(\d+)')
    # Jede Zeile einzeln geklammert: in @(a + b, c + d) bindet das Komma staerker als das Plus
    $zeilen = @(
        ('start=' + (Hex64 $range.Start))
        ('next=' + (Hex64 $next))
        ('end=' + (Hex64 $range.End))
        ('blocks=' + $(if ($tb.Success) { $tb.Groups[1].Value } else { '32' }))
        ('threads=' + $(if ($tt.Success) { $tt.Groups[1].Value } else { '256' }))
        ('points=' + $(if ($tp.Success) { $tp.Groups[1].Value } else { '512' }))
        'compression=compressed'
        "device=$dev"
        ('elapsed=' + [string]::Format($inv, '{0:F0}', $elapsedMs))
        ('stride=' + (Hex64 1))
    )
    if ($fort) {
        # Stand von CUDACyclone im Block. BitCrack liest nur seine eigenen Schluessel und ignoriert diese Zeilen.
        $zeilen += @(
            ('cyc_bits=' + $fort.bits)
            ('cyc_batches=' + [string]::Format($inv, '{0:F0}', [double]$fort.batches))
            ('cyc_threads=' + [string]::Format($inv, '{0:F0}', [double]$fort.threads))
            ('cyc_batch=' + [string]::Format($inv, '{0:F0}', [double]$fort.batch))
            ('cyc_grid=' + $fort.grid)
        )
    }
    $p = Join-Path $Daten $fProg
    [IO.File]::WriteAllText("$p.tmp", ($zeilen -join "`n") + "`n")
    Move-Item "$p.tmp" $p -Force
}

# Ausgerichteter Block, der den Schluessel $next enthaelt. Groesse nach dem Tempo des letzten Blocks,
# so dass ein Block etwa $CycloneBlockSec dauert; ohne Tempo 2^36. Er bleibt im Bereich des Puzzles.
function Get-CycBlock($next, [int]$fest = 0) {
    $bits = 36
    $ziel = if ($script:cycResume) { $CycloneResumeSec } else { $CycloneBlockSec }
    if ($script:cycSpeed -gt 0) { $bits = [int][math]::Round([math]::Log([double]$script:cycSpeed * [double]$ziel, 2)) }
    if ($fest -gt 0) { $bits = $fest }   # angefangener Block: Groesse aus dem Checkpoint
    $bits = [int][math]::Max(24.0, [math]::Min(48.0, [double]$bits))
    $rs = Hex $RangeStart; $re = Hex $RangeEnd
    while ($true) {
        $size = [Numerics.BigInteger]::Pow(2, $bits)
        $bs = [Numerics.BigInteger]::Divide($next, $size) * $size
        $be = $bs + $size - 1
        $passt = ($bs -ge $rs -and $be -le $re)
        if ($script:cycResume -and $fest -le 0) {
            # Mit grossen Bloecken: nicht vor next beginnen (sonst rechnet CUDACyclone Erledigtes noch einmal)
            # und nicht ueber das Share-Ende hinaus. Am Share-Anfang gibt es dadurch kurz ein paar kleinere Bloecke.
            $passt = $passt -and ($bs -eq $next) -and ($be -le $script:range.End)
        }
        if ($passt -or $bits -le 24) { break }
        $bits--
    }
    [pscustomobject]@{ Start = $bs; End = $be; Bits = $bits; Size = [double]$size }
}

function Start-Cyclone($range) {
    $cp = Read-Checkpoint
    if (-not $cp -or $cp.Start -ne $range.Start) {
        Write-CycCheckpoint $range $range.Start 0.0
        $cp = Read-Checkpoint
    }
    # Angefangenen Block fortsetzen: Programm kann es, gleiche Blockgroesse, gleiches --grid, nicht eben abgelehnt
    $fort = $script:cycResume -and (-not $script:cycNoResume) -and $cp.CycBits -gt 0 -and $cp.CycBatches -gt 0 -and $cp.CycGrid -eq "$CycloneGrid"
    $script:cycNoResume = $false
    $b = if ($fort) { Get-CycBlock $cp.Next $cp.CycBits } else { Get-CycBlock $cp.Next }
    if ($fort -and $b.Bits -ne $cp.CycBits) { $fort = $false }
    if ((-not $fort) -and $cp.CycBits -gt 0) {
        # Zwischenstand gilt nicht mehr: Block beginnt von vorn, cyc_*-Zeilen entfernen
        Write-CycCheckpoint $range $cp.Next $cp.Elapsed
        $cp = Read-Checkpoint
    }
    $script:blk = $b; $script:blkElapsed0 = $cp.Elapsed; $script:blkT0 = Get-Date; $script:cycLive = $null
    $script:blkNext      = $cp.Next
    $script:cycCpBatches = if ($fort) { $cp.CycBatches } else { 0.0 }
    $script:cycOffset    = if ($fort) { $cp.CycKeys } else { 0.0 }   # schon erledigte Schluessel des Blocks
    $script:cycCpTime    = Get-Date
    if ($fort) { $script:cycThreads = $cp.CycThreads }
    $a = @('--range', ((Hex64 $b.Start).TrimStart('0') + ':' + (Hex64 $b.End).TrimStart('0')), '--address', $Address, '--grid', $CycloneGrid)
    if ([int]$CycloneSlices -gt 0) { $a += @('--slices', "$CycloneSlices") }
    if ($fort) { $a += @('--resume-batches', [string]::Format($inv, '{0:F0}', $cp.CycBatches), '--resume-threads', [string]::Format($inv, '{0:F0}', $cp.CycThreads)) }
    $p = Start-Process -FilePath $exePath -ArgumentList $a -WorkingDirectory $Daten -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $Daten $fLog) -RedirectStandardError (Join-Path $Daten $fErr) -PassThru
    try { Set-Content -Encoding ascii -Path (Join-Path $Daten $fPid) -Value $p.Id } catch { }
    $p
}

# Letzte vollstaendige Tempo-Zeile aus der Ausgabe (kommt jede Sekunde, auch bei Umleitung in eine Datei)
function Read-CycLive {
    try {
        $fs = [IO.File]::Open((Join-Path $Daten $fLog), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]'ReadWrite, Delete')
        $n = [int][math]::Min(4096.0, [double]$fs.Length)
        if ($n -le 0) { $fs.Close(); return $null }
        [void]$fs.Seek(-$n, [IO.SeekOrigin]::End)
        $buf = New-Object byte[] $n
        [void]$fs.Read($buf, 0, $n); $fs.Close()
        $txt = [Text.Encoding]::ASCII.GetString($buf)
    } catch { return $null }
    $m = [regex]::Matches($txt, 'Time:\s*([0-9.]+)\s*s\s*\|\s*Speed:\s*([0-9.]+)\s*Mkeys/s\s*\|\s*Count:\s*(\d+)\s*\|\s*Progress')
    if ($m.Count -eq 0) { return $null }
    $g = $m[$m.Count - 1].Groups
    [pscustomobject]@{ Sec = [double]::Parse($g[1].Value, $inv); Speed = [double]::Parse($g[2].Value, $inv) * 1e6; Count = [double]::Parse($g[3].Value, $inv) }
}

# Letzte Checkpoint-Zeile von CUDACyclone (nach jedem vollstaendigen Haeppchen) samt Rechenzeit bis dahin.
# 64 KB vom Ende reichen: zwischen zwei Checkpoints kommen rund 80 Tempo-Zeilen, und gelesen wird jede Sekunde.
function Read-CycCheckpointLine {
    try {
        $fs = [IO.File]::Open((Join-Path $Daten $fLog), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]'ReadWrite, Delete')
        $n = [int][math]::Min(65536.0, [double]$fs.Length)
        if ($n -le 0) { $fs.Close(); return $null }
        [void]$fs.Seek(-$n, [IO.SeekOrigin]::End)
        $buf = New-Object byte[] $n
        [void]$fs.Read($buf, 0, $n); $fs.Close()
        $txt = [Text.Encoding]::ASCII.GetString($buf)
    } catch { return $null }
    $m = [regex]::Matches($txt, 'Checkpoint: batches=(\d+) threads=(\d+) batch=(\d+)')
    if ($m.Count -eq 0) { return $null }
    $last = $m[$m.Count - 1]
    $t = [regex]::Matches($txt.Substring(0, $last.Index), 'Time:\s*([0-9.]+)\s*s')
    $sec = if ($t.Count -gt 0) { [double]::Parse($t[$t.Count - 1].Groups[1].Value, $inv) } else { 0.0 }
    [pscustomobject]@{
        Batches = [double]::Parse($last.Groups[1].Value, $inv); Threads = [double]::Parse($last.Groups[2].Value, $inv)
        Batch = [double]::Parse($last.Groups[3].Value, $inv); Sec = $sec
    }
}

# Neue Checkpoint-Zeile in die Checkpoint-Datei uebernehmen (next bleibt am Blockanfang, dazu cyc_*)
function Save-CycCheckpoint {
    if (-not $script:cycResume -or -not $script:blk -or $null -eq $script:blkNext) { return }
    if ($script:cycThreads -le 0) {
        # Die Faeden stehen schon in der Kopfzeile - so stimmt der Countdown ab dem ersten Haeppchen
        try {
            $fs = [IO.File]::Open((Join-Path $Daten $fLog), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]'ReadWrite, Delete')
            $n = [int][math]::Min(4096.0, [double]$fs.Length); $buf = New-Object byte[] $n
            [void]$fs.Read($buf, 0, $n); $fs.Close()
            $m = [regex]::Match([Text.Encoding]::ASCII.GetString($buf), 'Total threads\s*:\s*(\d+)')
            if ($m.Success) { $script:cycThreads = [double]$m.Groups[1].Value }
        } catch { }
    }
    $c = Read-CycCheckpointLine
    if (-not $c -or $c.Batches -le 0 -or $c.Batches -le $script:cycCpBatches) { return }
    $script:cycCpBatches = $c.Batches
    $script:cycThreads   = $c.Threads
    $script:cycCpTime    = Get-Date
    Write-CycCheckpoint $script:range $script:blkNext ($script:blkElapsed0 + $c.Sec * 1000.0) @{
        bits = $script:blk.Bits; batches = $c.Batches; threads = $c.Threads; batch = $c.Batch; grid = "$CycloneGrid" }
}

# Wie hat CUDACyclone geendet? 'found' (Trefferdatei im Format von BitCrack geschrieben), 'block' oder 'crash'
function Read-DateiGeteilt([string]$datei) {
    # Mit FileShare ReadWrite lesen: direkt nach dem Programmende haelt PowerShell den umgeleiteten Handle
    # womoeglich noch offen, ReadAllText scheitert dann (14.09.2026 als "crash" am regulaeren Blockende)
    try {
        $fs = [IO.File]::Open((Join-Path $Daten $datei), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]'ReadWrite, Delete')
        $sr = New-Object IO.StreamReader($fs)
        $t = $sr.ReadToEnd(); $sr.Close(); $t
    } catch { $script:cycLeseFehler = "$datei`: $($_.Exception.Message)"; '' }
}

function Get-CycEnd {
    # Bis zu 3 s immer wieder lesen, bevor es als Absturz gilt - die letzten Zeilen koennen kurz nachkommen
    for ($versuch = 1; $versuch -le 30; $versuch++) {
        # Fehlermeldungen (z. B. Ablehnung beim Fortsetzen) schreibt CUDACyclone nach stderr, also in die .err-Datei
        $txt = (Read-DateiGeteilt $fLog) + "`n" + (Read-DateiGeteilt $fErr)
        $pk = [regex]::Match($txt, 'Private Key\s*:\s*([0-9A-Fa-f]{64})')
        if ($pk.Success) {
            $pub = [regex]::Match($txt, 'Public Key\s*:\s*([0-9A-Fa-f]{66})')
            if ($pub.Success -or $versuch -eq 30) {
                $zeile = "$Address $($pk.Groups[1].Value)" + $(if ($pub.Success) { " $($pub.Groups[1].Value)" } else { '' })
                $fp = Join-Path $Daten $fFound
                if (-not (Test-Path $fp)) { [IO.File]::WriteAllText($fp, $zeile + "`r`n") }
                return 'found'
            }
        }
        elseif ($txt -match 'does not match the thread count|exceeds the batches per thread') { return 'resume-abgelehnt' }
        elseif ($txt -match 'KEY NOT FOUND \(exhaustive\)') { return 'block' }
        if ([P71.Guard]::Closing) { return 'crash' }   # Fenster geht zu: nicht bis zu 3 s auf Protokollzeilen warten
        Start-Sleep -Milliseconds 100
    }
    # Fuer die Ursachensuche festhalten, was beim Lesen zu sehen war (enthaelt keine Schluessel - dann waere es 'found')
    try {
        $ende = ($txt -split "[`r`n]+" | Where-Object { $_.Trim() } | Select-Object -Last 3) -join ' | '
        Add-Content -Encoding utf8 -Path (Join-Path $Daten 'cyc-ende-diagnose.log') -Value ('{0:yyyy-MM-dd HH:mm:ss}  crash nach 30 Leseversuchen: log {1} Bytes, err {2} Bytes, Lesefehler [{3}], Ende: {4}' -f (Get-Date),
            (Get-Item (Join-Path $Daten $fLog) -ErrorAction SilentlyContinue).Length, (Get-Item (Join-Path $Daten $fErr) -ErrorAction SilentlyContinue).Length, $script:cycLeseFehler, $ende)
    } catch { }
    'crash'
}

function Start-BC([int]$m, $range) {
    Restore-Progress $range
    if ($cyc) { return (Start-Cyclone $range) }
    $a = "-d $dev -c $Tuning --keyspace ${RangeStart}:${RangeEnd} --share $m/$Shares -o $fFound --continue $fProg $Address"
    Start-Process -FilePath $exePath -ArgumentList $a -WorkingDirectory $Daten -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $Daten $fLog) -RedirectStandardError (Join-Path $Daten $fErr) -PassThru
}

function Fmt-Keys([double]$n) {
    if     ($n -ge 1e15) { T 'dash.einheit.brd' ($n / 1e15) }
    elseif ($n -ge 1e12) { T 'dash.einheit.bio' ($n / 1e12) }
    elseif ($n -ge 1e9)  { T 'dash.einheit.mrd' ($n / 1e9) }
    else                 { F '{0:N0}' $n }
}

function Fmt-Span([double]$sec) {
    if ([double]::IsNaN($sec) -or [double]::IsInfinity($sec) -or $sec -lt 0) { return '–' }
    $t = [TimeSpan]::FromSeconds([math]::Min([double]$sec, 864000000.0))
    if ($t.Days -gt 0) { return (T 'dash.dauer.tage' $t.Days $t.Hours $t.Minutes) }
    '{0:00}:{1:00}:{2:00}' -f $t.Hours, $t.Minutes, $t.Seconds
}

function Bar([double]$frac, [int]$width) {
    $frac = [math]::Max(0.0, [math]::Min(1.0, [double]$frac))
    $cells = $frac * $width
    $full  = [int][math]::Floor($cells)
    $half  = ($cells - $full) -ge 0.5
    $s = [string][char]0x2588 * $full
    if ($full -lt $width) {
        if ($half) { $s += [string][char]0x258C } else { $s += [string][char]0x2591 }
        $s += [string][char]0x2591 * ($width - $full - 1)
    }
    $s
}

function Col([double]$v, [double]$warn, [double]$crit) { if ($v -ge $crit) { 'Red' } elseif ($v -ge $warn) { 'Yellow' } else { 'Green' } }

# Wartet bis zu $sec Sekunden und bricht bei einem Tastendruck sofort ab.
# Rueckgabe: Name der Taste ('P', 'W', ...) oder '' wenn nichts gedrueckt wurde.
# Knopfdruck auf der Webseite: eine Datei mit einem Wort. Wird gelesen, geloescht und wie eine Taste behandelt.
function Read-Befehl {
    if ($script:mqtt) { $mb = Read-MqttBefehl; if ($mb) { return $mb } }   # Befehl von Home Assistant
    if ($script:tray) { $tb = Read-TrayBefehl; if ($tb) { return $tb } }   # Klick im Tray-Menü
    $p = Join-Path $Daten $fCmd
    if (-not (Test-Path $p)) { return '' }
    $t = ''
    try { $t = "$(Get-Content $p -TotalCount 1 -ErrorAction Stop)".Trim().ToLower() } catch { }
    Remove-Item $p -Force -ErrorAction SilentlyContinue
    switch ($t) {
        'pause'  { if (-not $script:paused) { return 'P' } }
        'weiter' { if ($script:paused) { return 'P' } }
        'start'  { if ($script:paused) { return 'P' } }
        'auto'   { return 'V' }
    }
    ''
}

function Wait-Key([double]$sec) {
    $end = (Get-Date).AddSeconds($sec)
    $ohneKonsole = $false
    $n = 0
    while ((Get-Date) -lt $end) {
        Step-Web        # in dieser Wartezeit wird auch die Webseite bedient
        if ([P71.Guard]::Closing) {   # Fenster wird mit X geschlossen
            Show-Beenden
            if ($script:mqtt) { Stop-Mqtt (T 'dash.status.fensterGeschlossen' (Get-Date)) }
            if ($script:tray) { Stop-Tray }   # sonst bleibt ein Geister-Symbol, bis man mit der Maus darüberfährt
        }
        if ((++$n % 5) -eq 0) { $b = Read-Befehl; if ($b) { return $b } }   # alle 500 ms nachsehen
        # Ohne echte Konsole (umgeleitete Eingabe) wirft KeyAvailable - dann nur warten und weiter bedienen.
        if (-not $ohneKonsole) {
            try {
                if ([Console]::KeyAvailable) {
                    $k = [Console]::ReadKey($true)
                    if ($k.KeyChar -eq [char]3 -or ($k.Key -eq 'C' -and ($k.Modifiers -band [ConsoleModifiers]::Control))) { return 'CtrlC' }
                    return "$($k.Key)"
                }
            }
            catch { $ohneKonsole = $true }
        }
        # Suchprogramm beendet (CUDACyclone nach jedem Block): sofort zurueck, damit der naechste Block
        # nicht bis zum Ende der Wartezeit liegen bleibt (gemessen vorher knapp 3 s Luecke je Block)
        if (-not $script:paused -and $script:proc -and $script:proc.HasExited) { return '' }
        Start-Sleep -Milliseconds 100
    }
    ''
}

# Beenden dauert einige Sekunden (Suchprogramm stoppen, Checkpoint, Power-Limit, 3 s fuer die Webseite).
# Damit sich niemand wundert, steht sofort "Wird beendet ..." in der Fusszeile und im Fenstertitel.
function Write-BeendenZeile { W (T 'dash.fuss.wirdBeendet') Yellow ('  ' + [char]0x00B7 + (T 'dash.fuss.wirdGesichert')) DarkGray }
function Show-Beenden {
    if ($script:beendenGezeigt) { return }
    $script:beendenGezeigt = $true
    try { $Host.UI.RawUI.WindowTitle = (T 'dash.titel.wirdBeendet' $appTitel) } catch { }
    if ($null -eq $script:fussZeile) { return }   # Dashboard noch nie gezeichnet
    try {
        $x = [Console]::CursorLeft; $y = [Console]::CursorTop
        [Console]::SetCursorPosition(0, $script:fussZeile)
        Write-BeendenZeile
        [Console]::SetCursorPosition($x, $y)
    } catch { }
}

# Balken als Segmente: gefuellter Teil in Farbe, leerer Teil dunkelgrau
function BarSeg([double]$frac, [int]$width, [string]$color) {
    $b = Bar $frac $width
    $n = $b.TrimEnd([char]0x2591).Length
    @($b.Substring(0, $n), $color, $b.Substring($n), 'DarkGray')
}

# Schrift des Konsolenfensters festlegen. Windows merkt sich die Einstellung getrennt fuer
# powershell.exe, cmd.exe und je Verknuepfung - ohne das sieht das Dashboard je nach Startweg
# anders aus (Rahmen und Balken wirken dann grob). Muss vor Set-ConsoleLayout laufen, weil sich
# mit der Schrift auch die Fenstergroesse in Pixeln aendert.
function Set-ConsoleFont([string]$name, [int]$hoehe) {
    if (-not $name) { return }
    try {
        if (-not ('P71.Font' -as [type])) {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace P71 {
  [StructLayout(LayoutKind.Sequential)] public struct COORD { public short X; public short Y; }
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct FONTINFOEX {
    public uint cbSize; public uint nFont; public COORD dwFontSize;
    public uint FontFamily; public uint FontWeight;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string FaceName;
  }
  public static class Font {
    [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetCurrentConsoleFontEx(IntPtr h, bool maxWindow, ref FONTINFOEX info);
    [DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetCurrentConsoleFontEx(IntPtr h, bool maxWindow, ref FONTINFOEX info);
  }
}
"@
        }
        $h = [P71.Font]::GetStdHandle(-11)          # STD_OUTPUT_HANDLE
        $fi = New-Object P71.FONTINFOEX
        $fi.cbSize = [uint32][Runtime.InteropServices.Marshal]::SizeOf($fi)
        if (-not [P71.Font]::GetCurrentConsoleFontEx($h, $false, [ref]$fi)) { return }
        if ($hoehe -le 0) { $hoehe = [math]::Max(16, [int]$fi.dwFontSize.Y) }
        if ($fi.FaceName -eq $name -and [int]$fi.dwFontSize.Y -eq $hoehe) { return }
        $c = New-Object P71.COORD
        $c.X = 0                                    # Breite passend zur Hoehe
        $c.Y = [int16]$hoehe
        $fi.dwFontSize = $c
        $fi.FontFamily = 54                         # FF_MODERN, TrueType, feste Breite
        $fi.FontWeight = 400
        $fi.FaceName = $name
        [void][P71.Font]::SetCurrentConsoleFontEx($h, $false, [ref]$fi)
    } catch { }
}

# Fenstersymbol setzen (puzzle.ico, oranges Bitcoin-B). Nur der klassische Konsolenhost hat ein
# echtes Fenster - unter Windows Terminal passiert schlicht nichts.
function Set-ConsoleIcon([string]$datei) {
    if (-not (Test-Path $datei)) { return }
    try {
        if (-not ('P71.Sym' -as [type])) {
            Add-Type -Namespace P71 -Name Sym -MemberDefinition @"
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr LoadImage(IntPtr inst, string name, uint type, int cx, int cy, uint flags);
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
"@
        }
        $h = [P71.Sym]::GetConsoleWindow()
        if ($h -eq [IntPtr]::Zero) { return }
        # IMAGE_ICON = 1, LR_LOADFROMFILE = 0x10, WM_SETICON = 0x80 (0 = klein, 1 = gross)
        $klein = [P71.Sym]::LoadImage([IntPtr]::Zero, $datei, 1, 16, 16, 0x10)
        $gross = [P71.Sym]::LoadImage([IntPtr]::Zero, $datei, 1, 32, 32, 0x10)
        if ($klein -ne [IntPtr]::Zero) { [void][P71.Sym]::SendMessage($h, 0x80, [IntPtr]0, $klein) }
        if ($gross -ne [IntPtr]::Zero) { [void][P71.Sym]::SendMessage($h, 0x80, [IntPtr]1, $gross) }
    } catch { }
}

# Konsolenfenster auf Groesse bringen und anordnen (nebeneinander, mittig)
function Set-ConsoleLayout([int]$cols, [int]$rows, [int]$slot, [int]$count) {
    $ui = $Host.UI.RawUI
    try {
        $max  = $ui.MaxPhysicalWindowSize
        $cols = [math]::Min($cols, $max.Width); $rows = [math]::Min($rows, $max.Height)
        $ui.WindowSize = New-Object Management.Automation.Host.Size ([math]::Min($ui.WindowSize.Width, $cols)), ([math]::Min($ui.WindowSize.Height, $rows))
        $ui.BufferSize = New-Object Management.Automation.Host.Size $cols, $rows
        $ui.WindowSize = New-Object Management.Automation.Host.Size $cols, $rows
    } catch { }
    try {
        if (-not ('P71.Win' -as [type])) {
            Add-Type -Namespace P71 -Name Win -MemberDefinition @"
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
"@
        }
        Add-Type -AssemblyName System.Windows.Forms
        $h = [P71.Win]::GetConsoleWindow()
        $r = New-Object P71.Win+RECT
        # Unter Windows Terminal ist das Konsolenfenster nur ein verstecktes Pseudofenster:
        # GetWindowRect meldet dann 0 x 0. In dem Fall nicht verschieben, sonst landet das
        # Fenster mit der linken oberen Ecke in der Bildschirmmitte.
        if ($h -ne [IntPtr]::Zero -and [P71.Win]::GetWindowRect($h, [ref]$r) -and
            ($r.Right - $r.Left) -gt 0 -and ($r.Bottom - $r.Top) -gt 0) {
            $wa = [Windows.Forms.Screen]::FromHandle($h).WorkingArea
            $winW = $r.Right - $r.Left; $winH = $r.Bottom - $r.Top
            $count = [math]::Max(1, $count)
            if ($winW * $count -le $wa.Width) { $x = $wa.Left + [int](($wa.Width - $winW * $count) / 2) + $slot * $winW }
            else { $x = $wa.Left + [int]($slot * ($wa.Width - $winW) / [math]::Max(1, $count - 1)) }
            $y = $wa.Top + [int](($wa.Height - $winH) / 2)
            [void][P71.Win]::SetWindowPos($h, [IntPtr]::Zero, $x, $y, 0, 0, 0x0015)   # NOSIZE | NOZORDER | NOACTIVATE
        }
    } catch { }
}

# Zeile schreiben: W 'Text' Farbe 'Text' Farbe ...
function W {
    $max = [Console]::WindowWidth - 1; $len = 0
    for ($i = 0; $i -lt $args.Count; $i += 2) {
        $t = [string]$args[$i]; $c = if ($i + 1 -lt $args.Count) { $args[$i + 1] } else { 'Gray' }
        if ($len + $t.Length -gt $max) { $t = $t.Substring(0, [math]::Max(0, $max - $len)) }
        if ($t.Length) { Write-Host $t -NoNewline -ForegroundColor $c }
        $len += $t.Length
    }
    Write-Host (' ' * [math]::Max(0, $max - $len))
}

function Section([string]$title) { W ('  ' + [string][char]0x2500 * 2 + " $title " + [string][char]0x2500 * (58 - $title.Length)) DarkCyan }

function Get-TargetStatus {
    if (-not $MempoolApi) { return [pscustomobject]@{ Ok = $false; Balance = 0.0; Spent = $false; Time = Get-Date; Err = $false; Off = $true } }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $a = Invoke-RestMethod "$MempoolApi/address/$Address" -TimeoutSec 15
        [pscustomobject]@{
            Ok      = $true
            Balance = ([double]$a.chain_stats.funded_txo_sum - [double]$a.chain_stats.spent_txo_sum) / 1e8
            Spent   = ([int]$a.chain_stats.spent_txo_count + [int]$a.mempool_stats.spent_txo_count) -gt 0
            Time    = Get-Date
            Err     = $false
            Off     = $false
        }
    } catch {
        [pscustomobject]@{ Ok = $false; Balance = 0.0; Spent = $false; Time = Get-Date; Err = $true; Off = $false }
    }
}

# Fragt Ollama, welche Modelle geladen sind und wie lange sie noch bleiben. Waehrend einer Anfrage
# schiebt Ollama diese Restzeit staendig nach vorn, im Leerlauf laeuft sie ab - daran erkennt die
# Schleife, ob gerade gerechnet wird. Sehr grosse Restzeiten (OLLAMA_KEEP_ALIVE=-1) sagen nichts aus.
function Get-OllamaState {
    if (-not $OllamaApi) { return $null }
    try {
        $r = Invoke-RestMethod "$OllamaApi/api/ps" -TimeoutSec 3
        $now = Get-Date
        $mb = 0.0; $rest = @{}; $namen = @(); $unklar = $false
        foreach ($m in @($r.models)) {
            $n = [string]$m.name
            $sec = ([datetime]::Parse([string]$m.expires_at, $inv) - $now).TotalSeconds
            if ($sec -gt 3600) { $unklar = $true }   # haelt ewig: Aktivitaet nicht ablesbar
            $namen += $n
            $rest[$n] = $sec
            $mb += [double]$m.size_vram / 1MB
        }
        [pscustomobject]@{ Ok = $true; Mb = $mb; Rest = $rest; Namen = $namen; Unklar = $unklar }
    } catch {
        [pscustomobject]@{ Ok = $false; Mb = 0.0; Rest = @{}; Namen = @(); Unklar = $false }
    }
}

# Aktuell belegter Grafikspeicher in MB (fuer die VRAM-Automatik auch vor dem ersten Durchlauf)
function Get-VramUsed {
    try { [double]::Parse("$(& $smi -i $dev --query-gpu=memory.used --format=csv,noheader,nounits)".Trim(), $inv) } catch { 0.0 }
}

# Pause: BitCrack beenden (max. 60 s Rechenzeit gehen verloren), GPU freigeben.
# $grund steht in der Flag-Datei, damit solar.ps1 Hand- und VRAM-Pause unterscheiden kann.
function Suspend-BC([string]$grund) {
    if ($cyc) { Save-CycCheckpoint }   # zuletzt gemeldetes Haeppchen noch sichern, bevor CUDACyclone beendet wird
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force; [void]$proc.WaitForExit(10000) }
    if ($usePl -gt 0) { & $smi -i $dev -pl $defaultPl | Out-Null }
    $script:paused = $true; $script:pauseAt = Get-Date; $script:speed = 0.0
    $script:autoPause = ($grund -ne 'hand')
    $script:pauseWhy  = $grund
    $script:vramHi = 0; $script:vramLo = 0
    # Nach dem Beenden faellt der Speicher um den Eigenbedarf von BitCrack - gute Gelegenheit zum Messen
    $script:vramPre = $script:vramNow; $script:vramDir = -1.0; $script:ollMbPre = $script:ollMb; $script:vramAt = $script:pauseAt.AddSeconds(12)
    # Marke fuer solar.ps1, damit die Pause nicht als Absturz gilt
    Set-Content -Encoding ascii -Path (Join-Path $Daten $fPause) -Value @($script:pauseAt.ToString('yyyy-MM-dd HH:mm:ss'), $grund)
    # Nur eine Pause von Hand wird gemerkt; Auto-Pausen setzen von selbst fort, gewollt bleibt "suchen"
    if ($grund -eq 'hand') { $script:sucheGewollt = $false; Save-Merken }
}

# Weiter: Power-Limit wieder setzen, BitCrack aus dem Checkpoint fortsetzen
function Resume-BC {
    if ($usePl -gt 0) { & $smi -i $dev -pl $usePl | Out-Null }
    $script:vramPre = $script:vramNow; $script:vramDir = 1.0; $script:ollMbPre = $script:ollMb; $script:vramAt = (Get-Date).AddSeconds(12)
    $script:proc = Start-BC $share $range
    [void][P71.Guard]::Attach($script:proc)
    Remove-Item (Join-Path $Daten $fPause) -ErrorAction SilentlyContinue
    $script:paused = $false; $script:pauseAt = $null; $script:skipSpd = $true
    $script:autoPause = $false; $script:pauseWhy = ''
    $script:sucheGewollt = $true; Save-Merken
    $script:vramHi = 0; $script:vramLo = 0
}

# Speicherregel der Automatik fuer diese Sitzung abschalten ('start': schon beim Start ueber der Schwelle, 'pendel': dreimal
# in 10 Minuten pausiert und wieder gestartet). Ohne Ollama-Abfrage ist die Automatik damit sichtbar aus; mit $OllamaApi
# bleibt die Ollama-Pause aktiv. Gemerkt wird weiter "an" (Save-Merken), Taste V hebt die Sperre auf.
function Set-VramSperre([string]$grund) {
    $script:vramSperre = $grund; $script:vramHi = 0; $script:vramLo = 0; $script:vramRueck = @()
    if (-not $OllamaApi) { $script:vramAuto = $false }
}

# Momentaufnahme für web.ps1. Bewusst ohne Schlüssel und ohne Inhalt der Trefferdatei: die Seite soll
# im Netz stehen dürfen. Erst in eine .tmp schreiben und dann umbenennen, damit web.ps1 nie eine
# halb geschriebene Datei liest.
# Meldungen, die nicht auf die Webseite gehoeren: die eigene Adresse, "laeuft im Fenster einer anderen GPU", MQTT verbunden
function Test-StatusIntern([string]$s) {
    foreach ($p in @((T 'dash.status.webAdresse' 'http'), (T 'dash.status.webAn' 'http'), (T 'dash.status.webAnderesFenster'), (T 'mqtt.status.verbunden' ''))) {
        if ($p -and $s.StartsWith($p)) { return $true }
    }
    $false
}

function Write-Status([string]$zustand) {
    if ([P71.Guard]::Closing) { return }   # Fenster geht zu: die letzte Meldung schreibt der Schutz selbst
    $o = [ordered]@{
        zeit = (Get-Date).ToString('s'); pc = $pc; gpu = $dev; puzzle = $Puzzle; adresse = $Address
        # Die Startmeldung mit der eigenen Adresse gehoert nicht auf die Webseite - wer sie sieht,
        # kennt sie schon. Fehlermeldungen bleiben dagegen stehen.
        zustand = $zustand; meldung = $(if (Test-StatusIntern "$status") { '' } else { "$status" })
        share = $share; shares = $Shares; abgesucht = $doneCount
        anteil = [math]::Round($frac, 8); geprueft = [double]$done; gesamt = [double]$total
        tempo = [double]$speed; laufzeit = [double]$elapsed; rest = $(if ([double]::IsNaN($eta)) { $null } else { [math]::Round($eta) })
        sitzung = [math]::Round(((Get-Date) - $t0).TotalSeconds); kwh = [math]::Round($wh / 1000, 4); preis = $PricePerKwh
        motor = $motor; block = $(if ($cyc -and $blk) { $blk.Bits } else { $null })
        karte = $(if ($gpu) { $gpu.Name } else { '' }); profil = $(if ($profileName) { $profileName } else { 'Standard' })
        watt = $(if ($gpu) { $gpu.Power } else { 0 }); limit = $(if ($gpu) { $gpu.Limit } else { 0 })
        grad = $(if ($gpu) { $gpu.Temp } else { 0 }); luefter = $(if ($gpu) { [double]$gpu.Fan } else { 0 })
        last = $(if ($gpu) { $gpu.Util } else { 0 })
        vram = $(if ($gpu) { $gpu.MemUsed } else { 0 }); vramGesamt = $(if ($gpu) { $gpu.MemTotal } else { 0 })
        vramFremd = [math]::Round($vramOther); automatik = $vramAuto; web = [bool]$webAn
        treffer = (Test-Path (Join-Path $Daten $fFound)); trefferDatei = $fFound
        ollama = $null
    }
    if ($OllamaApi) {
        $o.ollama = if (-not $oll -or -not $oll.Ok) { [ordered]@{ erreichbar = $false } }
                    else { [ordered]@{
                        erreichbar = $true; aktiv = $ollActive; mb = [math]::Round($oll.Mb)
                        modell = $(if ($oll.Namen.Count -gt 0) { [string]$oll.Namen[0] } else { '' })
                        anzahl = $oll.Namen.Count } }
    }
    $json = $o | ConvertTo-Json -Depth 4 -Compress
    try {
        $p = Join-Path $Daten $fStat
        [IO.File]::WriteAllText("$p.tmp", $json)
        Move-Item "$p.tmp" $p -Force
    } catch { }
    if ($script:mqtt) { Send-MqttStatus $json $zustand }   # dieselbe Momentaufnahme an MQTT (gedrosselt)
    if ($script:tray) { Update-Tray $zustand }             # Tooltip und Häkchen im Tray-Menü
}

# ---------- Webseite ----------
# Der Webserver laeuft in diesem Fenster mit: kein zweites Fenster, kein eigener Prozess.
# Die Seite selbst und die Schnittstellen stehen in web-inhalt.ps1, dieselbe Datei benutzt web.ps1.
# Bedient werden die Anfragen in Wait-Key, also im 100-ms-Takt zwischen zwei Bildschirmaufbauten.

# Schreibt mit, was beim Start der Webseite schiefgegangen ist - im Fenster ist dafuer kein Platz
function Write-WebLog([string]$text) {
    try {
        Add-Content -Encoding utf8 -Path (Join-Path $Daten 'web-fehler.log') `
            -Value ('{0:yyyy-MM-dd HH:mm:ss}  GPU {1}  {2}' -f (Get-Date), $dev, $text)
    } catch { }
}

function Start-Web {
    if ($WebPort -le 0) { return }
    if ($script:webListener -and $script:webListener.IsListening) { return }
    if (-not $script:webGeladen) { $script:status = (T 'dash.status.webInhaltFehlt'); return }
    try {
        $l = New-Object Net.HttpListener
        $l.Prefixes.Add("http://${WebBind}:$WebPort/")
        $l.Start()
        $script:webListener = $l
        $script:webTask = $null
        if ($script:webFehler) {
            $script:webFehler = $false
            Write-WebLog "Port $WebPort jetzt offen"
            $script:status = (T 'dash.status.webAdresse' "http://$(if ($WebBind -in '+', '*') { $pc } else { $WebBind }):$WebPort/")
        }
    } catch {
        $grund = $_.Exception.Message
        $script:webListener = $null
        if (-not $script:webFehler) {
            $script:webFehler = $true
            # Haelt das Fenster der anderen GPU den Port, ist das kein Fehler - dort laeuft die Seite ja.
            # Erkennbar daran, dass auf dem Port schon unsere Seite antwortet; sonst blockiert ein fremdes Programm.
            $unsere = $false
            try {
                $antwort = Invoke-WebRequest "http://localhost:$WebPort/api/status" -UseBasicParsing -TimeoutSec 2
                $unsere = ($antwort.Content -match '"pc"\s*:')
            } catch { }
            if ($unsere) {
                $script:status = (T 'dash.status.webAnderesFenster')
                Write-WebLog "Port $WebPort belegt, dort antwortet bereits die BitCrack-Seite (anderes Fenster) - uebernimmt, wenn es schliesst"
            } else {
                $script:status = (T 'dash.status.webPortBelegt' $WebPort)
                Write-WebLog "Port $WebPort ging nicht auf (Bind $WebBind): $grund"
            }
        }
    }
}

# Sorgt dafuer, dass die Windows-Firewall den Port durchlaesst - bewusst nur fuer private Netze,
# denn die Seite hat kein Passwort und kann die Suche starten und anhalten.
function Set-WebFirewall {
    if ($WebPort -le 0 -or $WebBind -ne '+') { return }
    $name = "BitCrack-Web $WebPort"
    try {
        if (-not (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $name -Direction Inbound -Action Allow -Protocol TCP `
                -LocalPort $WebPort -Profile Private -Description 'BitCrack-Webseite im eigenen Netz' -ErrorAction Stop | Out-Null
            Write-Host (T 'dash.fw.angelegt' $name) -ForegroundColor Green
            Write-WebLog "Firewall-Regel '$name' angelegt (Profil privat)"
            # Die Konsolenzeile ist beim ersten Bildschirmaufbau weg, deshalb auch in die Statuszeile
            $script:status = (T 'dash.fw.statusAngelegt' $WebPort)
        }
    } catch {
        Write-Host (T 'dash.fw.fehler' $name) -ForegroundColor Yellow
        Write-WebLog "Firewall-Regel '$name' ging nicht: $($_.Exception.Message)"
    }
    # Eine Regel fuer private Netze greift nicht, wenn Windows das Netz als oeffentlich fuehrt
    try {
        $pro = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue)
        if ($pro.Count -gt 0 -and -not ($pro | Where-Object { $_.NetworkCategory -ne 'Public' })) {
            $script:status = (T 'dash.fw.oeffentlichStatus')
            Write-Host (T 'dash.fw.oeffentlich1') -ForegroundColor Yellow
            Write-Host (T 'dash.fw.oeffentlich2') -ForegroundColor DarkGray
            Write-WebLog "Netzwerkprofil ist Oeffentlich ($($pro[0].Name)) - die Regel fuer private Netze greift nicht"
        }
    } catch { }
}

function Stop-Web {
    if ($script:webListener) {
        try { if ($script:webListener.IsListening) { $script:webListener.Stop() } } catch { }
        try { $script:webListener.Close() } catch { }
    }
    $script:webListener = $null
    $script:webTask = $null
}

# Offene Anfragen beantworten. Wird aus Wait-Key aufgerufen und darf nie blockieren.
function Step-Web {
    if (-not $script:webListener -or -not $script:webListener.IsListening) { return }
    for ($i = 0; $i -lt 8; $i++) {
        if (-not $script:webTask) {
            try { $script:webTask = $script:webListener.GetContextAsync() } catch { return }
        }
        $fertig = $false
        try { $fertig = $script:webTask.Wait(0) } catch { $script:webTask = $null; return }
        if (-not $fertig) { return }
        $ctx = $null
        try { $ctx = $script:webTask.GetAwaiter().GetResult() } catch { }
        $script:webTask = $null
        if ($ctx) { try { [void](Invoke-WebAnfrage $ctx) } catch { } }
    }
}

# ---------- Start ----------
$share   = Get-Share
$doneList  = Get-DoneShares           # schon abgesuchte Shares (eigene Liste plus eingespielte)
$doneCount = $doneList.Count
$frac = 0.0; $done = 0.0; $elapsed = 0.0; $eta = [double]::NaN; $vramOther = 0.0   # auch fuer Write-Status vor dem ersten Durchlauf
$range   = Get-ShareRange $share
$total   = [double]$range.Size
$proc    = $null
$cpLast  = $null
$blk         = $null                  # CUDACyclone: laufender Block (Start, Ende, Bits, Groesse)
$blkT0       = Get-Date               # Startzeit dieses Blocks
$blkElapsed0 = 0.0                    # Rechenzeit des Shares vor diesem Block (ms)
$cycLive     = $null                  # letzte Tempo-Zeile von CUDACyclone
$cycSpeed    = 0.0                    # Tempo des letzten Blocks (Schluessel/s), bestimmt die Blockgroesse
$blkNext      = $null                 # next im Checkpoint beim Start dieses Blocks (bleibt waehrend des Blocks gleich)
$cycCpBatches = 0.0                   # zuletzt gesicherte Pakete je Faden (Checkpoint-Zeile von CUDACyclone)
$cycOffset    = 0.0                   # beim Fortsetzen schon erledigte Schluessel des Blocks
$cycCpTime    = Get-Date              # Zeit des letzten gesicherten Haeppchens bzw. des Programmstarts
$cycThreads   = 0.0                   # Faeden laut CUDACyclone (fuer den Countdown)
$cycNoResume  = $false                # einmalig: nicht fortsetzen (CUDACyclone hat den Checkpoint abgelehnt)
if ($cyc) {
    # Startwert fuer die Blockgroesse: letztes Tempo aus der Kurve; ohne Kurve misst ein erster kleiner Block
    try {
        $hl = "$(Get-Content (Join-Path $Daten $fHist) -Tail 1 -ErrorAction Stop)"
        $hv = 0.0
        if ([double]::TryParse(($hl -split ';')[1], [Globalization.NumberStyles]::Float, $inv, [ref]$hv)) { $cycSpeed = $hv }
    } catch { }
}
$speed   = 0.0
$gpu     = $null
$gpuLauf = $null                      # GPU-Werte der letzten Abfrage, bei der das Suchprogramm lief (fuer die Kurve)
$wh      = 0.0
$t0      = Get-Date
$tick    = $t0
$lastW   = 0
$paused  = $false                     # Pause per Taste P: BitCrack beendet, GPU frei (z. B. für Ollama)
$pauseAt = $null
$skipSpd = $false                     # ersten Checkpoint nach dem Fortsetzen nicht fürs Tempo nutzen
$autoPause = $false                   # diese Pause hat die Automatik ausgelöst (nur dann startet sie wieder)
$pauseWhy  = ''                       # Grund der Pause: 'hand', 'vram' oder 'ollama'
$ollMb     = 0.0                      # Grafikspeicher, den Ollama gerade belegt
$ollMbPre  = 0.0                      # derselbe Wert beim letzten Start/Stopp von BitCrack
$ollRest   = @{}                      # Restzeit je geladenem Modell aus der vorigen Abfrage
$ollTime   = Get-Date                 # Zeitpunkt dieser Abfrage
$ollActive = $false                   # Ollama rechnet gerade
$ollActiveAt = (Get-Date).AddDays(-1) # wann Ollama zuletzt gerechnet hat
$ollArmed  = $true                    # nach Weiter von Hand erst wieder scharf, wenn Ollama ruhig war
$oll       = $null                    # letzte Antwort von Ollama (für die Anzeige)
# Zuletzt gewählter Zustand (Tasten W/V, Schalter in Home Assistant, Suche an/aus) - hat Vorrang vor der Config.
# Wird bei jeder Änderung sofort geschrieben, damit er auch das Schließen mit X übersteht (dort läuft kein finally).
function Read-Merken {
    try { Get-Content (Join-Path $Daten $fMerk) -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $null }
}
function Save-Merken {
    try {
        $p = Join-Path $Daten $fMerk
        $alt = Read-Merken
        # Was hier gerade nicht schaltbar ist ($WebPort = 0, keine Automatik), bleibt wie zuletzt gemerkt
        $web  = if ($WebPort -gt 0) { [bool]$script:webAn } elseif ($alt -and $null -ne $alt.web) { [bool]$alt.web } else { $true }
        $auto = if ($VramPauseMB -gt 0 -or $OllamaApi) { [bool]$script:vramAuto -or [bool]$script:vramSperre } elseif ($alt -and $null -ne $alt.automatik) { [bool]$alt.automatik } else { $true }
        $o = [ordered]@{ web = $web; automatik = $auto; suche = [bool]$script:sucheGewollt; zeit = (Get-Date).ToString('s') }
        [IO.File]::WriteAllText("$p.tmp", ($o | ConvertTo-Json -Compress))
        Move-Item "$p.tmp" $p -Force
    } catch { }
}
$merk = Read-Merken
$wartetVorgabe = if ($merk -and $null -ne $merk.suche) { -not [bool]$merk.suche } else { $StartWartet }
$wartet    = ($wartetVorgabe -and -not $Sofort)   # erst auf Knopfdruck suchen (gemerkt: beim letzten Schließen pausiert)
$sucheGewollt = -not $wartet                      # wird gemerkt: sucht beim nächsten Öffnen sofort weiter
$webAn     = ($WebPort -gt 0) -and $(if ($merk -and $null -ne $merk.web) { [bool]$merk.web } else { $true })   # Webseite gewünscht (Taste W schaltet um, gemerkt)
$webListener = $null                  # HttpListener dieses Fensters
$webTask   = $null                    # auf die nächste Anfrage wartend
$webFehler = $false                   # Port war belegt; nicht bei jedem Versuch neu melden
$webCheck  = (Get-Date).AddDays(-1)   # wann zuletzt versucht wurde, den Port zu öffnen
# Seite und Schnittstellen laden - muss im Skript stehen, in einer Funktion wären sie danach wieder weg
$webGeladen = $false
if ($WebPort -gt 0) {
    $WebOrdner = $Daten
    $webInhalt = Join-Path $PSScriptRoot 'web-inhalt.ps1'
    if (Test-Path $webInhalt) {
        try { . $webInhalt; $webGeladen = $true }
        catch { Write-Host (T 'dash.start.webInhaltFehler' $_.Exception.Message) -ForegroundColor Yellow }
    } else { Write-Host (T 'dash.start.webInhaltFehlt') -ForegroundColor Yellow }
}
$vramAuto  = ($VramPauseMB -gt 0 -or $OllamaApi -ne '') -and $(if ($merk -and $null -ne $merk.automatik) { [bool]$merk.automatik } else { $true })   # Automatik aktiv (Taste V schaltet um, gemerkt)
$vramArmed = $true                    # nach Weiter von Hand erst wieder scharf, wenn der Speicher frei war
$vramSelf  = [double]$VramSelfMB      # VRAM-Bedarf von BitCrack (wird beim Start/Stopp nachgemessen)
$vramNow   = 0.0                      # aktuell belegter Grafikspeicher
$vramPre   = 0.0                      # Wert vor dem letzten Start/Stopp von BitCrack
$vramDir   = 0.0                      # erwartete Richtung der Änderung: +1 nach Start, −1 nach Stopp
$vramAt    = $null                    # Zeitpunkt, ab dem der Vergleich sinnvoll ist
$vramHi    = 0                        # Messungen über der Pausenschwelle
$vramLo    = 0                        # Messungen unter der Rückkehrschwelle
$vramSperre = ''                      # Speicherregel für diese Sitzung aus: 'start' oder 'pendel' (Set-VramSperre)
$vramStartPruefung = ($vramAuto -and $VramPauseMB -gt 0)   # einmal prüfen, ob schon beim Start zu viel belegt ist
$vramRueck = @()                      # Zeitpunkte der Auto-Starts nach Speicher-Pausen (Pendelschutz)
$status  = ''
$tray = $null                         # Symbol im Infobereich ($Fenster = 'tray')
# MQTT laden und verbinden (Verbindung läuft im Hintergrund) - Dot-Sourcing im Skript, wie bei web-inhalt.ps1
$mqtt = $null
if ($MqttHost) {
    $mqttDatei = Join-Path $PSScriptRoot 'mqtt.ps1'
    if (Test-Path $mqttDatei) {
        try { . $mqttDatei; Start-Mqtt }
        catch { Write-Host (T 'dash.start.mqttFehler' $_.Exception.Message) -ForegroundColor Yellow; $mqtt = $null }
    } else { $status = (T 'dash.status.mqttFehlt') }
}
# Ohne passendes Profil sucht die Karte mit Standardwerten (Power-Limit, Tuning) - dann auf tuning.bat hinweisen.
# Auch ohne $GpuProfiles (neutrale Paket-Config): gerade dann wurde noch nie gemessen.
if (-not $profileName) {
    $status = (T 'dash.status.keinProfil')
    Write-Host (T 'dash.start.keinProfil1' $gpuName) -ForegroundColor Yellow
    Write-Host (T 'dash.start.keinProfil2') -ForegroundColor Yellow
}

# Ollama gibt den Grafikspeicher erst nach dieser Zeit ohne Anfrage frei (ohne Angabe sind es 5 Minuten).
# Der Wert wird in die Umgebung dieses Benutzers geschrieben und gilt ab dem nächsten Start von Ollama.
if ($OllamaKeepAlive) {
    try {
        if ([Environment]::GetEnvironmentVariable('OLLAMA_KEEP_ALIVE', 'User') -ne $OllamaKeepAlive) {
            [Environment]::SetEnvironmentVariable('OLLAMA_KEEP_ALIVE', $OllamaKeepAlive, 'User')
            $status = (T 'dash.status.keepAlive' $OllamaKeepAlive)
            Write-Host (T 'dash.start.keepAlive' $OllamaKeepAlive) -ForegroundColor Yellow
        }
    } catch { $status = (T 'dash.status.keepAliveFehler') }
}

# Kann vorkommen, wenn eine fremde Liste eingespielt wurde, nachdem dieser Share begonnen hat
if ($doneList.ContainsKey("$share")) { $status = T 'dash.status.shareInListe' $share }
$result  = ''

Write-Host (T 'dash.start.pruefeZiel') -ForegroundColor DarkGray
$target = Get-TargetStatus
if ($target.Ok -and $target.Spent) {
    Write-Host ''
    Write-Host (T 'dash.start.geloest' $Puzzle) -ForegroundColor Yellow
    Write-Host (T 'dash.start.nichtGestartet') -ForegroundColor Yellow
    exit
}

try {
    Set-ConsoleFont $ConsoleFont $ConsoleFontSize
    Set-ConsoleLayout $WinCols $WinRows $Slot $Count
    Set-ConsoleIcon (Join-Path $PSScriptRoot 'puzzle.ico')
    # Fenster minimiert starten oder nur als Symbol im Infobereich ($Fenster). Dot-Sourcing im Skript, nicht in einer Funktion.
    if ($Fenster -eq 'minimiert') {
        try {
            if (-not ('P71.Zeig' -as [type])) {
                Add-Type -Namespace P71 -Name Zeig -MemberDefinition @"
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
"@
            }
            [void][P71.Zeig]::ShowWindow([P71.Zeig]::GetConsoleWindow(), 7)   # SW_SHOWMINNOACTIVE
        } catch { }
    } elseif ($Fenster -eq 'tray') {
        $trayDatei = Join-Path $PSScriptRoot 'tray.ps1'
        if (Test-Path $trayDatei) {
            try { . $trayDatei; Start-Tray }
            catch { $tray = $null; $status = (T 'dash.status.trayFehler' $_.Exception.Message) }
        } else { $status = (T 'dash.status.trayFehlt') }
    }
    try { $Host.UI.RawUI.BackgroundColor = 'Black'; $Host.UI.RawUI.ForegroundColor = 'Gray' } catch { }   # einheitlich schwarz, egal wie gestartet
    [Console]::CursorVisible = $false
    if ($usePl -gt 0) { & $smi -i $dev -pl $usePl | Out-Null }
    if ($webAn) {
        Start-Web
        $webCheck = Get-Date
        if ($webListener) {
            $status = (T 'dash.status.webAdresse' "http://$(if ($WebBind -in '+', '*') { $pc } else { $WebBind }):$WebPort/")
            Set-WebFirewall      # darf $status überschreiben: die Warnung ist wichtiger als die Adresse
        }
    }
    if ($motorHinweis) { $status = $motorHinweis }
    if ($wartet) {
        # Fenster steht bereit, die Suche beginnt erst auf Knopfdruck (Taste P oder Webseite)
        $paused = $true; $pauseAt = Get-Date; $pauseWhy = 'wartet'; $autoPause = $false
        $status = if ($StartWartet) { (T 'dash.status.bereit') } else { (T 'dash.status.bereitGemerkt') }
        Set-Content -Encoding ascii -Path (Join-Path $Daten $fPause) -Value @($pauseAt.ToString('yyyy-MM-dd HH:mm:ss'), 'wartet')
    } else {
        # Belegung vor dem Start merken: der Zuwachs ist der Eigenbedarf von BitCrack
        if ($StartWartet -and -not $Sofort) { $status = (T 'dash.status.suchtGemerkt') }
        $vramNow = Get-VramUsed; $vramPre = $vramNow; $vramDir = 1.0; $vramAt = (Get-Date).AddSeconds(12)
        $proc = Start-BC $share $range
        [void][P71.Guard]::Attach($proc)
    }

    # Strg+C als Taste statt als Signal. Sonst beendet es PowerShell sofort, und cmd (puzzle.bat) fragt
    # danach "Batchvorgang abbrechen (J/N)?" - egal was man antwortet, die Suche ist schon zu.
    # So fragt das Dashboard selbst. RestoreConsoleMode im finally stellt den alten Modus wieder her.
    try { [Console]::TreatControlCAsInput = $true } catch { }
    $quitAsk = $null                      # Zeitpunkt der Rückfrage nach Strg+C

    while ($true) {
        $now = Get-Date

        # --- Fenster wird mit X geschlossen: sofort ins finally. Sonst wertet die Runde erst das Ende des Suchprogramms
        #     aus (der Schutz hat es gerade beendet), Get-CycEnd wartet bis zu 3 s, und Windows beendet nach ~3,5 s. ---
        if ([P71.Guard]::Closing) { break }

        # --- Stopp-Anforderung von solar.ps1? (nur Dateien, die nach dem Start geschrieben wurden) ---
        $sf = Get-Item (Join-Path $Daten $fStop) -ErrorAction SilentlyContinue
        if ($sf -and $sf.LastWriteTime -gt $t0) { $status = (T 'dash.status.solarStopp'); break }

        # --- Suchprogramm beendet? (in der Pause ist das gewollt) ---
        if ((-not $paused) -and $proc.HasExited) {
            if (Test-Path $fFound) { $result = 'found'; break }
            $shareFertig = $false
            if ($cyc) {
                # CUDACyclone endet nach jedem Block: Treffer, Block fertig oder Fehler
                $ende = Get-CycEnd
                if ($ende -eq 'found') { $result = 'found'; break }
                if ($ende -eq 'resume-abgelehnt') {
                    # Andere Aufteilung als beim Checkpoint (--grid oder Karte geaendert): Block ohne Fortsetzen neu
                    $cycNoResume = $true
                    $proc = Start-BC $share $range
                    [void][P71.Guard]::Attach($proc)
                    $status = (T 'dash.status.resumeAbgelehnt')
                    continue
                }
                if ($ende -ne 'block') { $result = 'crash'; break }
                $liveEnde = Read-CycLive
                $blkSek = if ($liveEnde -and $liveEnde.Sec -gt 0) { $liveEnde.Sec } else { ($now - $blkT0).TotalSeconds }
                # Ein fortgesetzter, schon fertiger Block dauert nur Sekundenbruchteile: daraus kein Tempo ableiten,
                # sonst faengt die Blockgroesse wieder bei 2^36 an (14.09.2026 nach dem Neustart um 19:05)
                if ($blkSek -ge 5 -and ([double]$blk.Size - [double]$cycOffset) -gt 0) { $cycSpeed = ([double]$blk.Size - [double]$cycOffset) / $blkSek }
                $nextKey = $blk.End + 1
                Write-CycCheckpoint $range $nextKey ($blkElapsed0 + $blkSek * 1000.0)
                if ($nextKey -le $range.End) {
                    $proc = Start-BC $share $range
                    [void][P71.Guard]::Attach($proc)
                } else { $shareFertig = $true; $cpLast = Read-Checkpoint }
            } else {
                $err = Get-Content $fErr -Raw -ErrorAction SilentlyContinue
                $shareFertig = ($err -match 'Reached end of keyspace')
                if (-not $shareFertig) { $result = 'crash'; break }
            }
            if ($shareFertig) {
                $status = T 'dash.status.shareFertig' $share $now
                Add-DoneShare $share
                Remove-Item $fShare, $fProg, $fBak -ErrorAction SilentlyContinue
                $share = Get-Share; $range = Get-ShareRange $share; $total = [double]$range.Size
                $doneCount = (Get-DoneShares).Count
                $cpLast = $null; $speed = 0.0
                $proc = Start-BC $share $range
                [void][P71.Guard]::Attach($proc)
            }
        }

        # --- Zieladresse regelmaessig pruefen ---
        if ((-not $target.Off) -and ($now - $target.Time).TotalMinutes -ge $CheckMin) {
            $t = Get-TargetStatus
            if ($t.Ok) { $target = $t } else { $target.Time = $t.Time; $target.Err = $true }
            if ($target.Ok -and $target.Spent) { $result = 'solved'; break }
        }

        # --- GPU-Werte dieser Karte ---
        try {
            $q = (& $smi -i $dev --query-gpu=name,pstate,power.draw,power.limit,temperature.gpu,fan.speed,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits) -split ',\s*'
            $gpu = [pscustomobject]@{
                Name = $q[0] -replace '^NVIDIA\s+', ''; PState = $q[1]
                Power = [double]::Parse($q[2], $inv); Limit = [double]::Parse($q[3], $inv)
                Temp = [double]$q[4]; Fan = $q[5]; Util = [double]$q[6]; MemUsed = [double]$q[7]; MemTotal = [double]$q[8]
            }
            $wh += $gpu.Power * ($now - $tick).TotalHours
            # letzter Wert, waehrend gerechnet wurde - nicht aus den ersten 15 s eines Blocks von CUDACyclone,
            # denn nach einem Blockende startet der naechste Block noch vor dieser Abfrage und die Karte ruht kurz
            if (-not $paused -and $proc -and -not $proc.HasExited -and ((-not $cyc) -or ($now - $blkT0).TotalSeconds -gt 15)) { $gpuLauf = $gpu }
        } catch { }
        $tick = $now

        # --- Ollama fragen: laeuft dort gerade eine Anfrage? ---
        $ollActive = $false
        if ($OllamaApi) {
            $o = Get-OllamaState
            $dt = [math]::Max(0.5, ($now - $ollTime).TotalSeconds)
            if ($o.Ok) {
                $neu = @{}
                foreach ($n in $o.Namen) {
                    $neu[$n] = $o.Rest[$n]
                    # Modell taucht neu auf oder die Restzeit laeuft nicht ab: Ollama arbeitet
                    if (-not $ollRest.ContainsKey($n)) { $ollActive = $true }
                    elseif (($ollRest[$n] - $o.Rest[$n]) -lt ($dt * 0.5)) { $ollActive = $true }
                }
                $ollRest = $neu
                # Haelt Ollama seine Modelle unbegrenzt, sagt die Restzeit nichts aus: dann wieder ueber den Speicher
                if ($o.Unklar) { $ollActive = $false; $ollMb = 0.0 } else { $ollMb = $o.Mb }
            } else { $ollRest = @{}; $ollMb = 0.0 }
            $oll = $o; $ollTime = $now
            if ($ollActive) { $ollActiveAt = $now }
            elseif (($now - $ollActiveAt).TotalSeconds -ge $OllamaIdleSec) { $ollArmed = $true }
        }

        # --- VRAM-Automatik: pausieren, wenn andere Programme die Karte brauchen ---
        if ($gpu) { $vramNow = $gpu.MemUsed }
        if ($vramAt -and $now -ge $vramAt) {
            # Messung verwerfen, wenn Ollama in diesen 12 s Speicher belegt oder freigegeben hat
            if ($VramSelfMB -le 0 -and [math]::Abs($ollMb - $ollMbPre) -lt 50.0) {
                $d = ($vramNow - $vramPre) * $vramDir      # Richtung: +1 nach dem Start, -1 nach dem Stopp
                if ($d -ge 50 -and $d -le 8000) { $vramSelf = $d }
            }
            $vramAt = $null
        }
        # Belegung ohne BitCrack und ohne Ollama: in der Pause ist der ganze Rest fremd,
        # sonst der Anteil ueber dem Eigenbedarf. Ollamas Modelle zaehlen nicht mit, um die kuemmert
        # sich die Abfrage oben - ein geparktes Modell soll die Suche nicht anhalten.
        $vramOther = [math]::Max(0.0, [double]$vramNow - $(if ($paused) { 0.0 } else { [double]$vramSelf }) - [double]$ollMb)
        # Startprüfung, einmal: sobald der Eigenbedarf gemessen ist (im Wartemodus sofort). Belegen Desktop und andere
        # Programme schon mehr als die Schwelle, bliebe die Suche sonst unerklärlich dauerhaft stehen.
        if ($vramStartPruefung -and $gpu -and -not $vramAt) {
            $vramStartPruefung = $false
            if ($vramAuto -and $vramOther -ge $VramPauseMB) {
                Set-VramSperre 'start'
                $status = T 'dash.status.autoAusStart' $vramOther
            }
        }
        if ($vramAuto -and $gpu -and -not $vramAt) {
            if ($vramOther -lt $VramResumeMB) { $vramArmed = $true }
            $ollRuhig = (-not $OllamaApi) -or ((-not $ollActive) -and (($now - $ollActiveAt).TotalSeconds -ge $OllamaIdleSec))
            if (-not $paused) {
                if ($VramPauseMB -gt 0 -and -not $vramSperre -and $vramOther -ge $VramPauseMB) { $vramHi++ } else { $vramHi = 0 }
                if ($ollActive -and $ollArmed) {
                    Suspend-BC 'ollama'
                    $status = T 'dash.status.autoPauseOllama' $pauseAt
                } elseif ($vramArmed -and $VramPauseMB -gt 0 -and ($vramHi * $RefreshSec) -ge $VramHoldSec) {
                    $mb = $vramOther
                    Suspend-BC 'vram'
                    $status = T 'dash.status.autoPauseVram' $pauseAt $mb
                }
            } elseif ($autoPause) {
                if ($VramPauseMB -le 0 -or $vramOther -lt $VramResumeMB) { $vramLo++ } else { $vramLo = 0 }
                # War der Speicher nicht der Grund, reicht es, dass er jetzt frei ist
                $vramFrei = if ($pauseWhy -eq 'vram') { ($vramLo * $RefreshSec) -ge $VramBackSec } else { $vramLo -gt 0 }
                if ($vramFrei -and $ollRuhig) {
                    $mb = $vramOther; $why = $pauseWhy
                    Resume-BC
                    $status = if ($why -eq 'ollama') { T 'dash.status.autoStartOllama' (Get-Date) }
                              else { T 'dash.status.autoStartVram' (Get-Date) $mb }
                    if ($why -eq 'vram') {
                        # Pendelschutz: dreimal in 10 Minuten wegen Speicher pausiert und wieder gestartet - dann zählt
                        # vermutlich die Suche selbst mit (Eigenbedarf falsch gemessen). Speicherregel für diese Sitzung aus.
                        $vramRueck = @(@($vramRueck | Where-Object { ($now - $_).TotalMinutes -le 10 }) + $now)
                        if ($vramRueck.Count -ge 3) { Set-VramSperre 'pendel'; $status = T 'dash.status.autoAusPendel' }
                    }
                }
            }
        }

        # --- Checkpoint auswerten ---
        $cp = Read-Checkpoint
        if ($cp -and $cp.Start -eq $range.Start -and (-not $cpLast -or $cp.Pos -ne $cpLast.Pos)) {
            if ($cpLast -and $cp.Elapsed -gt $cpLast.Elapsed -and -not $skipSpd) {
                $speed = [double]($cp.Pos - $cpLast.Pos) / (($cp.Elapsed - $cpLast.Elapsed) / 1000.0)
            }
            $skipSpd = $false   # der erste Checkpoint nach einer Pause ueberspannt die Pause
            $cpLast = $cp
            [IO.File]::WriteAllText((Join-Path $Daten $fBak), $cp.Raw)
            # eine Zeile fuer die Kurve auf der Webseite (Anhang, ueberlebt Neustarts)
            if ($speed -gt 0) {
                try {
                    $hp = Join-Path $Daten $fHist
                    if (-not (Test-Path $hp)) { Set-Content -Encoding ascii -Path $hp -Value 'zeit;tempo;grad;watt' }
                    Add-Content -Encoding ascii -Path $hp -Value ([string]::Format($inv, '{0};{1:F0};{2:F0};{3:F0}',
                        (Get-Date).ToString('s'), $speed, $(if ($gpuLauf) { $gpuLauf.Temp } elseif ($gpu) { $gpu.Temp } else { 0 }), $(if ($gpuLauf) { $gpuLauf.Power } elseif ($gpu) { $gpu.Power } else { 0 })))
                } catch { }
            }
        } elseif ($cp -and $cp.Start -ne $range.Start) {
            $status = (T 'dash.status.progressFalsch' $fProg)
        }

        # CUDACyclone meldet jede Sekunde Tempo und Anzahl - das ersetzt die Hochrechnung zwischen Checkpoints
        if ($cyc -and -not $paused -and $proc -and -not $proc.HasExited) {
            Save-CycCheckpoint
            $liveNow = Read-CycLive
            # Tempo = Durchschnitt im laufenden Block (Anzahl / Zeit); der Momentwert von CUDACyclone schwankt um +-10 %.
            # In den ersten Sekunden eines Blocks gilt noch der Schnitt des vorigen Blocks.
            if ($liveNow) {
                $cycLive = $liveNow
                if ($liveNow.Sec -ge 5 -and $liveNow.Count -gt 0) { $speed = $liveNow.Count / $liveNow.Sec }
                elseif ($cycSpeed -gt 0) { $speed = $cycSpeed }
                elseif ($liveNow.Speed -gt 0) { $speed = $liveNow.Speed }
            }
        }
        $done = 0.0; $since = 0.0; $elapsed = 0.0
        if ($cyc) {
            if ($cpLast) { $done = [double]($cpLast.Pos - $range.Start); $since = ($now - $cpLast.Time).TotalSeconds; $elapsed = $cpLast.Elapsed / 1000.0 }
            if (-not $paused -and $cycLive -and $blk) {
                # Der erste Block eines Shares beginnt an der Blockgrenze davor: diesen Teil nicht mitzaehlen.
                # $cycOffset: beim Fortsetzen schon erledigte Schluessel, die CUDACyclone in Count nicht mitzaehlt.
                # Alle Faeden rechnen gleichzeitig ueber den ganzen Block (Kamm): der erledigte Anteil gilt
                # gleichmaessig fuer den neuen Teil des Blocks - ab next beim Blockstart, hoechstens bis zum Share-Ende
                $neuAnf = [Numerics.BigInteger]::Max($blk.Start, $blkNext)
                $neuEnd = [Numerics.BigInteger]::Min($blk.End, $range.End)
                $neu = [math]::Max(0.0, [double]($neuEnd - $neuAnf + 1))
                $done = [math]::Max(0.0, [double]($blkNext - $range.Start)) + [math]::Min(1.0, ($cycOffset + $cycLive.Count) / $blk.Size) * $neu
                $elapsed = $blkElapsed0 / 1000.0 + $cycLive.Sec
            }
            $done = [math]::Max(0.0, [math]::Min([double]$total, [double]$done))
        } elseif ($cpLast) {
            $done    = [double]($cpLast.Next - $range.Start)
            $since   = ($now - $cpLast.Time).TotalSeconds
            $elapsed = $cpLast.Elapsed / 1000.0
            if ($speed -gt 0) { $done = [math]::Min([double]$total, $done + $speed * [math]::Min([double]$since, 90.0)); $elapsed += [math]::Min([double]$since, 90.0) }
        }
        $frac = $done / $total
        $eta  = if ($speed -gt 0) { ($total - $done) / $speed } else { [double]::NaN }
        # Sekunden bis zum naechsten Checkpoint: bei CUDACyclone aus dem Rest des laufenden Blocks,
        # bei BitCrack schreibt das Programm selbst alle 60 s. $null = unbekannt (Pause, noch kein Wert).
        $naechsterCp = $null
        if (-not $paused -and $proc -and -not $proc.HasExited) {
            if ($cyc -and $blk -and $cycLive -and $cycLive.Sec -ge 5 -and $cycLive.Count -gt 0) {
                $v = $cycLive.Count / $cycLive.Sec
                $naechsterCp = [math]::Max(0.0, ($blk.Size - $cycOffset - $cycLive.Count) / $v)
                if ($cycResume -and $cycThreads -gt 0) {
                    # Mit Fortsetzen sichert CUDACyclone nach jedem Haeppchen: Faeden x Paketgroesse x Pakete je Start
                    $haeppchen = $cycThreads * [double](("$CycloneGrid" -split ',')[0]) * $(if ([int]$CycloneSlices -gt 0) { [double]$CycloneSlices } else { 64.0 })
                    $naechsterCp = [math]::Min($naechsterCp, [math]::Max(0.0, $haeppchen / $v - ($now - $cycCpTime).TotalSeconds))
                }
            } elseif ($cyc -and $blk -and $cycSpeed -gt 0) {
                $naechsterCp = [math]::Max(0.0, $blk.Size / $cycSpeed - ($now - $blkT0).TotalSeconds)
            } elseif (-not $cyc -and $cpLast) {
                $naechsterCp = [math]::Max(0.0, 60.0 - [double]$since)
            }
        }

        # --- Ausgabe ---
        $w = [Console]::WindowWidth
        if ($w -ne $lastW) { Clear-Host; $lastW = $w }
        [Console]::SetCursorPosition(0, 0)
        $dbl = [string][char]0x2550 * 62
        $dot = [string][char]0x00B7
        $deg = [string][char]0x00B0

        W "  $dbl" DarkCyan
        W "   $($AppName.ToUpper()) " Cyan "$AppVersion " DarkCyan "$dot Puzzle $Puzzle" White " $dot GPU $dev" Cyan (' ' * [math]::Max(1, 23 - $AppName.Length - "$AppVersion".Length - "$dev".Length - "$Puzzle".Length)) Gray $now.ToString((T 'dash.kopf.datum'), $Kultur) DarkGray
        W "  $dbl" DarkCyan
        W ''
        W (T 'dash.label.ziel') DarkGray $Address White
        if ($target.Off) {
            W (T 'dash.label.zielstatus') DarkGray (T 'dash.ziel.aus') DarkGray
        } elseif ($target.Ok) {
            $ts = T 'dash.ziel.geprueft' $target.Balance $target.Time
            if ($fromTable -and [math]::Abs($target.Balance - $Puzzle / 10.0) -gt 0.05) {
                $status = T 'dash.status.guthabenFalsch' $target.Balance $Puzzle
            }
            # bei fehlgeschlagener Abfrage ohne das Wort "geprüft", sonst wird die Zeile zu lang
            if ($target.Err) { W (T 'dash.label.zielstatus') DarkGray (T 'dash.ziel.offen') Green (F ' · {0:N2} BTC · {1:HH:mm}' $target.Balance $target.Time) DarkGray (T 'dash.ziel.abfrageFehlt') Yellow }
            else             { W (T 'dash.label.zielstatus') DarkGray (T 'dash.ziel.offen') Green $ts DarkGray }
        } else {
            W (T 'dash.label.zielstatus') DarkGray (T 'dash.ziel.nichtPruefbar') Yellow (T 'dash.ziel.naechsterVersuch' $target.Time.AddMinutes($CheckMin)) DarkGray
        }
        $shTxt = T 'dash.share.von' $Shares
        if ($doneCount -gt 0) { $shTxt += T 'dash.share.abgesucht' $doneCount $dot }
        W (T 'dash.label.share') DarkGray (F '{0:N0}' $share) White $shTxt DarkGray
        W (T 'dash.label.bereich') DarkGray $range.Start.ToString('X').TrimStart('0') Gray " $([char]0x2026) " DarkGray $range.End.ToString('X').TrimStart('0') Gray
        if ($paused) {
            $pTxt = if ($pauseWhy -eq 'wartet') { (T 'dash.pause.bereit') }
                    elseif ($pauseWhy -eq 'ollama') { (T 'dash.pause.autoOllama') }
                    elseif ($autoPause) { (T 'dash.pause.autoVram') } else { (T 'dash.pause.pause') }
            W (T 'dash.label.status') DarkGray (T 'dash.status.pauseSeit' $pauseAt (Fmt-Span ($now - $pauseAt).TotalSeconds) $pTxt) Yellow
        } else {
            W (T 'dash.label.status') DarkGray $(if ($proc.HasExited) { (T 'dash.status.gestoppt') } else { (T 'dash.status.laeuft') }) $(if ($proc.HasExited) { 'Red' } else { 'Green' })
        }
        W ''
        Section (T 'dash.abschnitt.fortschritt')
        $sg = BarSeg $frac 44 'Green'
        W '   ' Gray @sg '  ' Gray (F '{0:N4} %' ($frac * 100)) White
        W (T 'dash.label.geprueft') DarkGray (Fmt-Keys $done) White (T 'dash.gepr.von') DarkGray (Fmt-Keys $total) White (T 'dash.gepr.schluessel') DarkGray
        if ($paused) {
            $tTxt = if ($pauseWhy -eq 'wartet') { (T 'dash.tempo.nichtGestartet') } else { (T 'dash.tempo.angehalten' $motor) }
            W (T 'dash.label.tempo') DarkGray $tTxt Yellow
        } elseif ($speed -gt 0) {
            W (T 'dash.label.tempo') DarkGray (F '{0:N0} MKey/s' ($speed / 1e6)) White $(if ($cyc) { (T 'dash.tempo.blockSchnitt') } else { (T 'dash.tempo.cpSchnitt') }) DarkGray
        } else {
            W (T 'dash.label.tempo') DarkGray $(if ($cyc) { (T 'dash.tempo.ermittelt') } else { (T 'dash.tempo.ermittelt2') }) DarkGray
        }
        W (T 'dash.label.laufzeit') DarkGray (Fmt-Span $elapsed) White (T 'dash.laufzeit.rest') DarkGray (Fmt-Span $eta) White
        $cpTxt = if ($cyc -and $blk -and -not $paused) { T 'dash.cp.block' $blk.Bits $(if ($cycLive) { ($cycOffset + $cycLive.Count) / $blk.Size * 100 } else { $cycOffset / $blk.Size * 100 }) (Fmt-Span $since) }
                 elseif (-not $cpLast) { (T 'dash.cp.keiner') }
                 elseif ($paused) { T 'dash.cp.eingefroren' $cpLast.Time }
                 else { T 'dash.cp.vor' $since }
        W (T 'dash.label.checkpoint') DarkGray $cpTxt Gray
        W ''
        Section 'GPU'
        if ($gpu) {
            $eff = if ($gpu.Power -gt 0 -and $speed -gt 0) { F '{0:N2} MKey/J' ($speed / 1e6 / $gpu.Power) } else { '–' }
            W (T 'dash.label.karte') DarkGray $gpu.Name White "   $($gpu.PState)" DarkGray
            if ($profileName) { W (T 'dash.label.profil') DarkGray $profileName White $(if ($cyc) { "   CUDACyclone $CycloneGrid" } else { "   $Tuning" }) DarkGray }
            else { W (T 'dash.label.profil') DarkGray (T 'dash.profil.standard') Yellow (T 'dash.profil.ungemessen') Yellow }   # bleibt stehen, anders als die Statuszeile
            $sg = BarSeg ($gpu.Power / $gpu.Limit) 24 (Col ($gpu.Power / $gpu.Limit) 0.97 1.05)
            W (T 'dash.label.leistung') DarkGray (F '{0,5:N0} W  ' $gpu.Power) White @sg (F '  Limit {0:N0} W' $gpu.Limit) DarkGray
            $sg = BarSeg ($gpu.Temp / 90) 24 (Col $gpu.Temp 75 83)
            W (T 'dash.label.temperatur') DarkGray (F "{0,5:N0} ${deg}C " $gpu.Temp) (Col $gpu.Temp 75 83) @sg
            $fanV = 0.0; [void][double]::TryParse($gpu.Fan, [Globalization.NumberStyles]::Float, $inv, [ref]$fanV)
            $sg = BarSeg ($fanV / 100) 24 (Col $fanV 65 85)
            W (T 'dash.label.luefter') DarkGray (F '{0,5:N0} %  ' $fanV) (Col $fanV 65 85) @sg
            $sg = BarSeg ($gpu.Util / 100) 24 'Cyan'
            W (T 'dash.label.auslastung') DarkGray (F '{0,5:N0} %  ' $gpu.Util) White @sg
            if ($VramPauseMB -gt 0) {
                $vCol = if ($vramOther -ge $VramPauseMB) { 'Yellow' } else { 'White' }
                W (T 'dash.label.vram') DarkGray (F '{0:N0} / {1:N0} MB' $gpu.MemUsed $gpu.MemTotal) White (T 'dash.vram.fremd' $vramOther) $vCol
            } else {
                W (T 'dash.label.vram') DarkGray (F '{0:N0} / {1:N0} MB' $gpu.MemUsed $gpu.MemTotal) White
            }
            W (T 'dash.label.effizienz') DarkGray $eff White
            if ($OllamaApi) {
                if (-not $oll -or -not $oll.Ok)  { W (T 'dash.label.ollama') DarkGray (T 'dash.ollama.nichtErreichbar') DarkGray }
                elseif ($oll.Namen.Count -eq 0)  { W (T 'dash.label.ollama') DarkGray (T 'dash.ollama.keinModell') DarkGray }
                else {
                    $nm = if ($oll.Namen.Count -gt 1) { T 'dash.ollama.modelle' $oll.Namen.Count } else { [string]$oll.Namen[0] }
                    if ($nm.Length -gt 15) { $nm = $nm.Substring(0, 14) + [string][char]0x2026 }
                    $zu = if ($ollActive) { (T 'dash.ollama.rechnet') }
                          elseif ($oll.Unklar) { (T 'dash.ollama.geparkt') }
                          else { T 'dash.ollama.geparktSek' ([math]::Max(0.0, [double]$oll.Rest[[string]$oll.Namen[0]])) }
                    W (T 'dash.label.ollama') DarkGray $nm White (F ' {0} {1:N0} MB {0} ' $dot $oll.Mb) DarkGray $zu $(if ($ollActive) { 'Yellow' } else { 'Green' })
                }
            }
        } else {
            1..$(if ($OllamaApi) { 9 } else { 8 }) | ForEach-Object { W (T 'dash.gpu.keineDaten') DarkGray }
        }
        W ''
        Section (T 'dash.abschnitt.sitzung')
        if ($null -eq $naechsterCp) {
            W (T 'dash.label.dauer') DarkGray (Fmt-Span ($now - $t0).TotalSeconds) White
        } else {
            # Kurz vor dem Checkpoint gelb: jetzt lieber noch nicht abbrechen
            $ncFarbe = if ($naechsterCp -lt 30) { 'Yellow' } else { 'DarkGray' }
            $ncTxt = if ($naechsterCp -lt 5) { (T 'dash.cp.gleich') }
                     else { T 'dash.cp.in' ([int][math]::Floor($naechsterCp / 60)) ([int][math]::Floor($naechsterCp) % 60) }
            W (T 'dash.label.dauer') DarkGray (Fmt-Span ($now - $t0).TotalSeconds) White $ncTxt $ncFarbe
        }
        W (T 'dash.label.energie') DarkGray (F '{0:N3} kWh' ($wh / 1000)) White (F '   ≈ {0:N2} €' ($wh / 1000 * $PricePerKwh)) Yellow (T 'dash.energie.bei' ($PricePerKwh * 100)) DarkGray
        # Abgesuchte Shares ohne Treffer scheiden aus: der Schlüssel liegt in einem der übrigen
        W (T 'dash.label.chance') DarkGray (F '1 : {0:N0}' ([math]::Max(1.0, [double]$Shares - $doneCount))) White (T 'dash.chance.pro') DarkGray
        W ''
        # Statuszeile bleibt innerhalb des Rahmens (Einzug 3 + 61 Zeichen = Spalte 64)
        $stTxt = "$status"
        if ($stTxt.Length -gt 61) { $stTxt = $stTxt.Substring(0, 60) + [string][char]0x2026 }
        W "   $stTxt" Yellow
        $fussZeile = [Console]::CursorTop   # hier schreibt Show-Beenden "Wird beendet ..."
        if ([P71.Guard]::Closing)                { Write-BeendenZeile }
        elseif ($quitAsk)                        { W (T 'dash.fuss.frage') Yellow (T 'dash.fuss.ja') Red "  $dot  " DarkGray (T 'dash.fuss.nein') Green }
        elseif ($paused -and $pauseWhy -eq 'wartet') { W (T 'dash.fuss.start') Green ("  $dot  " + (T 'dash.fuss.oderWeb')) DarkGray }
        elseif ($paused -and $pauseWhy -eq 'ollama') { W (T 'dash.fuss.weiter') Yellow ("  $dot  " + (T 'dash.fuss.autoStartOllama')) DarkGray }
        elseif ($paused -and $autoPause)   { W (T 'dash.fuss.weiter') Yellow ("  $dot  " + (T 'dash.fuss.autoStartVram')) DarkGray }
        elseif ($paused)                   { W (T 'dash.fuss.weiter') Yellow ("  $dot  " + (T 'dash.fuss.gpuFrei')) DarkGray }
        elseif ($VramPauseMB -gt 0 -or $OllamaApi -or $WebPort -gt 0) {
            $t1 = if ($vramAuto) { (T 'dash.fuss.an') } else { (T 'dash.fuss.aus') }
            $t2 = if ($webAn) { (T 'dash.fuss.an') } else { (T 'dash.fuss.aus') }
            if ($WebPort -gt 0 -and ($VramPauseMB -gt 0 -or $OllamaApi)) {
                W (T 'dash.fuss.pause') Cyan ("  $dot  " + (T 'dash.fuss.autoPause')) DarkGray $t1 $(if ($vramAuto) { 'Green' } else { 'DarkGray' }) `
                  ("  $dot  " + (T 'dash.fuss.webseite')) DarkGray $t2 $(if ($webAn) { 'Green' } else { 'DarkGray' })
            } elseif ($WebPort -gt 0) {
                W (T 'dash.fuss.pause') Cyan ("  $dot  " + (T 'dash.fuss.webseite')) DarkGray $t2 $(if ($webAn) { 'Green' } else { 'DarkGray' }) ("  $dot  " + (T 'dash.fuss.strgC')) DarkGray
            } else {
                W (T 'dash.fuss.pause') Cyan ("  $dot  " + (T 'dash.fuss.autoPause')) DarkGray $t1 $(if ($vramAuto) { 'Green' } else { 'DarkGray' }) ("  $dot  " + (T 'dash.fuss.strgC')) DarkGray
            }
        }
        else                               { W (T 'dash.fuss.pause') Cyan  $(if ($cyc) { (T 'dash.fuss.cycBlock' $dot ($(if ($cycResume) { $CycloneResumeSec } else { $CycloneBlockSec }) / 60.0)) } else { (T 'dash.fuss.bcCheckpoint' $dot) }) DarkGray }

        # Titelzeile: Name, Version, Karte; die Messwerte stehen im Fenster. Pause/Bereit sieht man so auch in der Taskleiste.
        $titel = if ($paused) { (T 'dash.titel.pause' $appTitel $(if ($pauseWhy -eq 'wartet') { (T 'dash.pause.bereit') } else { (T 'dash.pause.pause') })) } else { (T 'dash.titel.normal' $appTitel) }
        if ([P71.Guard]::Closing) { $titel = (T 'dash.titel.wirdBeendet' $appTitel) }
        if ($Host.UI.RawUI.WindowTitle -ne $titel) { $Host.UI.RawUI.WindowTitle = $titel }

        # --- Webseite am Leben halten (auch wenn das Fenster der anderen GPU sie mitgenommen hat) ---
        # Hielt das Fenster der anderen GPU den Port und ist es zu, springt die Seite hierher.
        if ($webAn -and ($now - $webCheck).TotalSeconds -ge 30) {
            $webCheck = $now
            Start-Web
        }

        # --- Momentaufnahme für web.ps1 ---
        Write-Status $(if ($paused -and $pauseWhy) { "pause-$pauseWhy" } elseif ($paused) { 'pause' }
                       elseif ($proc.HasExited) { 'gestoppt' } else { 'laeuft' })

        # --- Warten und dabei auf die Pausentaste hoeren ---
        $key = Wait-Key $RefreshSec
        if ($key -eq 'TrayEnde') { $status = T 'dash.status.endeTray' (Get-Date); break }
        if ($quitAsk) {
            # Rückfrage nach Strg+C: J oder ein zweites Strg+C beendet, jede andere Taste
            # (oder 30 s ohne Antwort) lässt weiter suchen und wird danach normal behandelt
            if ($key -eq 'J' -or $key -eq 'Y' -or $key -eq 'CtrlC') { $status = T 'dash.status.endeStrgC' (Get-Date); break }
            if ($key -or ((Get-Date) - $quitAsk).TotalSeconds -ge 30) { $quitAsk = $null }
        }
        if ($key -eq 'CtrlC') {
            $quitAsk = Get-Date
        } elseif ($key -eq 'P') {   # nur P - die Leertaste pausierte bis 15.09.2026 mit, versehentlich beim Tippen in ein anderes Programm
            if ($paused) {
                $wasAuto = $autoPause
                Resume-BC
                # Von Hand trotz belegter Karte gestartet: erst wieder automatisch pausieren,
                # wenn der Speicher zwischendurch frei war bzw. Ollama einmal geruht hat.
                if ($wasAuto) { $vramArmed = $false; $ollArmed = $false }
                $status = T 'dash.status.fortgesetzt' (Get-Date)
            } else {
                Suspend-BC 'hand'
                $status = T 'dash.status.pauseAb' $pauseAt
            }
        } elseif ($key -eq 'W' -and $WebPort -gt 0) {
            $webAn = -not $webAn; Save-Merken
            if ($webAn) {
                $webFehler = $false
                Start-Web; $webCheck = Get-Date
                if ($webListener) { $status = (T 'dash.status.webAn' "http://$(if ($WebBind -in '+', '*') { $pc } else { $WebBind }):$WebPort/") }
            } else { Stop-Web; $status = (T 'dash.status.webAus') }
        } elseif ($key -eq 'V' -and ($VramPauseMB -gt 0 -or $OllamaApi) -and -not $paused) {
            $vramAuto = -not $vramAuto; $vramSperre = ''; $vramRueck = @(); Save-Merken   # V hebt eine Sperre (Start/Pendel) auf
            $vramHi = 0; $vramLo = 0
            $status = if (-not $vramAuto) { (T 'dash.status.autoAus') }
                      elseif ($OllamaApi -and $VramPauseMB -gt 0) { T 'dash.status.autoAnBeide' ([double]$VramPauseMB) }
                      elseif ($OllamaApi) { (T 'dash.status.autoAnOllama') }
                      else { T 'dash.status.autoAnVram' ([double]$VramPauseMB) }
        }
    }
}
finally {
    Show-Beenden
    # Tray: Symbol weg, Fenster wieder zeigen - "Wird beendet ..." soll man sehen, und nach Treffer/Absturz wartet
    # "Enter drücken" (sonst unsichtbar). Beim X ist das Fenster schon am Schließen.
    if ($tray) { if ([P71.Guard]::Closing) { Stop-Tray } else { Stop-Tray -Zeigen } }
    # Beim X bleibt nur wenig Zeit: letzte Meldung an MQTT zuerst (Write-Status schreibt dann nichts mehr)
    if ($mqtt -and [P71.Guard]::Closing) { Stop-Mqtt (T 'dash.status.fensterGeschlossen' (Get-Date)) }
    if ($cyc -and -not $paused) { try { Save-CycCheckpoint } catch { } }
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force; $proc.WaitForExit(10000) | Out-Null }
    Restore-Progress $range
    if ($usePl -gt 0) { & $smi -i $dev -pl $defaultPl | Out-Null }
    [Console]::CursorVisible = $true
    [P71.Guard]::RestoreConsoleMode()
    try { $Host.UI.RawUI.BufferSize = New-Object Management.Automation.Host.Size $Host.UI.RawUI.BufferSize.Width, 3000 } catch { }
    Remove-Item (Join-Path $Daten $fPause) -ErrorAction SilentlyContinue
    try { Write-Status $(if ($result) { $result } else { 'beendet' }) } catch { }
    # Die Seite fragt alle 2 s: noch 3 s bedienen, damit sie den Endzustand abholt
    if ($webListener -and $webListener.IsListening) { $bis = (Get-Date).AddSeconds(3); while ((Get-Date) -lt $bis) { try { Step-Web } catch { }; Start-Sleep -Milliseconds 100 } }
    Stop-Web   # der Webserver lief in diesem Fenster mit und geht mit ihm; ein Fenster der anderen GPU holt ihn binnen 30 s
    if ($mqtt) { Stop-Mqtt }   # letzter Zustand ging mit Write-Status raus; jetzt "offline" und abmelden
    $Host.UI.RawUI.WindowTitle = (T 'dash.titel.beendet' $appTitel)   # erst jetzt, vorher stand dort "wird beendet ..."
    if ($lock) { $lock.Dispose() }
    Write-Host ''
    if ($usePl -gt 0) { Write-Host (T 'dash.ende.gpuPl' $dev $defaultPl) -ForegroundColor Cyan }
    else              { Write-Host (T 'dash.ende.gpu' $dev) -ForegroundColor Cyan }
    Write-Host (T 'dash.ende.sitzung' (Fmt-Span ((Get-Date) - $t0).TotalSeconds) ($wh / 1000) ($wh / 1000 * $PricePerKwh)) -ForegroundColor DarkGray
}

if ($result -eq 'found') {
    Write-Host ''
    $bar = '   ' + ('*' * 61)
    Write-Host $bar -ForegroundColor Green
    Write-Host ('   ***  ' + (T 'dash.treffer.datei' $fFound).PadRight(53) + '***') -ForegroundColor Green
    Write-Host ('   ***  ' + (T 'dash.treffer.mempool').PadRight(53) + '***') -ForegroundColor Green
    Write-Host $bar -ForegroundColor Green
    1..5 | ForEach-Object { [console]::Beep(1200, 400); Start-Sleep -Milliseconds 200 }
} elseif ($result -eq 'solved') {
    Write-Host ''
    Write-Host (T 'dash.ende.geloest' $Puzzle) -ForegroundColor Yellow
    Write-Host (T 'dash.ende.suchBeendet') -ForegroundColor Yellow
} elseif ($result -eq 'crash') {
    Write-Host ''
    Write-Host (T 'dash.ende.crash' $motor) -ForegroundColor Red
    Get-Content $fErr -Tail 10 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
    if ($cyc) {
        $lt = ''; try { $lt = [IO.File]::ReadAllText((Join-Path $Daten $fLog)) } catch { }
        if ($lt) { ($lt.Substring([math]::Max(0, $lt.Length - 400)) -split "[`r`n]+") | Where-Object { $_.Trim() } | Select-Object -Last 6 | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray } }
    }
}

# Meldung sichtbar lassen, auch wenn das Fenster sonst sofort schliessen wuerde (Start aus cmd/Launcher)
if ($result) {
    Write-Host ''
    [void](Read-Host (T 'dash.ende.enter'))
}

# Prozess wirklich beenden: Die Fenster je Karte und der Neustart mit Adminrechten laufen mit -NoExit (damit
# Fehlermeldungen vor der Hauptschleife stehen bleiben). Ohne das bliebe nach dem Ende die Eingabeaufforderung
# stehen, beim X druckte PowerShell sie bis zum Abschuss durch Windows immer wieder (15.09.2026 bei zwei Karten).
[Environment]::Exit(0)
