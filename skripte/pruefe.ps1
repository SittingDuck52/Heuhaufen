# pruefe.ps1 - prueft eine found*.txt OFFLINE: Schluessel -> Public Key -> Adresse, gibt WIF aus
# (checks a found*.txt OFFLINE: key -> public key -> address, prints the WIF)
param([string]$File, [string]$Hex, [string]$Sprache)   # ohne Angabe: erste found*.txt in daten\ (sonst im aktuellen Ordner)
# Sprache: -Sprache de|en, sonst Windows-Anzeigesprache. Texte stehen hier im Skript, damit es ohne weitere Dateien laeuft.
if (-not $Sprache) { try { $Sprache = if ((Get-UICulture).TwoLetterISOLanguageName -eq 'de') { 'de' } else { 'en' } } catch { $Sprache = 'de' } }
$deutsch = ($Sprache -eq 'de')
function Txt([string]$de, [string]$en) { if ($deutsch) { $de } else { $en } }

Add-Type -AssemblyName System.Numerics
$BI = [System.Numerics.BigInteger]
function HexBI([string]$h) { $BI::Parse('0' + $h, [Globalization.NumberStyles]::AllowHexSpecifier) }
function Mod($a, $m) { $r = $BI::Remainder($a, $m); if ($r.Sign -lt 0) { $r += $m }; $r }
function Bytes32($n) {
    $b = $n.ToByteArray(); [Array]::Reverse($b)
    $b = @($b | Select-Object -Last ([Math]::Min($b.Length, 32)))
    [byte[]](@([byte[]]::new(32 - $b.Count)) + $b)
}
function Sha256([byte[]]$d) { [Security.Cryptography.SHA256]::Create().ComputeHash($d) }
function Ripemd160([byte[]]$d) { (New-Object Security.Cryptography.RIPEMD160Managed).ComputeHash($d) }
function Base58Check([byte[]]$payload) {
    $chk  = (Sha256 (Sha256 $payload))[0..3]
    $full = [byte[]]($payload + $chk)
    $alph = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'
    $n = HexBI (($full | ForEach-Object { $_.ToString('x2') }) -join '')
    $s = ''
    while ($n.Sign -gt 0) { $r = $BI::Zero; $n = $BI::DivRem($n, $BI::new(58), [ref]$r); $s = $alph[[int]$r] + $s }
    foreach ($b in $full) { if ($b -eq 0) { $s = '1' + $s } else { break } }
    $s
}

# secp256k1
$P  = HexBI 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F'
$N  = HexBI 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141'
$Gx = HexBI '79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798'
$Gy = HexBI '483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8'
function Inv($a) { $BI::ModPow((Mod $a $P), $P - $BI::new(2), $P) }
function PAdd($p1, $p2) {
    if ($null -eq $p1) { return $p2 }; if ($null -eq $p2) { return $p1 }
    if ($p1[0] -eq $p2[0]) {
        if ((Mod ($p1[1] + $p2[1]) $P).IsZero) { return $null }
        $l = Mod ($p1[0] * $p1[0] * 3 * (Inv ($p1[1] * 2))) $P
    } else {
        $l = Mod (($p2[1] - $p1[1]) * (Inv ($p2[0] - $p1[0]))) $P
    }
    $x = Mod ($l * $l - $p1[0] - $p2[0]) $P
    $y = Mod ($l * ($p1[0] - $x) - $p1[1]) $P
    ,@($x, $y)
}
function PMul($k) {
    $r = $null; $q = @($Gx, $Gy)
    while ($k.Sign -gt 0) {
        if (-not $k.IsEven) { $r = PAdd $r $q }
        $q = PAdd $q $q
        $k = $BI::Divide($k, $BI::new(2))
    }
    $r
}

# --- Eingabe ---
$addrFile = $null; $pubFile = $null
if (-not $Hex) {
    if (-not $File) {
        $such = @('found*.txt')
        if ($PSScriptRoot) { $such = @(Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'daten') 'found*.txt') + $such }
        $f = Get-ChildItem $such -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $f) { Write-Host (Txt 'Keine found*.txt gefunden' 'No found*.txt found') -ForegroundColor Red; exit 1 }
        $File = $f.FullName
        Write-Host ((Txt '  Datei: ' '  File: ') + $f.Name)
    }
    $parts = ((Get-Content $File | Where-Object { $_.Trim() } | Select-Object -First 1).Trim()) -split '\s+'
    $addrFile = $parts[0]; $Hex = $parts[1]; if ($parts.Count -gt 2) { $pubFile = $parts[2] }
}
$k = HexBI $Hex
if ($k.Sign -le 0 -or $k -ge $N) { Write-Host (Txt 'Ungueltiger Schluessel' 'Invalid key') -ForegroundColor Red; exit 1 }

$pt   = PMul $k
$pub  = [byte[]](@([byte](2 + [int]$BI::Remainder($pt[1], $BI::new(2)))) + (Bytes32 $pt[0]))
$h160 = Ripemd160 (Sha256 $pub)
$addr = Base58Check ([byte[]](@([byte]0) + $h160))
$wif  = Base58Check ([byte[]](@([byte]0x80) + (Bytes32 $k) + @([byte]1)))
$pubHex = ($pub | ForEach-Object { $_.ToString('X2') }) -join ''

Write-Host ''
Write-Host ((Txt '  Privater Schluessel (hex) : ' '  Private key (hex)         : ') + $k.ToString('X').TrimStart('0'))
Write-Host ((Txt '  Public Key (komprimiert)  : ' '  Public key (compressed)   : ') + $pubHex)
Write-Host ((Txt '  Berechnete Adresse        : ' '  Computed address          : ') + $addr)
if ($addrFile) {
    $ok = $addr -eq $addrFile
    Write-Host ((Txt '  Adresse in der Datei      : ' '  Address in the file       : ') + $addrFile)
    Write-Host ((Txt '  Uebereinstimmung          : ' '  Match                     : ') + $(if ($ok) { Txt 'JA' 'YES' } else { Txt 'NEIN' 'NO' })) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
}
Write-Host ((Txt '  WIF (komprimiert)         : ' '  WIF (compressed)          : ') + $wif) -ForegroundColor Yellow
Write-Host ''
