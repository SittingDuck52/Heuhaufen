# tuning.ps1 - ermittelt selbststaendig die besten BitCrack-Einstellungen fuer die Grafikkarte(n)
#
# Ablauf je Kartenmodell:
#   1. Rechenprobe: BitCrack sucht den bekannten Schluessel von Puzzle 32 (wenige Sekunden)
#   2. Tuning-Reihe beim Standard-Power-Limit: -b/-p schrittweise verdoppeln, bis es nicht mehr
#      spuerbar schneller wird, der Speicher knapp wird oder BitCrack abbricht
#   3. Leistungsreihe mit dieser Einstellung: Power-Limit in Stufen senken
#   4. Rechenprobe mit dem Ergebnis, Power-Limit zurueck, Bericht, auf Wunsch in puzzle-config.ps1
#   5. Stecken mehrere gleiche Karten im Rechner: gemeinsamer Lauf aller Karten dieses Modells mit dem
#      empfohlenen Limit (je Stufe 5 Minuten). Drosselt eine Karte wegen Hitze, wird das Limit fuer alle
#      in 10-%-Schritten gesenkt, bis keine mehr drosselt. Allein gemessen wird eine Karte nicht heiss genug.
#
# Gemessen wird wie im Dashboard ueber die Checkpoint-Datei: Zuwachs zwischen erstem und zweitem
# Checkpoint geteilt durch die Zeit. Der erste Checkpoint allein taugt nicht, er enthaelt die
# Startphase (gemessen 13.09.2026: -b 128 -p 2048 zeigte dort 904 statt 1.030 MKey/s).
# Ein Messlauf dauert deshalb gut zwei Minuten, das Ganze je Karte etwa 10 bis 20 Minuten.
# Gemessen wird nie gegen ein echtes Ziel: die Adresse von Puzzle 32 liegt nicht im Messbereich.
# Alle Arbeitsdateien landen in einem Temp-Ordner und werden danach geloescht.
param(
    [string]$Device = 'all',     # 'all' = jedes Kartenmodell einmal messen, sonst GPU-Index (0, 1, ...)
    [switch]$OhneLimit,          # Power-Limit nicht anfassen: keine Adminrechte, keine Leistungsreihe
    [int]$MinTempo = 90,         # Power-Limit: sparsamste Stufe mit mindestens so viel % des Hoechsttempos
    [ValidateSet('', 'bitcrack', 'cyclone')]
    [string]$Programm = '',      # Suchprogramm; leer = wie in puzzle-config.ps1 bzw. im Profil der Karte
    [switch]$Eintragen,          # Ergebnis ohne Rueckfrage in puzzle-config.ps1 schreiben
    [switch]$Einzeln,            # keinen gemeinsamen Lauf gleicher Karten
    [switch]$Gemeinsam           # gemeinsamen Lauf auch mit nur einer Karte bzw. mit -Device <Nummer> (zum Testen)
)

# ================= Einstellungen =================
$CheckAddr  = '1FRoHA9xewq7DjrZ1psWJVeTer8gHRqEvR'    # Puzzle 32, geloest
$CheckKey   = 'B862A62E'
$CheckRange = '80000000:FFFFFFFF'
$MessRange  = '4A0000000000000000:7FFFFFFFFFFFFFFFFF'   # im Bereich von Puzzle 71, Schluessel oben liegt nicht darin
$Stufen = @(                     # Punkte = b * t * p
    '-b 8 -t 128 -p 256',        #     262.144  nur als Rueckfall
    '-b 16 -t 256 -p 256',       #   1.048.576  Rueckfall
    '-b 32 -t 256 -p 512',       #   4.194.304  Start (Standard von puzzle.ps1)
    '-b 64 -t 256 -p 512',       #   8.388.608
    '-b 64 -t 256 -p 1024',      #  16.777.216
    '-b 128 -t 256 -p 1024',     #  33.554.432
    '-b 128 -t 256 -p 2048',     #  67.108.864
    '-b 256 -t 256 -p 2048',     # 134.217.728
    '-b 256 -t 256 -p 4096'      # 268.435.456
)
$StartStufe = 2
$Zuwachs    = 3.0      # % - so viel schneller muss die naechste Stufe sein, sonst endet die Reihe
$Nahe       = 98.0     # % - gewaehlt wird die kleinste Stufe mit so viel vom besten Tempo (spart VRAM)
$VramAnteil = 0.6      # hoechstens dieser Anteil des Grafikspeichers fuer BitCrack
$RamAnteil  = 0.5      # hoechstens dieser Anteil des freien Arbeitsspeichers
$LaufMaxSec = 300      # laenger darf ein Messlauf nicht brauchen
$PlStufen   = @(0.9, 0.8, 0.7, 0.6)   # Anteile des Standard-Power-Limits fuer die Leistungsreihe
$CycStufen  = @('128,128|16', '512,512', '1024,1024')   # CUDACyclone: --grid A,B, nach | optional --slices
$CycMessBits = 36      # CUDACyclone: Messbereich 2^36 Schluessel; ist ein Lauf kuerzer als 30 s, wird er groesser
$Engine = 'cyclone'    # Suchprogramm (wie puzzle.ps1), puzzle-config.ps1 kann es ueberschreiben
$GemeinsamSek       = 300   # gemeinsamer Lauf: Dauer je Stufe (die Hitze staut sich erst nach einigen Minuten)
$GemeinsamAuswertSek = 150   # davon ausgewertet: die letzten Sekunden
$GemeinsamFaktor    = 0.9    # drosselt eine Karte, naechste Stufe mit diesem Anteil des Limits
$GemeinsamStufenMax = 4      # hoechstens so viele Absenkungen
$PricePerKwh = 0.30
$Sprache = ''   # 'de' oder 'en'; leer = Windows-Anzeigesprache (puzzle-config.ps1 kann es setzen)
$GpuProfiles = $null
# =================================================

