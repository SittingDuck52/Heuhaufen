# web.ps1 - zeigt den Stand aller Suchen im Ordner als Webseite im lokalen Netz.
# Normalerweise braucht man das Skript nicht: puzzle.ps1 bedient die Seite selbst mit (Taste W).
# Hier laeuft sie eigenstaendig, etwa um sie ohne laufende Suche herzuzeigen.
# Gelesen werden nur status*.json und verlauf*.csv; geschrieben wird nichts.
# Ein Schluessel steht nie in diesen Dateien und damit auch nie auf der Seite.
param(
    [int]$Port      = 8080,
    [string]$Bind   = '+',     # '+' = im ganzen Netz erreichbar (Adminrechte), 'localhost' = nur hier
    [string]$Ordner = '',      # Standard: daten\ im Heuhaufen-Ordner; auch eine Freigabe ist moeglich
    [switch]$Firewall          # legt die Firewall-Regel fuer den Port an und beendet sich wieder
)

$ErrorActionPreference = 'Stop'
$Daten = Join-Path (Split-Path $PSScriptRoot -Parent) 'daten'
if (-not $Ordner) { $Ordner = $Daten }
$win = $env:SystemRoot
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Sprache: $Sprache aus puzzle-config.ps1 (nur diese Zeile, die Config wird nicht geladen), sonst Windows-Sprache
$Sprache = ''
try {
    $cfgDatei = Join-Path (Split-Path $PSScriptRoot -Parent) 'puzzle-config.ps1'
    $m = Select-String -Path $cfgDatei -Pattern "^\s*\`$Sprache\s*=\s*'([A-Za-z]*)'" -ErrorAction SilentlyContinue | Select-Object -Last 1
    if ($m) { $Sprache = $m.Matches[0].Groups[1].Value }
} catch { }
$sprDatei = Join-Path $PSScriptRoot 'sprache.ps1'
if (Test-Path $sprDatei) { . $sprDatei } else { function T([string]$k) { "[$k]" } }

# Im Netz erreichbar sein und die Firewall-Regel anlegen geht nur als Administrator
if ((-not $isAdmin) -and ($Firewall -or $Bind -eq '+')) {
    $a = "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$PSCommandPath`" -Port $Port -Bind $Bind"
    if ($Ordner -ne $Daten) { $a += " -Ordner `"$Ordner`"" }
    if ($Firewall) { $a += ' -Firewall' }
    Start-Process "$win\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList $a
    exit
}

if ($Firewall) {
    # Normalerweise legt puzzle.ps1 die Regel beim Start selbst an; hier von Hand, gleiche Regel.
    # Bewusst nur fuer private Netze: die Seite hat kein Passwort.
    $name = "BitCrack-Web $Port"
    & "$win\System32\netsh.exe" advfirewall firewall delete rule name="$name" | Out-Null
    & "$win\System32\netsh.exe" advfirewall firewall add rule name="$name" dir=in action=allow protocol=TCP localport=$Port profile=private | Out-Null
    Write-Host ('   ' + (T 'webps.firewallAngelegt' $name)) -ForegroundColor Green
    try {
        $pro = @(Get-NetConnectionProfile -ErrorAction SilentlyContinue)
        if ($pro.Count -gt 0 -and -not ($pro | Where-Object { $_.NetworkCategory -ne 'Public' })) {
            Write-Host ('   ' + (T 'webps.oeffentlich')) -ForegroundColor Yellow
            Write-Host ('   ' + (T 'webps.aufPrivat')) -ForegroundColor DarkGray
        }
    } catch { }
    [void](Read-Host ('   ' + (T 'webps.enter')))
    exit
}

# Seite und Datenfunktionen (dieselbe Datei benutzt puzzle.ps1)
$WebOrdner = $Ordner
$inhalt = Join-Path $PSScriptRoot 'web-inhalt.ps1'
if (-not (Test-Path $inhalt)) {
    Write-Host ('   ' + (T 'webps.inhaltFehlt')) -ForegroundColor Red
    [void](Read-Host ('   ' + (T 'webps.enter'))); exit 1
}
. $inhalt
try { $Host.UI.RawUI.WindowTitle = (T 'webps.titel' $AppName $AppVersion) } catch { }

# ---------- Server ----------
$listener = New-Object Net.HttpListener
$prefix = "http://${Bind}:$Port/"
$listener.Prefixes.Add($prefix)
try { $listener.Start() }
catch {
    $m = $_.Exception.Message
    Write-Host ('   ' + (T 'webps.portFehler' $Port $m)) -ForegroundColor Red
    Write-Host ('   ' + (T 'webps.portGrund')) -ForegroundColor Yellow
    try {
        Add-Content -Encoding utf8 -Path (Join-Path $Daten 'web-fehler.log') `
            -Value ('{0:yyyy-MM-dd HH:mm:ss}  web.ps1  Prefix {1} ging nicht auf: {2}' -f (Get-Date), $prefix, $m)
    } catch { }
    [void](Read-Host ('   ' + (T 'webps.enter'))); exit 1
}

$ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
    ForEach-Object { $_.IPAddress })
Write-Host ''
Write-Host ('   ' + (T 'webps.laeuft' $AppName $AppVersion)) -ForegroundColor Cyan
Write-Host ('   ' + (T 'webps.ordner' $Ordner)) -ForegroundColor DarkGray
Write-Host ('   ' + (T 'webps.hier' "http://localhost:$Port/")) -ForegroundColor Gray
foreach ($ip in $ips) { Write-Host ('   ' + (T 'webps.imNetz' "http://${ip}:$Port/" "http://$env:COMPUTERNAME`:$Port/")) -ForegroundColor Green }
if ($Bind -ne '+') { Write-Host ('   ' + (T 'webps.nurHier')) -ForegroundColor Yellow }
Write-Host ('   ' + (T 'webps.firewallTipp')) -ForegroundColor DarkGray
Write-Host ('   ' + (T 'webps.beenden')) -ForegroundColor DarkGray
Write-Host ''

$anfragen = 0
try {
    while ($listener.IsListening) {
        # Nicht blockierend warten, damit Q und Strg+C jederzeit greifen
        $task = $listener.GetContextAsync()
        $ende = $false
        while (-not $task.AsyncWaitHandle.WaitOne(200)) {
            try { if ([Console]::KeyAvailable -and "$(([Console]::ReadKey($true)).Key)" -eq 'Q') { $ende = $true; break } } catch { }
        }
        if ($ende) { break }
        $ctx = $task.GetAwaiter().GetResult()
        $anfragen++
        $pfad = Invoke-WebAnfrage $ctx
        Write-Host ("`r   " + (T 'webps.anfragen' $anfragen $pfad $ctx.Request.RemoteEndPoint.Address (Get-Date -Format HH:mm:ss)) + '      ') -NoNewline -ForegroundColor DarkGray
    }
} catch { }
finally {
    if ($listener.IsListening) { $listener.Stop() }
    $listener.Close()
    Write-Host ''
    Write-Host ('   ' + (T 'webps.beendet')) -ForegroundColor Cyan
}
