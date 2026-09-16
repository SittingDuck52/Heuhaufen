# Notfallplan: Treffer bei einem Bitcoin-Puzzle

> **Stand: 11.09.2026.** Die Adressen unten gelten für **Puzzle 71** – bei einem anderen Puzzle
> die Adresse aus dem Dashboard bzw. der `found`-Datei verwenden.
> Dienste und Empfehlungen können sich ändern.
> Vor dem Handeln kurz prüfen, ob die genannten Wege noch aktuell sind.

---

## 0. Die wichtigste Regel

**Die Transaktion NIEMALS normal senden.** Nicht über „Senden/Broadcast“ in einer Wallet,
nicht über „Push TX“ bei einem Block-Explorer, nicht über die eigene Node.

**Warum:** Beim Senden wird der Public Key sichtbar. Weil der Schlüssel von Puzzle 71 nur
71 Bit hat, berechnen Bots damit den privaten Schlüssel in Minuten (Pollard's Kangaroo) und
ersetzen die Transaktion per Replace-by-Fee durch ihre eigene.

- **Puzzle 66 (2024) und 69 (2025):** öffentlich gesendet → Prämie von Bots gestohlen.
- **Puzzle 67 und 68 (2025):** am öffentlichen Mempool vorbei direkt an einen Miner übergeben → Prämie erhalten.

---

## 1. Sofort – die ersten Minuten

- [ ] **Ruhe bewahren.** Es gibt keinen Zeitdruck, solange der Schlüssel nicht öffentlich ist.
- [ ] **Niemandem etwas erzählen**, nichts posten, keine Screenshots, den Schlüssel nicht in
      Chats, KI-Assistenten, E-Mails oder Cloud-Notizen einfügen.
- [ ] Das Dashboard hat BitCrack bereits gestoppt. Der Treffer steht im Unterordner `daten` in
      `foundNN-RECHNER-gpuX.txt` (NN = Puzzle, X = GPU), z. B. `daten\found71-MEINPC-gpu0.txt`:
      `Adresse  PrivaterSchlüssel(hex)  PublicKey`
- [ ] **Offline sichern:** die `found`-Datei auf einen USB-Stick kopieren und den privaten
      Schlüssel zusätzlich von Hand auf Papier notieren (zweimal gegenlesen).
- [ ] **Nicht** in OneDrive/Google Drive/Dropbox-synchronisierte Ordner legen.
- [ ] Den PC bis zum Abschluss nur noch für diesen Ablauf nutzen, keine neue Software
      außer Electrum installieren.

---

## 2. Treffer prüfen

- [ ] **Offline rechnen:** Netzwerkkabel ziehen bzw. WLAN aus, dann im BitCrack-Ordner:

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\skripte\pruefe.ps1
  ```

  Ohne Angabe nimmt es die erste `found*.txt` aus `daten`.

  Erwartung: `Uebereinstimmung: JA`, Adresse `1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU` (bei Puzzle 71;
  bei anderen Puzzles die Adresse aus der Kopfzeile des Dashboards).
  Die ausgegebene **WIF** (beginnt mit `K` oder `L`) wird für Electrum gebraucht.

- [ ] **Guthaben prüfen** (z. B. vom Handy, das Ansehen der Adresse ist unkritisch):
  <https://mempool.space/address/1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU>
  Es darf **keine ausgehende** Transaktion geben – auch keine unbestätigte.

---

## 3. Ziel-Wallet vorbereiten

- [ ] Eine **neue, unbenutzte Empfangsadresse** in einer Wallet erzeugen, deren Seed nur ich
      kenne – idealerweise eine Hardware-Wallet.
- [ ] Adresse auf dem Display der Hardware-Wallet mit der kopierten Adresse vergleichen
      (Schutz gegen Zwischenablage-Malware).
- [ ] **Keine Börsenadresse** als erstes Ziel verwenden: große Eingänge aus einer bekannten
      Puzzle-Adresse können dort Rückfragen oder Sperren auslösen.

---

## 4. Transaktion bauen und signieren – ohne zu senden

Werkzeug: **Electrum** (nur von <https://electrum.org>). Menünamen können je nach Version abweichen.

### 4a. Unsignierte Transaktion (Wallet ohne Schlüssel, online)

1. Electrum starten → neue Wallet → Typ **„Bitcoin-Adressen oder private Schlüssel importieren“**
2. **Nur die Adresse** `1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU` einfügen → Watch-only-Wallet,
   das Guthaben wird angezeigt.
3. Senden an die eigene Adresse aus Schritt 3, Betrag **„Max“**.
4. **Gebühr großzügig** wählen (deutlich über der aktuellen Empfehlung von mempool.space) –
   gegenüber 7,1 BTC fällt sie kaum ins Gewicht und erhöht die Chance auf schnelle Aufnahme.
5. **Nicht** „Senden/Broadcast“ – stattdessen **Vorschau/Erweitert → Exportieren → In Datei
   speichern** (unsignierte Transaktion / PSBT).

### 4b. Signieren (Wallet mit Schlüssel, offline)

1. **Netzwerk trennen.** Electrum im Offline-Modus starten:

   ```
   electrum.exe --offline
   ```

2. Neue Wallet → **„Bitcoin-Adressen oder private Schlüssel importieren“** → die **WIF** aus
   `pruefe.ps1` einfügen. Angezeigte Adresse muss `1PWo3J…` sein.
3. **Werkzeuge → Transaktion laden → Aus Datei** → PSBT aus 4a laden.
4. Kontrollieren: **Empfänger = eigene Adresse**, Betrag und Gebühr plausibel.
5. **Signieren** → **Exportieren** als **Hex** (in Datei speichern oder kopieren).
   **Nicht** „Senden“ drücken.
6. Electrum schließen.

---

## 5. Privat an einen Miner übergeben

- [ ] **MARA Slipstream:** <https://slipstream.mara.com>
      Die signierte Transaktion (Hex) dort einreichen. Sie geht direkt an MARA Pool, nicht in
      den öffentlichen Mempool. Laut Berichten vom August 2026 kostenlos, nur die normale
      Transaktionsgebühr fällt an.
- [ ] **Geduld:** Aufgenommen wird sie erst, wenn MARA Pool einen Block findet – das kann
      Stunden dauern. **Nicht** zusätzlich öffentlich senden, „um es zu beschleunigen“.
- [ ] Beobachten auf mempool.space (Adresse aus Schritt 2). Sobald die Transaktion in einem
      Block steht, ist sie sicher.
- [ ] **Falls Slipstream nicht verfügbar ist:** vorher recherchieren, welche privaten
      Einreichungswege aktuell genutzt werden (Bitcointalk-Thread zum Puzzle,
      privatekeys.pw). **Ungeeignet** sind Beschleuniger, die eine bereits gesendete
      Transaktion bzw. TXID verlangen.
- [ ] Restrisiko: Der Pool-Betreiber sieht die Transaktion. Einen besseren Weg gibt es derzeit
      nicht.

---

## 6. Nach der Bestätigung

- [ ] **6 Bestätigungen** abwarten.
- [ ] Die Puzzle-Adresse ist ab jetzt verbrannt – **nie wieder** etwas dorthin senden.
- [ ] Weiterhin **Stillschweigen**: Wer von einem Gewinn weiß, wird Ziel von Phishing,
      Betrug und schlimmerem. Seed der Ziel-Wallet sicher und offline aufbewahren.
- [ ] **Steuern:** Die steuerliche Behandlung eines solchen Fundes ist nicht eindeutig.
      Vor jedem Verkauf einen **Steuerberater mit Krypto-Erfahrung** fragen.
- [ ] **Dokumentieren** (für Finanzamt und Börsen-Nachweise zur Mittelherkunft):
  - aus `daten`: `found71-RECHNER-gpuX.txt` mit Datum, `bitcrack71-RECHNER-gpuX.log` / `.err`,
    `share71-RECHNER-gpuX.txt`
  - TXID der Auszahlung, Datum und EUR-Kurs zum Zeitpunkt des Eingangs
  - diese Checkliste mit Notizen, wann was passiert ist

---

## 7. Jetzt schon vorbereiten (Trockenübung)

- [ ] `pruefe.ps1` testen – mit dem gelösten Puzzle 20:

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\skripte\pruefe.ps1 -Hex D2C55
  ```

  Erwartet: Adresse `1HsMJxNiV7TLxmoF6uJNkydxPFDog4NQum`,
  WIF `KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rHfuE2Tg4nJW`

- [ ] Electrum installieren und den Ablauf aus Schritt 4 einmal mit einem **kleinen eigenen
      Betrag** durchspielen (Watch-only → PSBT → offline signieren → Hex exportieren).
      Bei der Übung darf die Transaktion normal gesendet werden.
- [ ] Prüfen, dass der BitCrack-Ordner **nicht** in einem Cloud-Ordner liegt.
- [ ] Ziel-Wallet (Hardware-Wallet) einsatzbereit halten.
- [ ] Links als Lesezeichen: mempool.space-Adresse, slipstream.mara.com, privatekeys.pw

---

## Anhang: pruefe.ps1

Liegt als eigene Datei im Unterordner `skripte`. Ohne Parameter nimmt es die erste `found*.txt` aus `daten` (sonst aus dem aktuellen Ordner). Falls sie fehlt: Inhalt als `skripte\pruefe.ps1` speichern.
Das Skript arbeitet komplett offline (Windows PowerShell 5.1). `-Sprache de` zeigt die Ausgabe auf Deutsch, `-Sprache en` auf Englisch; ohne Angabe entscheidet die Windows-Anzeigesprache.

```powershell
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
```