$win = $env:SystemRoot
$fwd = "-Device $Device -MinTempo $MinTempo" + $(if ($Programm) { " -Programm $Programm" } else { '' }) + $(if ($OhneLimit) { ' -OhneLimit' } else { '' }) + $(if ($Eintragen) { ' -Eintragen' } else { '' }) + $(if ($Einzeln) { ' -Einzeln' } else { '' }) + $(if ($Gemeinsam) { ' -Gemeinsam' } else { '' })
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-Device', $Device, '-MinTempo', $MinTempo)
    if ($OhneLimit) { $a += '-OhneLimit' }
    if ($Eintragen) { $a += '-Eintragen' }
    if ($Einzeln) { $a += '-Einzeln' }
    if ($Gemeinsam) { $a += '-Gemeinsam' }
    if ($Programm) { $a += @('-Programm', $Programm) }
    & "$win\Sysnative\WindowsPowerShell\v1.0\powershell.exe" @a
    exit
}
$psExe = "$win\System32\WindowsPowerShell\v1.0\powershell.exe"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $OhneLimit) {
    try {
        Start-Process $psExe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$PSCommandPath`" $fwd" -ErrorAction Stop
    } catch {
        . (Join-Path $PSScriptRoot 'sprache.ps1')   # Meldung ohne Config: Windows-Sprache
        Write-Host ''
        Write-Host (T 'tun.start.keinAdmin1') -ForegroundColor Yellow
        Write-Host (T 'tun.start.keinAdmin2') -ForegroundColor Yellow
        Write-Host ''
    }
    exit
}

# Ordner: skripte\ (dieses Skript), programm\ (BitCrack), daten\ (Sperrdateien, Bericht)
$Basis = Split-Path $PSScriptRoot -Parent
$Daten = Join-Path $Basis 'daten'
# Name und Versionsnummer (skripte\version.ps1) fuer Titel und Bericht
$AppName = 'Heuhaufen'; $AppVersion = '?'
if (Test-Path (Join-Path $PSScriptRoot 'version.ps1')) { . (Join-Path $PSScriptRoot 'version.ps1') }
if (-not (Test-Path $Daten)) { New-Item -ItemType Directory -Path $Daten -Force | Out-Null }
Set-Location $Basis
Add-Type -AssemblyName System.Numerics
$de  = [Globalization.CultureInfo]'de-DE'
$inv = [Globalization.CultureInfo]::InvariantCulture
$interaktiv = $false
try { $interaktiv = -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected } catch { }

. (Join-Path $PSScriptRoot 'sprache.ps1')   # erst Windows-Sprache (fuer Meldungen beim Laden der Config)
$cfgFile = Join-Path $Basis 'puzzle-config.ps1'
if (Test-Path $cfgFile) { try { . $cfgFile } catch { Write-Host (T 'tun.start.cfgFehler' $_.Exception.Message) -ForegroundColor Yellow } }
. (Join-Path $PSScriptRoot 'sprache.ps1'); $de = $Kultur   # nach der Config: $Sprache von dort gilt, Zahlen im Format der Sprache

$exe    = Join-Path $Basis 'programm\cuBitCrack.exe'
$cycExe = Join-Path $Basis 'programm\CUDACyclone.exe'
if (-not (Test-Path $exe) -and -not (Test-Path $cycExe)) { Write-Host (T 'tun.start.exeFehlt') -ForegroundColor Red; exit 1 }
if (-not (Test-Path (Join-Path $Basis 'programm\cudart64_12.dll'))) { Write-Host (T 'tun.start.dllFehlt') -ForegroundColor Red; exit 1 }

$smi = @(
    (Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue).Source
    "$win\System32\nvidia-smi.exe"
    "$env:ProgramW6432\NVIDIA Corporation\NVSMI\nvidia-smi.exe"
) + @(Get-ChildItem "$win\System32\DriverStore\FileRepository\nv*\nvidia-smi.exe" -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) |
    Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $smi) { Write-Host (T 'tun.start.keinSmi') -ForegroundColor Red; exit 1 }

# Schutz: BitCrack stirbt mit dem Fenster, beim Schliessen wird das Power-Limit zurueckgesetzt
if (-not ('P71T.Guard' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
namespace P71T {
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
    public static void DisableQuickEdit() {
        IntPtr h = GetStdHandle(-10);
        uint m;
        if (GetConsoleMode(h, out m)) { savedMode = m; modeSaved = true; SetConsoleMode(h, (m & ~0x40u) | 0x80u); }
    }
    public static void RestoreConsoleMode() { if (modeSaved) SetConsoleMode(GetStdHandle(-10), savedMode); }
    static IntPtr job = IntPtr.Zero;
    static CtrlHandler handler;
    static string smiPath;
    public static string ResetArgs;
    static Process child;
    public static void Init(string smi) {
        smiPath = smi;
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
            try { if (child != null && !child.HasExited) child.Kill(); } catch { }
            // ResetArgs: ein Aufruf je Karte, getrennt durch '|' (gemeinsamer Lauf mehrerer Karten)
            if (!String.IsNullOrEmpty(ResetArgs)) {
                foreach (string a in ResetArgs.Split('|')) {
                    if (a.Trim().Length == 0) continue;
                    try {
                        ProcessStartInfo psi = new ProcessStartInfo(smiPath, a.Trim());
                        psi.UseShellExecute = false; psi.CreateNoWindow = true;
                        using (Process p = Process.Start(psi)) { p.WaitForExit(2000); }
                    } catch { }
                }
            }
        }
        return false;
    }
}
}
"@
}
[P71T.Guard]::Init($smi)
[P71T.Guard]::DisableQuickEdit()

# ---------- Hilfsfunktionen ----------
function F([string]$fmt) { [string]::Format($de, $fmt, $args) }
function Hex([string]$x) { [Numerics.BigInteger]::Parse('0' + $x, [Globalization.NumberStyles]::AllowHexSpecifier) }
function Num([string]$s) {
    $d = 0.0
    if ([double]::TryParse("$s".Trim(), [Globalization.NumberStyles]::Float, $inv, [ref]$d)) { $d } else { [double]::NaN }
}
function Mittel($werte) {
    $w = @($werte | Where-Object { -not [double]::IsNaN($_) })
    if ($w.Count -eq 0) { [double]::NaN } else { [double]($w | Measure-Object -Average).Average }
}
function Hoechst($werte) {
    $w = @($werte | Where-Object { -not [double]::IsNaN($_) })
    if ($w.Count -eq 0) { [double]::NaN } else { [double]($w | Measure-Object -Maximum).Maximum }
}
# Zahl rechtsbuendig, '-' fuer unbekannt
function Z([double]$v, [string]$fmt, [int]$breite) {
    if ([double]::IsNaN($v) -or [double]::IsInfinity($v)) { '-'.PadLeft($breite) } else { [string]::Format($de, "{0,$breite$fmt}", $v) }
}
function Get-Punkte([string]$t) {
    $b  = [double][regex]::Match($t, '-b\s+(\d+)').Groups[1].Value
    $th = [double][regex]::Match($t, '-t\s+(\d+)').Groups[1].Value
    $p  = [double][regex]::Match($t, '-p\s+(\d+)').Groups[1].Value
    $b * $th * $p
}
function Smi-Query([int]$i, [string]$fields) {
    $r = @(& $smi -i $i "--query-gpu=$fields" --format=csv,noheader,nounits)
    if ($LASTEXITCODE -ne 0 -or $r.Count -eq 0) { return $null }
    ,@("$($r[0])" -split ',' | ForEach-Object { $_.Trim() })
}
function Get-Probe([int]$i) {
    $v = Smi-Query $i 'power.draw,memory.used,temperature.gpu,fan.speed,utilization.gpu'
    if (-not $v -or $v.Count -lt 5) { return $null }
    [pscustomobject]@{ Watt = Num $v[0]; Mem = Num $v[1]; Temp = Num $v[2]; Fan = Num $v[3]; Util = Num $v[4]; Phase = $false }
}
function Set-Limit([int]$i, [int]$w) {
    & $smi -i $i -pl $w | Out-Null
    $v = Smi-Query $i 'power.limit'
    [bool]($v -and [math]::Abs((Num $v[0]) - [double]$w) -lt 1.5)
}
# Einzeilige Fortschrittsanzeige (nur in einem echten Fenster)
function Zeile([string]$text) {
    if (-not $interaktiv) { return }
    $w = 79
    try { $w = [Console]::WindowWidth - 1 } catch { }
    if ($text.Length -gt $w) { $text = $text.Substring(0, $w) }
    Write-Host -NoNewline ("`r" + $text.PadRight($w))
}
function Zeile-Weg { Zeile ''; if ($interaktiv) { Write-Host -NoNewline "`r" } }
function Frage([string]$text) {
    if (-not $interaktiv) { return $false }
    $a = Read-Host $text
    return ($a -match '^\s*[jJyY]')
}

function Start-BC([int]$i, [string]$argLine, [string]$name) {
    $p = Start-Process -FilePath $exe -ArgumentList "-d $i -c $argLine" -WorkingDirectory $tmp -WindowStyle Hidden `
        -RedirectStandardOutput (Join-Path $tmp "$name.out") -RedirectStandardError (Join-Path $tmp "$name.err") -PassThru
    $null = $p.Handle   # sonst ist der ExitCode spaeter nicht mehr lesbar
    [void][P71T.Guard]::Attach($p)
    $p
}
function Stop-BC($p) {
    if ($p -and -not $p.HasExited) { try { $p.Kill() } catch { }; [void]$p.WaitForExit(15000) }
}
# Letzte aussagekraeftige Zeile aus dem Fehlerprotokoll von BitCrack
function Get-BCFehler([string]$name) {
    $zeilen = @(Get-Content (Join-Path $tmp "$name.err") -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
    if ($zeilen.Count -eq 0) { return (T 'tun.bcOhneMeldung') }
    $err = @($zeilen | Where-Object { $_ -match 'error|fail|memory|resources' })
    $z = if ($err.Count) { $err[-1] } else { $zeilen[-1] }
    ($z -replace '^\[[^\]]*\]\s*\[\w+\]\s*', '').Trim()
}
# Checkpoint lesen, ohne BitCrack beim Schreiben zu behindern
function Read-Cp([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    try {
        $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]'ReadWrite, Delete')
        $sr = New-Object IO.StreamReader($fs)
        $txt = $sr.ReadToEnd(); $sr.Close()
    } catch { return $null }
    $h = @{}
    foreach ($l in $txt -split "`r?`n") { if ($l -match '^(\w+)=(.+)$') { $h[$matches[1]] = $matches[2].Trim() } }
    if (-not ($h.next -and $h.elapsed -and $h.stride)) { return $null }   # stride ist die letzte Zeile: Datei vollstaendig
    try { [pscustomobject]@{ Next = Hex $h.next; Elapsed = [double]::Parse($h.elapsed, $inv) } } catch { $null }
}

# ---------- Rechenprobe: findet BitCrack den bekannten Schluessel von Puzzle 32? ----------
function Test-Rechnung([int]$i, [string]$tun) {
    $out = Join-Path $tmp 'probe.txt'
    if (Test-Path $out) { [IO.File]::Delete($out) }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-BC $i "$tun --keyspace $CheckRange -o probe.txt $CheckAddr" 'probe'
    while (-not $p.HasExited -and $sw.Elapsed.TotalSeconds -lt $LaufMaxSec) {
        Zeile (T 'tun.probe.laeuft' $tun $sw.Elapsed.TotalSeconds)
        Start-Sleep -Milliseconds 500
    }
    $sek = $sw.Elapsed.TotalSeconds
    $haengt = -not $p.HasExited
    Stop-BC $p
    Zeile-Weg
    $ok = $false; $grund = ''
    if (Test-Path $out) {
        $teile = @(((Get-Content $out | Where-Object { $_.Trim() } | Select-Object -First 1) + '').Trim() -split '\s+')
        try { $ok = ($teile.Count -ge 2 -and $teile[0] -eq $CheckAddr -and (Hex $teile[1]) -eq (Hex $CheckKey)) } catch { $ok = $false }
        if (-not $ok) { $grund = (T 'tun.probe.falsch' ($teile -join ' ')) }
    } elseif ($haengt) { $grund = (T 'tun.probe.nichts' $LaufMaxSec) }
    else { $grund = Get-BCFehler 'probe' }
    [pscustomobject]@{ Ok = $ok; Grund = $grund; Sek = $sek; Tuning = $tun }
}
function Show-Probe($r) {
    if ($r.Ok) { Write-Host (T 'tun.probe.ok' $r.Tuning $r.Sek) -ForegroundColor Green }
    else       { Write-Host (T 'tun.probe.fehler' $r.Tuning $r.Grund) -ForegroundColor Red }
}

# ---------- Ein Messlauf: Tempo zwischen erstem und zweitem Checkpoint ----------
function Invoke-Messung([int]$i, [string]$tun, [double]$limit) {
    $cp = Join-Path $tmp 'mess.cp'
    if (Test-Path $cp) { [IO.File]::Delete($cp) }   # sonst setzt BitCrack mit alten Werten fort
    Start-Sleep -Seconds 3                           # Speicher des vorigen Laufs freigeben lassen
    $basis = Get-Probe $i
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-BC $i "$tun --keyspace $MessRange --continue mess.cp $CheckAddr" 'mess'
    $cp1 = $null; $cp2 = $null; $letzte = -99.0; $peak = 0L; $pr = $null
    $proben = New-Object Collections.ArrayList
    while ($true) {
        $t = $sw.Elapsed.TotalSeconds
        if ($p.HasExited -or $t -gt $LaufMaxSec) { break }
        $c = Read-Cp $cp
        if ($c) {
            if (-not $cp1) { $cp1 = $c }
            elseif ($c.Elapsed -gt $cp1.Elapsed) { $cp2 = $c; break }
        }
        if ($t - $letzte -ge 2) {
            $letzte = $t
            $pr = Get-Probe $i
            if ($pr) { $pr.Phase = [bool]$cp1; [void]$proben.Add($pr) }
            try { $p.Refresh(); if ($p.PeakWorkingSet64 -gt $peak) { $peak = $p.PeakWorkingSet64 } } catch { }
        }
        $frac = [math]::Min(1.0, $t / 125.0)
        $n = [int][math]::Round($frac * 20)
        $bar = '[' + ('#' * $n) + ('-' * (20 - $n)) + ']'
        $info = if ($pr) { (Z $pr.Watt ':N0' 4) + ' W ' + (Z $pr.Temp ':N0' 3) + ' C' } else { '' }
        Zeile ('   ' + $tun.PadRight(22) + (Z $limit ':N0' 5) + ' W  ' + $bar + (Z $t ':N0' 4) + ' s  ' + $info)
        Start-Sleep -Milliseconds 500
    }
    $fehler = ''
    if (-not $cp2) {
        if ($p.HasExited) { $fehler = Get-BCFehler 'mess' } else { $fehler = (T 'tun.mess.keineCp' $LaufMaxSec) }
    }
    Stop-BC $p
    Zeile-Weg
    $speed = [double]::NaN
    if ($cp2) { $speed = [double]($cp2.Next - $cp1.Next) / ($cp2.Elapsed - $cp1.Elapsed) * 1000.0 }
    $ph = @($proben | Where-Object { $_.Phase })
    if ($ph.Count -lt 3) { $ph = @($proben) }
    $watt = Mittel ($ph | ForEach-Object { $_.Watt })
    $mkey = $speed / 1e6
    $vram = [double]::NaN
    if ($basis -and $proben.Count) { $vram = (Hoechst ($proben | ForEach-Object { $_.Mem })) - $basis.Mem }
    [pscustomobject]@{
        Tuning = $tun; Punkte = Get-Punkte $tun; Limit = $limit
        Ok = [bool]$cp2; Fehler = $fehler
        MKey = $mkey; Watt = $watt; Eff = $mkey / $watt
        Temp = Hoechst ($ph | ForEach-Object { $_.Temp }); Fan = Mittel ($ph | ForEach-Object { $_.Fan })
        Util = Mittel ($ph | ForEach-Object { $_.Util })
        Vram = $vram; Ram = $peak / 1MB
    }
}
function Show-Kopf {
    Write-Host ('   ' + (T 'tun.kopf.einstellung').PadRight(22) + '  Limit' + '   MKey/s' + '   Watt' + '  MKey/J' + '   Temp' + '    VRAM') -ForegroundColor DarkGray
}
function Show-Lauf($r) {
    $t = '   ' + $r.Tuning.PadRight(22) + (Z $r.Limit ':N0' 5) + ' W'
    if ($r.Ok) {
        $t += (Z $r.MKey ':N0' 9) + (Z $r.Watt ':N0' 7) + (Z $r.Eff ':N2' 8) + (Z $r.Temp ':N0' 5) + ' C' + (Z $r.Vram ':N0' 8) + ' MB'
        $farbe = if ($r.Util -lt 90) { 'Yellow' } else { 'Gray' }
        Write-Host $t -ForegroundColor $farbe
        if ($r.Util -lt 90) { Write-Host (T 'tun.lauf.auslastung' $r.Util) -ForegroundColor Yellow }
    } else {
        Write-Host ($t + (T 'tun.abgebrochen') + $r.Fehler) -ForegroundColor Yellow
    }
}

# Laeuft auf dieser GPU schon BitCrack? Ohne lesbare Kommandozeile zaehlt jede Instanz.
function Get-FremdBC([int]$i) {
    @(Get-CimInstance Win32_Process -Filter "Name='cuBitCrack.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $cl = [string]$_.CommandLine
        (-not $cl) -or ($cl -match "(^|\s)-d\s+$i(\s|$)") -or ($i -eq 0 -and $cl -notmatch '(^|\s)-d\s+\d')
    })
}

# ---------- CUDACyclone ----------
# CUDACyclone kann nicht fortsetzen und schreibt keine Checkpoints. Gemessen wird deshalb ein voller Durchlauf
# ueber 2^36 Schluessel: Anzahl geteilt durch die Rechenzeit aus seiner eigenen Anzeige (ohne Startphase).
function Start-Cyc([int]$i, [string[]]$argv, [string]$name) {
    # CUDACyclone nimmt immer die erste sichtbare Karte: nur diese zeigen, Reihenfolge wie nvidia-smi
    $env:CUDA_DEVICE_ORDER = 'PCI_BUS_ID'; $env:CUDA_VISIBLE_DEVICES = "$i"
    try {
        $p = Start-Process -FilePath $cycExe -ArgumentList $argv -WorkingDirectory $tmp -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $tmp "$name.out") -RedirectStandardError (Join-Path $tmp "$name.err") -PassThru
    } finally { Remove-Item Env:CUDA_VISIBLE_DEVICES, Env:CUDA_DEVICE_ORDER -ErrorAction SilentlyContinue }
    $null = $p.Handle
    [void][P71T.Guard]::Attach($p)
    $p
}
function Get-CycArgs([string]$grid) {
    $teile = $grid -split '\|'
    $a = @('--grid', $teile[0])
    if ($teile.Count -gt 1 -and $teile[1]) { $a += @('--slices', $teile[1]) }
    ,$a
}
function Get-CycText([string]$name) {
    "$(Get-Content (Join-Path $tmp "$name.out") -Raw -ErrorAction SilentlyContinue)`n$(Get-Content (Join-Path $tmp "$name.err") -Raw -ErrorAction SilentlyContinue)"
}
function Get-CycFehler([string]$txt) {
    $z = @(($txt -split "[`r`n]+") | Where-Object { $_ -match 'Error|error|fail' })
    if ($z.Count) { $z[-1].Trim() } else { (T 'tun.cycOhneMeldung') }
}
function Test-CycRechnung([int]$i, [string]$grid) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Cyc $i (@('--range', $CheckRange, '--address', $CheckAddr) + (Get-CycArgs $grid)) 'probe'
    while (-not $p.HasExited -and $sw.Elapsed.TotalSeconds -lt $LaufMaxSec) {
        Zeile (T 'tun.probe.laeuftGrid' $grid $sw.Elapsed.TotalSeconds)
        Start-Sleep -Milliseconds 500
    }
    $sek = $sw.Elapsed.TotalSeconds; $haengt = -not $p.HasExited
    Stop-BC $p
    Zeile-Weg
    $txt = Get-CycText 'probe'
    $m = [regex]::Match($txt, 'Private Key\s*:\s*([0-9A-Fa-f]+)')
    $ok = $false; $grund = ''
    if ($m.Success) {
        try { $ok = ((Hex $m.Groups[1].Value) -eq (Hex $CheckKey)) } catch { $ok = $false }
        if (-not $ok) { $grund = (T 'tun.probe.falscherSchluessel' $m.Groups[1].Value) }
    }
    elseif ($haengt) { $grund = (T 'tun.probe.nichts' $LaufMaxSec) }
    elseif ($txt -match 'KEY NOT FOUND') { $grund = (T 'tun.probe.uebersehen') }
    else { $grund = Get-CycFehler $txt }
    [pscustomobject]@{ Ok = $ok; Grund = $grund; Sek = $sek; Tuning = "grid $grid" }
}
function Invoke-CycMessung([int]$i, [string]$grid, [double]$limit) {
    $bits = $script:cycBits
    while ($true) {
        $start = [Numerics.BigInteger]::Parse('04A0000000000000000', [Globalization.NumberStyles]::AllowHexSpecifier)
        $ende  = $start + [Numerics.BigInteger]::Pow(2, $bits) - 1
        $range = $start.ToString('X').TrimStart('0') + ':' + $ende.ToString('X').TrimStart('0')
        Start-Sleep -Seconds 3                           # Speicher des vorigen Laufs freigeben lassen
        $basis = Get-Probe $i
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $p = Start-Cyc $i (@('--range', $range, '--address', $CheckAddr) + (Get-CycArgs $grid)) 'mess'
        $proben = New-Object Collections.ArrayList; $letzte = -99.0; $pr = $null
        while (-not $p.HasExited -and $sw.Elapsed.TotalSeconds -lt $LaufMaxSec) {
            $t = $sw.Elapsed.TotalSeconds
            if ($t - $letzte -ge 2) {
                $letzte = $t
                $pr = Get-Probe $i
                if ($pr) { $pr.Phase = ($t -gt 6); [void]$proben.Add($pr) }
            }
            $info = if ($pr) { (Z $pr.Watt ':N0' 4) + ' W ' + (Z $pr.Temp ':N0' 3) + ' C' } else { '' }
            Zeile ('   ' + ("grid $grid").PadRight(22) + (Z $limit ':N0' 5) + ' W  ' + (F '2^{0}' $bits) + (Z $t ':N0' 5) + ' s  ' + $info)
            Start-Sleep -Milliseconds 500
        }
        $haengt = -not $p.HasExited
        Stop-BC $p
        Zeile-Weg
        $txt = Get-CycText 'mess'
        $ok = (-not $haengt) -and ($txt -match 'KEY NOT FOUND \(exhaustive\)')
        $zm = [regex]::Matches($txt, 'Time:\s*([0-9.]+)\s*s\s*\|\s*Speed:\s*([0-9.]+)\s*Mkeys/s\s*\|\s*Count:\s*(\d+)')
        $zeitProg = 0.0; $anzahl = 0.0
        if ($zm.Count) {
            $zeitProg = [double]::Parse($zm[$zm.Count - 1].Groups[1].Value, $inv)
            $anzahl   = [double]::Parse($zm[$zm.Count - 1].Groups[3].Value, $inv)
        }
        # Zu kurz fuer eine brauchbare Verbrauchsmessung (schnelle Karte): gleiche Einstellung, vierfacher Bereich
        if ($ok -and $zeitProg -lt 30 -and $bits -lt 44) { $bits += 2; $script:cycBits = $bits; continue }
        break
    }
    $speed = if ($ok -and $zeitProg -gt 0 -and $anzahl -gt 0) { $anzahl / $zeitProg } else { [double]::NaN }
    $ph = @($proben | Where-Object { $_.Phase })
    if ($ph.Count -lt 3) { $ph = @($proben) }
    $watt = Mittel ($ph | ForEach-Object { $_.Watt })
    $mkey = $speed / 1e6
    $vram = [double]::NaN
    if ($basis -and $proben.Count) { $vram = (Hoechst ($proben | ForEach-Object { $_.Mem })) - $basis.Mem }
    $ab = $grid -split '[,|]'
    [pscustomobject]@{
        Tuning = "grid $grid"; Grid = $grid; Punkte = [double]$ab[0] * [double]$ab[1]; Limit = $limit
        Ok = $ok; Fehler = $(if ($ok) { '' } elseif ($haengt) { (T 'tun.mess.nichtFertig' $LaufMaxSec) } else { Get-CycFehler $txt })
        MKey = $mkey; Watt = $watt; Eff = $mkey / $watt
        Temp = Hoechst ($ph | ForEach-Object { $_.Temp }); Fan = Mittel ($ph | ForEach-Object { $_.Fan })
        Util = Mittel ($ph | ForEach-Object { $_.Util })
        Vram = $vram; Ram = 0.0
    }
}

