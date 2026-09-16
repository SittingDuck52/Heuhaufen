# sprache.ps1 - Texte in der Sprache des Benutzers (Deutsch oder Englisch).
# Geladen per Dot-Sourcing von puzzle.ps1, tuning.ps1, web.ps1 und paket.ps1 - nach der Config, damit $Sprache wirkt.
#
# $Sprache = 'de' oder 'en' legt die Sprache fest; leer = Windows-Anzeigesprache (Deutsch bei deutschem Windows,
# sonst Englisch). Die Texte stehen in sprache\de.psd1 und sprache\en.psd1: Schluessel = Text, {0} {1} ... sind
# Werte wie bei -f, Zahlen und Datum im Format der Sprache ($Kultur: de-DE bzw. en-US).
# Fehlt ein Text in der gewaehlten Sprache, gilt der deutsche; fehlt er ganz, erscheint [schluessel].

if (-not $Sprache) {
    $Sprache = try { if ((Get-UICulture).TwoLetterISOLanguageName -eq 'de') { 'de' } else { 'en' } } catch { 'de' }
}
$Sprache = "$Sprache".Trim().ToLower()
if ($Sprache -notin 'de', 'en') { $Sprache = 'en' }
$Kultur = [Globalization.CultureInfo]$(if ($Sprache -eq 'de') { 'de-DE' } else { 'en-US' })

function Import-Texte([string]$kuerzel) {
    $p = Join-Path $PSScriptRoot "sprache\$kuerzel.psd1"
    try { Import-PowerShellDataFile -Path $p } catch { @{} }
}
$TexteDe = Import-Texte 'de'
$Texte = if ($Sprache -eq 'de') { $TexteDe } else { Import-Texte $Sprache }

# T 'schluessel' [wert0] [wert1] ... - Text holen und Werte einsetzen
function T([string]$schluessel) {
    $t = $Texte[$schluessel]
    if ($null -eq $t) { $t = $TexteDe[$schluessel] }
    if ($null -eq $t) { return "[$schluessel]" }
    if ($args.Count -gt 0) { return [string]::Format($Kultur, $t, [object[]]$args) }
    $t
}

# Alle Texte, deren Schluessel mit $praefix beginnt, als JSON-Objekt (fuer die Webseite), deutscher Rueckfall
function Get-TexteJson([string]$praefix) {
    $h = [ordered]@{}
    foreach ($k in @($TexteDe.Keys | Where-Object { $_ -like "$praefix*" } | Sort-Object)) { $h[$k] = $TexteDe[$k] }
    foreach ($k in @($Texte.Keys | Where-Object { $_ -like "$praefix*" } | Sort-Object)) { $h[$k] = $Texte[$k] }
    $h | ConvertTo-Json -Compress
}