# Profilwerte als Text, so wie sie in puzzle-config.ps1 stehen sollen
function Get-ProfilWerte($e) {
    $werte = [ordered]@{}
    if ($e.GemLimit) { $werte['PowerLimit'] = "$([int]$e.GemLimit)" }       # gemeinsamer Lauf gleicher Karten geht vor
    elseif ($e.PlWahl) { $werte['PowerLimit'] = "$([int]$e.PlWahl.Limit)" }
    if ($e.Engine -eq 'cyclone') {
        $teile = $e.Wahl.Grid -split '\|'
        $werte['Engine'] = "'cyclone'"
        $werte['CycloneGrid'] = "'$($teile[0])'"
        $werte['CycloneSlices'] = $(if ($teile.Count -gt 1 -and $teile[1]) { $teile[1] } else { '0' })
    } else {
        # Ausdruecklich mit -Programm bitcrack gemessen: dann auch zurueck auf BitCrack schalten
        if ($Programm -eq 'bitcrack') { $werte['Engine'] = "'bitcrack'" }
        $werte['Tuning'] = "'$($e.Wahl.Tuning)'"
    }
    $werte
}

# ---------- Messung einer Karte ----------
function Test-Karte($g) {
    $i = $g.Index
    $erg = [pscustomobject]@{
        Index = $i; Name = $g.Name; Key = (($g.Name -replace '^NVIDIA\s+', '') -replace '^GeForce\s+', '').Trim()
        Ok = $false; Grund = ''; Treiber = ''; Reihe = @(); Leistung = @(); Wahl = $null; PlWahl = $null
        PlDef = [double]::NaN; PlMin = [double]::NaN; PlMax = [double]::NaN; LimitGemessen = $false; Hinweise = @()
        Gemeinsam = @(); GemLimit = $null; GemKarten = @()
    }
    Write-Host ''
    Write-Host "   ===== GPU ${i}: $($g.Name) =====" -ForegroundColor Cyan
    $info = Smi-Query $i 'driver_version,memory.total,power.limit,power.default_limit,power.min_limit,power.max_limit'
    if (-not $info) { $erg.Grund = (T 'tun.smiKeineDaten'); Write-Host "   $($erg.Grund)" -ForegroundColor Red; return $erg }
    $erg.Treiber = $info[0]
    $memTotal = Num $info[1]; $plNow = Num $info[2]
    $erg.PlDef = Num $info[3]; $erg.PlMin = Num $info[4]; $erg.PlMax = Num $info[5]
    Write-Host (T 'tun.karte.treiber' $info[0] $memTotal) -ForegroundColor DarkGray
    if (-not [double]::IsNaN($erg.PlDef)) {
        Write-Host (T 'tun.karte.limit' $plNow $erg.PlDef $erg.PlMin $erg.PlMax) -ForegroundColor DarkGray
    }

    # Suchprogramm fuer diese Karte: Schalter -Programm, sonst Profil, sonst puzzle-config.ps1
    $eng = $Programm
    if (-not $eng) {
        $eng = "$Engine"
        if ($GpuProfiles) { foreach ($k2 in @($GpuProfiles.Keys)) { if ($g.Name -like "*$k2*") { if (@($GpuProfiles[$k2].Keys) -contains 'Engine') { $eng = $GpuProfiles[$k2]['Engine'] }; break } } }
    }
    $eng = "$eng".Trim().ToLower()
    if ($eng -ne 'cyclone') { $eng = 'bitcrack' }
    # Standard ist CUDACyclone; fehlt es (alter Ordner), wie puzzle.ps1 mit BitCrack weitermachen
    if ($eng -eq 'cyclone' -and -not $Programm -and -not (Test-Path $cycExe)) {
        Write-Host (T 'tun.karte.cycFehltBc') -ForegroundColor Yellow
        $eng = 'bitcrack'
    }
    $cycK = ($eng -eq 'cyclone')
    $erg | Add-Member NoteProperty Engine $eng
    $script:cycBits = $CycMessBits
    Write-Host ((T 'tun.karte.programm') + $(if ($cycK) { 'CUDACyclone' } else { 'BitCrack' })) -ForegroundColor DarkGray
    if ($cycK -and -not (Test-Path $cycExe)) { $erg.Grund = (T 'tun.karte.cycFehlt'); Write-Host "   $($erg.Grund)" -ForegroundColor Red; return $erg }
    if (-not $cycK -and -not (Test-Path $exe)) { $erg.Grund = (T 'tun.karte.bcFehlt'); Write-Host "   $($erg.Grund)" -ForegroundColor Red; return $erg }

    # Nichts darf die Karte gerade benutzen
    $lockF = Join-Path $Daten "bitcrack-$env:COMPUTERNAME-gpu$i.lock"
    if (Test-Path $lockF) {
        try { $fs = [IO.File]::Open($lockF, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None); $fs.Close() }
        catch { $erg.Grund = (T 'tun.karte.dashboardOffen' $i); Write-Host "   $($erg.Grund)" -ForegroundColor Red; return $erg }
    }
    if (@(Get-Process CUDACyclone -ErrorAction SilentlyContinue).Count -gt 0) { $erg.Grund = (T 'tun.karte.cycLaeuft'); Write-Host "   $($erg.Grund)" -ForegroundColor Red; return $erg }
    if ((Get-FremdBC $i).Count -gt 0) { $erg.Grund = (T 'tun.karte.bcLaeuft' $i); Write-Host "   $($erg.Grund)" -ForegroundColor Red; return $erg }
    $util = Mittel (1..3 | ForEach-Object { $x = Get-Probe $i; Start-Sleep -Milliseconds 700; if ($x) { $x.Util } else { [double]::NaN } })
    if ($util -gt 15) {
        Write-Host (T 'tun.karte.ausgelastet' $util) -ForegroundColor Yellow
        if (-not (Frage (T 'tun.karte.trotzdem'))) { $erg.Grund = (T 'tun.karte.beschaeftigt'); return $erg }
    }

    $limitAn = (-not $OhneLimit) -and -not [double]::IsNaN($erg.PlDef) -and -not [double]::IsNaN($erg.PlMin) -and $erg.PlMin -lt $erg.PlDef
    if (-not $OhneLimit -and -not $limitAn) { Write-Host (T 'tun.karte.limitFest') -ForegroundColor Yellow }
    $plStart = $plNow
    try {
        if ($limitAn) {
            [P71T.Guard]::ResetArgs = F '-i {0} -pl {1:0}' $i $plStart
            if ($plNow -ne $erg.PlDef -and -not (Set-Limit $i ([int]$erg.PlDef))) {
                Write-Host (T 'tun.karte.limitStandardFehler') -ForegroundColor Yellow
                $limitAn = $false
            }
        }
        $messPl = if ($limitAn) { $erg.PlDef } else { $plNow }

        # 1. Rechenprobe mit kleiner Einstellung
        Write-Host ''
        $pr = if ($cycK) { Test-CycRechnung $i $CycStufen[1] } else { Test-Rechnung $i $Stufen[0] }
        Show-Probe $pr
        if (-not $pr.Ok) { $erg.Grund = (T 'tun.karte.probeFehler' $pr.Grund); return $erg }

        # 2. Tuning-Reihe
        Write-Host ''
        Write-Host $(if ($cycK) { (T 'tun.reihe.cyc') } else { (T 'tun.reihe.bc') }) -ForegroundColor Cyan
        Show-Kopf
        if ($cycK) {
            foreach ($gs in $CycStufen) {
                $rc = Invoke-CycMessung $i $gs $messPl
                Show-Lauf $rc
                $erg.Reihe += $rc
            }
            $okR = @($erg.Reihe | Where-Object { $_.Ok })
            if ($okR.Count -eq 0) { $erg.Grund = (T 'tun.reihe.cycKeine' $erg.Reihe[-1].Fehler); return $erg }
            $best = $okR | Sort-Object MKey -Descending | Select-Object -First 1
        } else {
        $k = $StartStufe
        $r = Invoke-Messung $i $Stufen[$k] $messPl
        Show-Lauf $r
        $erg.Reihe += $r
        while (-not $r.Ok -and $k -gt 0) {
            $k--
            $r = Invoke-Messung $i $Stufen[$k] $messPl
            Show-Lauf $r
            $erg.Reihe += $r
        }
        if (-not $r.Ok) { $erg.Grund = (T 'tun.reihe.bcKeine' $r.Fehler); return $erg }
        $best = $r
        while ($k + 1 -lt $Stufen.Count) {
            $naechste = $Stufen[$k + 1]
            $faktor = (Get-Punkte $naechste) / $r.Punkte
            if (-not [double]::IsNaN($r.Vram) -and $r.Vram * $faktor -gt $VramAnteil * $memTotal) {
                $erg.Hinweise += T 'tun.reihe.endeVram' $naechste ($r.Vram * $faktor)
                break
            }
            $frei = 0.0
            try { $frei = [double](Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024 } catch { }
            if ($frei -gt 0 -and $r.Ram * $faktor -gt $RamAnteil * $frei) {
                $erg.Hinweise += T 'tun.reihe.endeRam' $naechste ($r.Ram * $faktor)
                break
            }
            $k++
            $r2 = Invoke-Messung $i $naechste $messPl
            Show-Lauf $r2
            $erg.Reihe += $r2
            if (-not $r2.Ok) { $erg.Hinweise += (T 'tun.reihe.endeAbbruch' $naechste $r2.Fehler); break }
            $gewinn = ($r2.MKey / $best.MKey - 1) * 100
            if ($r2.MKey -gt $best.MKey) { $best = $r2 }
            if ($gewinn -lt $Zuwachs) {
                $erg.Hinweise += T 'tun.reihe.endeGewinn' $naechste $gewinn
                break
            }
            $r = $r2
        }
        }
        $gute = @($erg.Reihe | Where-Object { $_.Ok -and $_.MKey -ge $best.MKey * $Nahe / 100 } | Sort-Object Punkte)
        $erg.Wahl = $gute[0]

        # 3. Leistungsreihe
        $erg.Leistung = @($erg.Wahl)
        if ($limitAn -and [double]::IsNaN($erg.Wahl.Watt)) {
            $erg.Hinweise += (T 'tun.leistung.keinVerbrauch')
        } elseif ($limitAn) {
            $stufenW = @()
            foreach ($f in $PlStufen) {
                $w = [int][math]::Round($erg.PlDef * $f)
                if ($w -lt $erg.PlMin) { $w = [int][math]::Ceiling($erg.PlMin) }
                if ($w -lt $erg.PlDef - 4 -and -not ($stufenW | Where-Object { [math]::Abs($_ - $w) -lt 5 })) { $stufenW += $w }
            }
            if ($stufenW.Count) {
                Write-Host ''
                Write-Host ((T 'tun.leistung.reihe' $erg.Wahl.Tuning) + ($stufenW -join ', ') + ' W)') -ForegroundColor Cyan
                Show-Kopf
                Show-Lauf $erg.Wahl
                foreach ($w in $stufenW) {
                    if (-not (Set-Limit $i $w)) { $erg.Hinweise += (T 'tun.leistung.setzenFehler' $w); break }
                    $erg.LimitGemessen = $true
                    $r3 = if ($cycK) { Invoke-CycMessung $i $erg.Wahl.Grid $w } else { Invoke-Messung $i $erg.Wahl.Tuning $w }
                    Show-Lauf $r3
                    if (-not $r3.Ok) { $erg.Hinweise += (T 'tun.leistung.abbruch' $w $r3.Fehler); break }
                    $erg.Leistung += $r3
                    if ($r3.MKey -lt $erg.Wahl.MKey * $MinTempo / 100) { break }   # noch weniger lohnt nicht
                }
                [void](Set-Limit $i ([int]$erg.PlDef))
            }
        }
        if ($limitAn) {
            $top = Hoechst ($erg.Leistung | ForEach-Object { $_.MKey })
            $erg.PlWahl = @($erg.Leistung | Where-Object { $_.MKey -ge $top * $MinTempo / 100 -and -not [double]::IsNaN($_.Eff) } |
                Sort-Object @{ Expression = 'Eff'; Descending = $true }, @{ Expression = 'Limit'; Descending = $false }) | Select-Object -First 1
        }

        # 4. Rechenprobe mit dem Ergebnis
        Write-Host ''
        $pr2 = if ($cycK) { Test-CycRechnung $i $erg.Wahl.Grid } else { Test-Rechnung $i $erg.Wahl.Tuning }
        Show-Probe $pr2
        if (-not $pr2.Ok) { $erg.Grund = (T 'tun.karte.probe2Fehler' $erg.Wahl.Tuning $pr2.Grund); return $erg }
        $erg.Ok = $true
        $erg
    } finally {
        if ($limitAn -or [P71T.Guard]::ResetArgs) { & $smi -i $i -pl ([int]$plStart) | Out-Null }
        [P71T.Guard]::ResetArgs = ''
    }
}

# ---------- Gemeinsamer Lauf gleicher Karten ----------
# Allein wird eine Karte nicht so heiss wie im Verbund (gesehen bei 2 x RTX 2080 Ti: GPU 1 drosselte nur, wenn
# beide rechneten). Darum laufen hier alle Karten eines Modells gleichzeitig mit dem empfohlenen Limit.
# Drosselt eine, wird das Limit fuer alle gesenkt - das Profil gilt ohnehin fuer das Modell, nicht je Karte.
function Get-GemProbe([int]$i) {
    $felder = 'power.draw,memory.used,temperature.gpu,fan.speed,utilization.gpu'
    if ($null -eq $script:drosselFeld) {
        # Feldname je nach Treiber: neu clocks_event_reasons, alt clocks_throttle_reasons
        $script:drosselFeld = ''
        foreach ($pre in 'clocks_event_reasons', 'clocks_throttle_reasons') {
            $t = Smi-Query $i "$pre.sw_thermal_slowdown"
            if ($t -and "$($t[0])" -match 'Active') { $script:drosselFeld = $pre; break }
        }
    }
    $pre = $script:drosselFeld
    if ($pre) { $felder += ",$pre.sw_thermal_slowdown,$pre.hw_thermal_slowdown,$pre.hw_slowdown" }
    $v = Smi-Query $i $felder
    if (-not $v -or $v.Count -lt 5) { return $null }
    $dr = [double]::NaN
    if ($v.Count -ge 8) { $dr = $(if (@($v[5..7] | Where-Object { "$_" -match '^Active' }).Count) { 1.0 } else { 0.0 }) }
    [pscustomobject]@{ Watt = Num $v[0]; Mem = Num $v[1]; Temp = Num $v[2]; Fan = Num $v[3]; Util = Num $v[4]; Drossel = $dr; Phase = $false }
}

# Eine Stufe: alle Karten starten, $GemeinsamSek laufen lassen, die letzten $GemeinsamAuswertSek auswerten
function Invoke-GemStufe($e, $karten, [double]$limit, [bool]$setzen) {
    if ($setzen) { foreach ($k in $karten) { if (-not (Set-Limit $k.Index ([int]$limit))) { return $null } } }
    Start-Sleep -Seconds 3
    $cyc = ($e.Engine -eq 'cyclone')
    $laeufe = @()
    foreach ($k in $karten) {
        $name = "gem$($k.Index)"
        if ($cyc) {
            $p = Start-Cyc $k.Index (@('--range', $script:gemRange, '--address', $CheckAddr) + (Get-CycArgs $e.Wahl.Grid)) $name
        } else {
            $cp = Join-Path $tmp "$name.cp"
            if (Test-Path $cp) { [IO.File]::Delete($cp) }
            $p = Start-BC $k.Index "$($e.Wahl.Tuning) --keyspace $MessRange --continue $name.cp $CheckAddr" $name
        }
        $laeufe += [pscustomobject]@{ Index = $k.Index; Name = $name; P = $p; Proben = (New-Object Collections.ArrayList); Cps = (New-Object Collections.ArrayList) }
    }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $letzte = -99.0; $info = ''; $frueh = $false
    while ($sw.Elapsed.TotalSeconds -lt $GemeinsamSek) {
        $t = $sw.Elapsed.TotalSeconds
        if (@($laeufe | Where-Object { $_.P.HasExited }).Count) { $frueh = $true; break }
        if ($t - $letzte -ge 2) {
            $letzte = $t
            $teile = @()
            foreach ($l in $laeufe) {
                $pr = Get-GemProbe $l.Index
                if ($pr) {
                    $pr.Phase = ($t -ge $GemeinsamSek - $GemeinsamAuswertSek)
                    [void]$l.Proben.Add($pr)
                    $teile += "GPU$($l.Index)" + (Z $pr.Watt ':N0' 4) + ' W' + (Z $pr.Temp ':N0' 3) + ' C'
                }
                if (-not $cyc) {
                    $c = Read-Cp (Join-Path $tmp "$($l.Name).cp")
                    if ($c -and ($l.Cps.Count -eq 0 -or $c.Elapsed -gt $l.Cps[$l.Cps.Count - 1].Elapsed)) { [void]$l.Cps.Add($c) }
                }
            }
            $info = $teile -join ' | '
        }
        Zeile ('   ' + (Z $limit ':N0' 4) + ' W' + (Z $t ':N0' 5) + '/' + $GemeinsamSek + ' s  ' + $info)
        Start-Sleep -Milliseconds 500
    }
    foreach ($l in $laeufe) { Stop-BC $l.P }
    Zeile-Weg

    $ergeb = @()
    foreach ($l in $laeufe) {
        $mkey = [double]::NaN; $fehler = ''
        $mindest = [math]::Min(60.0, $GemeinsamAuswertSek / 2.0)
        if ($cyc) {
            $txt = Get-CycText $l.Name
            $zm = [regex]::Matches($txt, 'Time:\s*([0-9.]+)\s*s\s*\|\s*Speed:\s*([0-9.]+)\s*Mkeys/s\s*\|\s*Count:\s*(\d+)')
            $pts = @($zm | ForEach-Object { [pscustomobject]@{ T = [double]::Parse($_.Groups[1].Value, $inv); N = [double]::Parse($_.Groups[3].Value, $inv) } })
            if ($pts.Count -ge 2) {
                $pb = $pts[$pts.Count - 1]
                $pa = @($pts | Where-Object { $_.T -ge $pb.T - $GemeinsamAuswertSek })[0]
                if ($pb.T - $pa.T -ge $mindest) { $mkey = ($pb.N - $pa.N) / ($pb.T - $pa.T) / 1e6 }
            }
            if ([double]::IsNaN($mkey)) {
                $fehler = if ($txt -match 'KEY NOT FOUND') { (T 'tun.gem.zuFrueh') } elseif ($frueh) { Get-CycFehler $txt } else { (T 'tun.gem.keineTempo') }
            }
        } else {
            if ($l.Cps.Count -ge 2) {
                $cb = $l.Cps[$l.Cps.Count - 1]
                $ca = @($l.Cps | Where-Object { $_.Elapsed -ge $cb.Elapsed - ($GemeinsamAuswertSek + 5) * 1000.0 })[0]
                if ($cb.Elapsed - $ca.Elapsed -ge $mindest * 1000.0) { $mkey = [double]($cb.Next - $ca.Next) / ($cb.Elapsed - $ca.Elapsed) * 1000.0 / 1e6 }
            }
            if ([double]::IsNaN($mkey)) { $fehler = if ($frueh) { Get-BCFehler $l.Name } else { (T 'tun.gem.zuWenigeCp') } }
        }
        $ph = @($l.Proben | Where-Object { $_.Phase })
        if ($ph.Count -lt 3) { $ph = @($l.Proben) }
        $watt = Mittel ($ph | ForEach-Object { $_.Watt })
        $ergeb += [pscustomobject]@{
            Index = $l.Index; Limit = $limit; Ok = -not [double]::IsNaN($mkey); Fehler = $fehler
            MKey = $mkey; Watt = $watt; Eff = $mkey / $watt
            Temp = Hoechst ($ph | ForEach-Object { $_.Temp }); Fan = Mittel ($ph | ForEach-Object { $_.Fan })
            Util = Mittel ($ph | ForEach-Object { $_.Util }); Drossel = Mittel ($ph | ForEach-Object { $_.Drossel })
            Befund = ''
        }
    }
    # Drosselt eine Karte? Meldung des Treibers, zu wenig Leistung trotz Hitze, oder deutlich langsamer als die schnellste
    $top = Hoechst (@($ergeb | Where-Object { $_.Ok }) | ForEach-Object { $_.MKey })
    foreach ($r in $ergeb) {
        $gr = @()
        if ($r.Drossel -ge 0.2) { $gr += (T 'tun.befund.temperatur') }
        if ($limit -gt 0 -and $r.Watt -lt 0.85 * $limit -and $r.Util -ge 80 -and ($r.Temp -ge 83 -or $r.Fan -ge 90)) { $gr += (T 'tun.befund.leistung') }
        if ($ergeb.Count -gt 1 -and $r.Ok -and $r.MKey -lt 0.9 * $top) { $gr += (T 'tun.befund.langsamer') }
        $r.Befund = $gr -join ', '
    }
    [pscustomobject]@{ Limit = $limit; Karten = $ergeb }
}
function Show-GemStufe($s) {
    foreach ($r in $s.Karten) {
        $t = '   GPU ' + "$($r.Index)".PadRight(3) + (Z $r.Limit ':N0' 5) + ' W'
        if ($r.Ok) {
            $t += (Z $r.MKey ':N0' 9) + (Z $r.Watt ':N0' 7) + (Z $r.Eff ':N2' 8) + (Z $r.Temp ':N0' 5) + ' C' + (Z $r.Fan ':N0' 5) + ' %  '
            if ($r.Befund) { Write-Host ($t + (T 'tun.gem.drosselt') + $r.Befund + ')') -ForegroundColor Yellow }
            else { Write-Host ($t + 'ok') }
        } else {
            Write-Host ($t + (T 'tun.abgebrochen') + $r.Fehler) -ForegroundColor Yellow
        }
    }
    $ok = @($s.Karten | Where-Object { $_.Ok })
    if ($ok.Count -gt 1) {
        $sm = ($ok | Measure-Object MKey -Sum).Sum; $sw = ($ok | Measure-Object Watt -Sum).Sum
        Write-Host ((T 'tun.gem.zusammen') + (Z $sm ':N0' 15) + (Z $sw ':N0' 7) + (Z ($sm / $sw) ':N2' 8)) -ForegroundColor DarkGray
    }
}

function Invoke-Gemeinsam($e, $karten) {
    Write-Host ''
    Write-Host ((T 'tun.gem.titel') + (($karten | ForEach-Object { "GPU $($_.Index)" }) -join ' + ') + " ($($e.Key)) =====") -ForegroundColor Cyan
    Write-Host (T 'tun.gem.erklaerung' ($GemeinsamSek / 60.0)) -ForegroundColor DarkGray
    $e.GemKarten = @($karten | ForEach-Object { $_.Index })

    # Die anderen Karten muessen ebenso frei sein wie die gemessene
    foreach ($k in $karten) {
        $lockF = Join-Path $Daten "bitcrack-$env:COMPUTERNAME-gpu$($k.Index).lock"
        if (Test-Path $lockF) {
            try { $fs = [IO.File]::Open($lockF, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None); $fs.Close() }
            catch { $e.Hinweise += (T 'tun.gem.entfaelltDashboard' $k.Index); Write-Host "   $($e.Hinweise[-1])" -ForegroundColor Yellow; return }
        }
        if ((Get-FremdBC $k.Index).Count -gt 0) { $e.Hinweise += (T 'tun.gem.entfaelltBc' $k.Index); Write-Host "   $($e.Hinweise[-1])" -ForegroundColor Yellow; return }
    }
    if (@(Get-Process CUDACyclone -ErrorAction SilentlyContinue).Count -gt 0) { $e.Hinweise += (T 'tun.gem.entfaelltCyc'); Write-Host "   $($e.Hinweise[-1])" -ForegroundColor Yellow; return }

    # Power-Limits aller Karten merken; verstellt wird nur, wenn es bei jeder Karte geht
    $plStart = @{}; $plMin = 0.0; $limitAn = -not $OhneLimit
    foreach ($k in $karten) {
        $v = Smi-Query $k.Index 'power.limit,power.default_limit,power.min_limit'
        $jetzt = if ($v) { Num $v[0] } else { [double]::NaN }
        $plStart[$k.Index] = $jetzt
        if (-not $v -or [double]::IsNaN($jetzt) -or [double]::IsNaN((Num $v[2])) -or (Num $v[2]) -ge (Num $v[1])) { $limitAn = $false }
        elseif ((Num $v[2]) -gt $plMin) { $plMin = Num $v[2] }
    }
    $L = if ($limitAn -and $e.PlWahl) { [double]$e.PlWahl.Limit } elseif ($limitAn) { $e.PlDef } else { $plStart[$karten[0].Index] }
    if (-not $limitAn) { Write-Host (T 'tun.gem.nurMessung') -ForegroundColor DarkGray }

    # Messbereich so gross, dass CUDACyclone die ganze Stufe ueber rechnet
    $bits = 44
    if (-not [double]::IsNaN($e.Wahl.MKey) -and $e.Wahl.MKey -gt 0) {
        $bits = [int][math]::Ceiling([math]::Log($e.Wahl.MKey * 1e6 * ($GemeinsamSek + 120), 2))
    }
    $bits = [math]::Max(36, [math]::Min(48, $bits))
    $s0 = [Numerics.BigInteger]::Parse('04A0000000000000000', [Globalization.NumberStyles]::AllowHexSpecifier)
    $script:gemRange = $s0.ToString('X').TrimStart('0') + ':' + ($s0 + [Numerics.BigInteger]::Pow(2, $bits) - 1).ToString('X').TrimStart('0')

    if ($limitAn) { [P71T.Guard]::ResetArgs = (@($karten | ForEach-Object { F '-i {0} -pl {1:0}' $_.Index $plStart[$_.Index] }) -join '|') }
    try {
        Write-Host (T 'tun.gem.kopf') -ForegroundColor DarkGray
        $n = 0
        while ($true) {
            $s = Invoke-GemStufe $e $karten $L $limitAn
            if (-not $s) { $e.Hinweise += (T 'tun.gem.limitFehler' ([int]$L)); Write-Host "   $($e.Hinweise[-1])" -ForegroundColor Yellow; break }
            Show-GemStufe $s
            $e.Gemeinsam += $s
            $fehl = @($s.Karten | Where-Object { -not $_.Ok })
            if ($fehl.Count) { $e.Hinweise += (T 'tun.gem.abbruch' ([int]$L) $fehl[0].Index $fehl[0].Fehler); break }
            $heiss = @($s.Karten | Where-Object { $_.Befund })
            if ($heiss.Count -eq 0) {
                if ($limitAn) { $e.GemLimit = [int]$L }
                break
            }
            $namen = ($heiss | ForEach-Object { "GPU $($_.Index)" }) -join ', '
            if (-not $limitAn) { $e.Hinweise += (T 'tun.gem.drosseltOhneLimit' $namen); break }
            $neu = [int][math]::Round($L * $GemeinsamFaktor)
            if ($neu -lt $plMin) { $neu = [int][math]::Ceiling($plMin) }
            if ($neu -gt $L - 5 -or $n -ge $GemeinsamStufenMax) {
                $e.GemLimit = [int]$L
                $e.Hinweise += (T 'tun.gem.drosseltImmer' $namen ([int]$L))
                break
            }
            Write-Host (T 'tun.gem.naechsteStufe' $namen $neu) -ForegroundColor Yellow
            $L = $neu; $n++
        }
    } finally {
        if ($limitAn) { foreach ($k in $karten) { if (-not [double]::IsNaN($plStart[$k.Index])) { & $smi -i $k.Index -pl ([int]$plStart[$k.Index]) | Out-Null } } }
        [P71T.Guard]::ResetArgs = ''
    }
}

# ---------- Eintrag in puzzle-config.ps1 ----------
function Write-Profil($e) {
    $key = $e.Key
    $werte = Get-ProfilWerte $e
    $alt = ''
    $enc = New-Object Text.UTF8Encoding $false
    if (Test-Path $cfgFile) {
        $bytes = [IO.File]::ReadAllBytes($cfgFile)
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $enc = New-Object Text.UTF8Encoding $true }
        $alt = [IO.File]::ReadAllText($cfgFile)
    }
    $nl = if ($alt -match "`r`n" -or -not $alt) { "`r`n" } else { "`n" }
    $keyRx = [regex]::Escape($key)

    # Steht die Karte schon als Zeile im Profil, wird nur diese Zeile angepasst
    $zeilen = [regex]::Matches($alt, "(?m)^[ \t]*'$keyRx'[ \t]*=[ \t]*@\{[^}\r\n]*\}[^\r\n]*")
    $neu = $null
    if ($zeilen.Count -eq 1) {
        $z = $zeilen[0].Value
        foreach ($k in $werte.Keys) {
            $v = $werte[$k]
            $muster = "\b$k\s*=\s*('[^']*'|[0-9.]+)"
            if ($z -match $muster) { $z = [regex]::Replace($z, $muster, "$k = $v") }
            else {
                # Schluessel fehlt in der Zeile: vor der schliessenden Klammer anhaengen
                $mz = [regex]::Match($z, '^(?<kopf>.*?@\{)(?<inhalt>[^}]*)\}(?<rest>.*)$')
                $inh = $mz.Groups['inhalt'].Value.TrimEnd().TrimEnd(';').TrimEnd()
                $inh = if ($inh.Trim()) { "$inh; $k = $v " } else { " $k = $v " }
                $z = $mz.Groups['kopf'].Value + $inh + '}' + $mz.Groups['rest'].Value
            }
        }
        Write-Host (T 'tun.profil.bisher') -NoNewline -ForegroundColor DarkGray; Write-Host $zeilen[0].Value.Trim()
        Write-Host (T 'tun.profil.neu') -NoNewline -ForegroundColor DarkGray; Write-Host $z.Trim() -ForegroundColor Green
        if ($z -eq $zeilen[0].Value) { Write-Host (T 'tun.profil.stehtSchon') -ForegroundColor Green; return }
        $neu = $alt.Substring(0, $zeilen[0].Index) + $z + $alt.Substring($zeilen[0].Index + $zeilen[0].Length)
    } else {
        # Sonst ein eigener Block am Ende (ein frueherer Block fuer dieselbe Karte wird ersetzt)
        $datum = (Get-Date).ToString((T 'tun.datum'), $Kultur)
        $b = @((T 'tun.profil.blockKopf' $key $datum))
        $b += 'if (-not $GpuProfiles) { $GpuProfiles = [ordered]@{} }'
        $b += "if (-not `$GpuProfiles.Contains('$key')) { `$GpuProfiles['$key'] = @{} }"
        foreach ($k in $werte.Keys) { $b += "`$GpuProfiles['$key'].$k = $($werte[$k])" }
        $b += "# <<< tuning.ps1: $key"
        Write-Host (T 'tun.profil.anhaengen') -ForegroundColor DarkGray
        $b | ForEach-Object { Write-Host "     $_" -ForegroundColor Green }
        $rest = [regex]::Replace($alt, "(?ms)^# >>> tuning\.ps1: $keyRx \(.*?^# <<< tuning\.ps1: $keyRx[ \t]*(\r?\n)?", '')
        $rest = $rest.TrimEnd("`r", "`n")
        $neu = $(if ($rest) { $rest + $nl + $nl } else { '' }) + ($b -join $nl) + $nl
    }
    if (-not $Eintragen -and -not (Frage (T 'tun.profil.frage'))) { Write-Host (T 'tun.profil.nicht') -ForegroundColor DarkGray; return }

    $bak = Join-Path $Daten 'puzzle-config.ps1.bak'
    if (Test-Path $cfgFile) { Copy-Item $cfgFile $bak -Force }
    [IO.File]::WriteAllText($cfgFile, $neu, $enc)

    # Pruefen: laesst sich die Datei lesen und findet puzzle.ps1 fuer diese Karte die neuen Werte?
    $perr = $null
    [void][Management.Automation.Language.Parser]::ParseFile($cfgFile, [ref]$null, [ref]$perr)
    $fehler = ''
    if ($perr -and $perr.Count) { $fehler = (T 'tun.profil.syntax' $perr[0].Message) }
    else {
        try {
            $prof = & { $GpuProfiles = $null; . $cfgFile; $GpuProfiles }
            $treffer = $null
            if ($prof) { foreach ($k2 in @($prof.Keys)) { if ($e.Name -like "*$k2*") { $treffer = $k2; break } } }
            if (-not $treffer) { $fehler = (T 'tun.profil.nichtGefunden') }
            else {
                $p2 = $prof[$treffer]
                if ($treffer -ne $key) { $fehler = (T 'tun.profil.anderes' $treffer) }
                else { foreach ($k in $werte.Keys) { if ("$($p2[$k])" -ne $werte[$k].Trim("'")) { $fehler = (T 'tun.profil.kommtNicht' $k); break } } }
            }
        } catch { $fehler = $_.Exception.Message }
    }
    if ($fehler) {
        if (Test-Path $bak) { Copy-Item $bak $cfgFile -Force } else { [IO.File]::Delete($cfgFile) }
        Write-Host (T 'tun.profil.zurueck' $fehler) -ForegroundColor Red
    } else {
        Write-Host (T 'tun.profil.ok') -ForegroundColor Green
    }
}

# ================= Hauptteil =================
$gpus = @(& $smi --query-gpu=index,name --format=csv,noheader | ForEach-Object {
    $x = "$_" -split ',', 2
    if ($x.Count -eq 2 -and $x[0].Trim() -match '^\d+$') { [pscustomobject]@{ Index = [int]$x[0].Trim(); Name = $x[1].Trim() } }
})
if ($gpus.Count -eq 0) { Write-Host (T 'tun.start.keineGpu') -ForegroundColor Red; exit 1 }
if ($Device -eq 'all') {
    $ziele = @($gpus | Sort-Object Index | Group-Object Name | ForEach-Object { $_.Group[0] } | Sort-Object Index)
} elseif ($Device -match '^\d+$') {
    $ziele = @($gpus | Where-Object { $_.Index -eq [int]$Device })
    if ($ziele.Count -eq 0) { Write-Host (T 'tun.start.gpuFehlt' $Device) -ForegroundColor Red; exit 1 }
} else { Write-Host (T 'tun.start.ungueltig' $Device) -ForegroundColor Red; exit 1 }

$kopfTitel = "$AppName $AppVersion - Tuning"
try { $Host.UI.RawUI.WindowTitle = $kopfTitel } catch { }
Write-Host ''
Write-Host "   $kopfTitel" -ForegroundColor Cyan
Write-Host ('   ' + ('-' * $kopfTitel.Length)) -ForegroundColor Cyan
Write-Host ((T 'tun.start.gemessen') + (($ziele | ForEach-Object { "GPU $($_.Index) ($($_.Name))" }) -join ', '))
if ($Device -eq 'all' -and $gpus.Count -gt $ziele.Count) {
    if ($Einzeln) { Write-Host (T 'tun.start.einzeln') -ForegroundColor DarkGray }
    else { Write-Host (T 'tun.start.gemeinsam' ($GemeinsamSek / 60.0) ($GemeinsamSek * 3 / 60.0)) -ForegroundColor DarkGray }
}
if ($OhneLimit) { Write-Host (T 'tun.start.ohneLimit') -ForegroundColor DarkGray }
Write-Host (T 'tun.start.dauer1') -ForegroundColor DarkGray
Write-Host (T 'tun.start.dauer2') -ForegroundColor DarkGray
Write-Host (T 'tun.start.dauer3') -ForegroundColor DarkGray

$tmp = Join-Path $env:TEMP ("bitcrack-tuning-$PID")
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$ergebnisse = @()
$startZeit = Get-Date
try {
    foreach ($g in $ziele) {
        $e = Test-Karte $g
        $ergebnisse += $e
        $karten = @($gpus | Where-Object { $_.Name -eq $g.Name } | Sort-Object Index)
        if ($Device -ne 'all') { $karten = @($g) }
        if ($e.Ok -and -not $Einzeln -and ($karten.Count -gt 1 -or $Gemeinsam)) { Invoke-Gemeinsam $e $karten }
    }
} finally {
    [P71T.Guard]::RestoreConsoleMode()
    Get-Process cuBitCrack, CUDACyclone -ErrorAction SilentlyContinue | Where-Object { $_.Path -and ($_.Path -ieq $exe -or $_.Path -ieq $cycExe) -and $_.StartTime -ge $startZeit } |
        ForEach-Object { try { $_.Kill() } catch { } }
    Start-Sleep -Milliseconds 500
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------- Ergebnis ----------
$bericht = @()
$bericht += (T 'tun.bericht.kopf' $AppName $AppVersion $env:COMPUTERNAME (Get-Date) ([int]((Get-Date) - $startZeit).TotalMinutes))
foreach ($e in $ergebnisse) {
    Write-Host ''
    Write-Host (T 'tun.erg.titel' $e.Index $e.Name) -ForegroundColor Cyan
    $bericht += ''
    $bericht += (T 'tun.bericht.gpu' $e.Index $e.Name $e.Treiber)
    foreach ($r in @($e.Reihe) + @($e.Leistung | Select-Object -Skip 1)) {
        if ($r.Ok) { $bericht += F '  {0,-22} {1,5:N0} W  {2,7:N0} MKey/s  {3,5:N0} W  {4,5:N2} MKey/J  {5,3:N0} C  {6,6:N0} MB VRAM' $r.Tuning $r.Limit $r.MKey $r.Watt $r.Eff $r.Temp $r.Vram }
        else       { $bericht += T 'tun.bericht.abgebrochen' $r.Tuning $r.Limit $r.Fehler }
    }
    foreach ($h in $e.Hinweise) { Write-Host "   $h" -ForegroundColor DarkGray; $bericht += "  $h" }
    if (-not $e.Ok) {
        Write-Host (T 'tun.erg.keins' $e.Grund) -ForegroundColor Red
        $bericht += (T 'tun.bericht.keins' $e.Grund)
        continue
    }
    $w = $e.Wahl
    Write-Host (T 'tun.erg.tuning' $w.Tuning $w.MKey $w.Vram) -ForegroundColor Green
    $bericht += T 'tun.bericht.tuning' $w.Tuning $w.MKey
    $preis = $PricePerKwh
    if ($GpuProfiles) { foreach ($k2 in @($GpuProfiles.Keys)) { if ($e.Name -like "*$k2*") { if (@($GpuProfiles[$k2].Keys) -contains 'PricePerKwh') { $preis = $GpuProfiles[$k2]['PricePerKwh'] }; break } } }
    $lauf = if ($e.PlWahl) { $e.PlWahl } else { $w }
    if ($e.PlWahl) {
        $p = $e.PlWahl
        Write-Host (T 'tun.erg.limit' $p.Limit $p.MKey $p.Watt $p.Eff) -ForegroundColor Green
        $bericht += T 'tun.bericht.limit' $p.Limit $p.MKey $p.Watt $p.Eff
        if ($p.Limit -lt $e.PlDef) {
            Write-Host (T 'tun.erg.anteil' ($p.MKey / $w.MKey * 100) ($p.Watt / $w.Watt * 100)) -ForegroundColor DarkGray
        }
    }
    if (@($e.Gemeinsam).Count) {
        $bericht += (T 'tun.bericht.gem') + ($e.GemKarten -join ' + ') + ':'
        foreach ($s in $e.Gemeinsam) {
            foreach ($r in $s.Karten) {
                if ($r.Ok) { $bericht += T 'tun.bericht.gemZeile' $r.Index $r.Limit $r.MKey $r.Watt $r.Eff $r.Temp $r.Fan $(if ($r.Befund) { (T 'tun.bericht.drosselt' $r.Befund) } else { 'ok' }) }
                else       { $bericht += T 'tun.bericht.gemAbgebrochen' $r.Index $r.Limit $r.Fehler }
            }
        }
        $gs = @($e.Gemeinsam | Where-Object { $e.GemLimit -and [int]$_.Limit -eq [int]$e.GemLimit }) | Select-Object -Last 1
        if ($gs) {
            $ok = @($gs.Karten | Where-Object { $_.Ok })
            $sm = ($ok | Measure-Object MKey -Sum).Sum; $sw = ($ok | Measure-Object Watt -Sum).Sum
            $alle = @($gs.Karten | Where-Object { $_.Befund }).Count -eq 0
            if ($e.PlWahl -and $e.GemLimit -lt [int]$e.PlWahl.Limit) {
                Write-Host (T 'tun.erg.gemStatt' $e.GemLimit $e.PlWahl.Limit) -ForegroundColor Yellow
                $bericht += T 'tun.bericht.gemStatt' $e.GemLimit $e.PlWahl.Limit
            } else {
                Write-Host (T 'tun.erg.gem' $e.GemLimit $(if ($alle) { (T 'tun.erg.keineDrosselt') } else { (T 'tun.erg.drosseltNoch') })) -ForegroundColor $(if ($alle) { 'Green' } else { 'Yellow' })
                $bericht += T 'tun.bericht.gem2' $e.GemLimit $(if ($alle) { (T 'tun.bericht.keineDrosselung') } else { (T 'tun.bericht.drosseltNoch') })
            }
            Write-Host (T 'tun.erg.zusammen' $sm $sw ($sm / $sw)) -ForegroundColor DarkGray
            $bericht += T 'tun.bericht.zusammen' $sm $sw
            $lauf = [pscustomobject]@{ Watt = $sw; Wer = (T 'tun.erg.alleKarten') }
        }
    }
    if (-not [double]::IsNaN($lauf.Watt)) {
        $kwh = $lauf.Watt * 24 / 1000
        Write-Host (T 'tun.erg.strom' $kwh $preis ($kwh * $preis) $(if ($lauf.Wer) { $lauf.Wer } else { (T 'tun.erg.nurKarte') })) -ForegroundColor DarkGray
    }
    $pw = Get-ProfilWerte $e
    $zeile = "'$($e.Key)' = @{ " + (@($pw.Keys | ForEach-Object { "$_ = $($pw[$_])" }) -join '; ') + ' }'
    $bericht += (T 'tun.bericht.profil' $zeile)
    Write-Host ''
    Write-Host (T 'tun.erg.zeileFuer') -ForegroundColor DarkGray
    Write-Host "     $zeile" -ForegroundColor White
    Write-Host ''
    Write-Profil $e
}
$berichtDatei = Join-Path $Daten "tuning-$env:COMPUTERNAME.txt"
try {
    Add-Content -Path $berichtDatei -Value (@('') + $bericht) -Encoding ASCII
    Write-Host ''
    Write-Host (T 'tun.bericht.angehaengt' (Split-Path $berichtDatei -Leaf)) -ForegroundColor DarkGray
} catch { }
Write-Host ''
if ($interaktiv) { try { [void](Read-Host (T 'tun.enter')) } catch { } }
