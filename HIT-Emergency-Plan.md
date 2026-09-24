# Emergency plan: a hit on a Bitcoin puzzle

> **As of 11 September 2026.** The addresses below apply to **puzzle 71** – for a different puzzle
> use the address from the dashboard or from the `found` file.
> Services and recommendations can change.
> Before acting, briefly check whether the routes named here are still current.

---

## 0. The most important rule

**NEVER broadcast the transaction the normal way.** Not via "Send/Broadcast" in a wallet,
not via "Push TX" on a block explorer, not via your own node.

**Why:** Sending makes the public key visible. Because the key of puzzle 71 has only
71 bits, bots use it to compute the private key within minutes (Pollard's kangaroo) and
replace the transaction with their own via replace-by-fee.

- **Puzzle 66 (2024) and 69 (2025):** broadcast publicly → reward stolen by bots.
- **Puzzle 67 and 68 (2025):** handed directly to a miner, bypassing the public mempool → reward received.

**Do I have to switch off RBF (replace-by-fee) in the wallet?** No – not on this route. Guides on the web
(btcpuzzle.info for one) recommend it and suggest the old Electrum 4.3.4, because newer versions no longer
offer the switch. It only helps in a case this plan rules out anyway: the transaction reaching the public
mempool. Handed straight to a miner it is never seen by a bot, and once in a block it is final. On top of
that, Bitcoin Core 28 (late 2024) turned on "full RBF" by default, so nodes replace transactions regardless
of the flag – and whoever has the public key has the key itself and needs no RBF to build a competing
transaction. Using a wallet version over two years old, with unpatched holes, would be the bigger risk.
**So: take the current Electrum from electrum.org and simply do not broadcast.**

---

## 1. Immediately – the first minutes

- [ ] **Stay calm.** There is no time pressure as long as the key is not public.
- [ ] **Tell nobody**, post nothing, take no screenshots, do not paste the key into
      chats, AI assistants, e-mails or cloud notes.
- [ ] The dashboard has already stopped the search program. The hit is in the subfolder `daten` in
      `foundNN-COMPUTER-gpuX.txt` (NN = puzzle, X = GPU), e.g. `daten\found71-MYPC-gpu0.txt`:
      `Address  PrivateKey(hex)  PublicKey`
- [ ] **Back it up offline:** copy the `found` file to a USB stick and additionally write the private
      key down on paper by hand (check it twice).
- [ ] Do **not** put it into folders synchronised with OneDrive/Google Drive/Dropbox.
- [ ] Until this is finished, use the PC only for this procedure and install no new software
      apart from Electrum.

---

## 2. Verify the hit

- [ ] **Compute offline:** unplug the network cable or turn off Wi-Fi, then in the Heuhaufen folder:

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\skripte\pruefe.ps1 -Sprache en
  ```

  Without further arguments it takes the first `found*.txt` from `daten`.

  Expected: `Match: YES`, address `1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU` (for puzzle 71;
  for other puzzles the address from the header line of the dashboard).
  The printed **WIF** (starts with `K` or `L`) is needed for Electrum.

- [ ] **Check the balance** (e.g. from your phone – looking at the address is harmless):
  <https://mempool.space/address/1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU>
  There must be **no outgoing** transaction – not even an unconfirmed one.

---

## 3. Prepare the destination wallet

- [ ] Create a **new, unused receiving address** in a wallet whose seed only you
      know – ideally a hardware wallet.
- [ ] Compare the address on the hardware wallet's display with the copied address
      (protection against clipboard malware).
- [ ] Do **not** use an exchange address as the first destination: large deposits from a well-known
      puzzle address can trigger questions or a freeze there.

---

## 4. Build and sign the transaction – without sending it

Tool: **Electrum** (only from <https://electrum.org>). Menu names may differ between versions.

### 4a. Unsigned transaction (wallet without the key, online)

1. Start Electrum → new wallet → type **"Import Bitcoin addresses or private keys"**
2. Paste **only the address** `1PWo3JeB9jrGwfHDNpdGK54CRas7fsVzXU` → watch-only wallet,
   the balance is shown.

   **This wallet is not just for looking: it builds the transaction.** It knows the amounts sitting on
   the address and the current fees, and assembles the complete transaction from them – it just cannot
   sign it, because it has no key. That is the whole point: the machine on the network never sees the
   key, the machine with the key never goes online. After the export in step 5 it is no longer needed
   (it holds no key and is harmless; you can use it later to see whether the payment arrived).
3. The **recipient** is your own address from step 3. For the **amount** press the **"Max"** button
   next to the amount field – the address is emptied completely, so there is no change output.
   (**"Max" refers to the amount here, not to the fee.**) Then click **"Pay"** – a **second window**
   opens; nothing is sent yet.
4. **The fee is set in that window, not before.** Electrum offers three tabs – *ETA*, *Fee rate* and
   *Mempool*. Use **Fee rate** (sat/vByte): the other two are estimates that move with the mempool,
   this is the only one where you know exactly what is set. Look up the current "High Priority" rate
   on <https://mempool.space> and enter **two to three times** that – pulling the slider to its
   maximum is fine. The transaction has one input and one output (about 190 vBytes), so at
   250 sat/vByte it costs roughly 47,500 satoshi – half a per mille of 7.1 BTC. The fee is fixed once
   you export; changing it later means redoing 4a and 4b.

   **Why so high when Slipstream asks for so little?** Slipstream states (as of 18.09.2026) a minimum
   submission rate of **1 sat/vByte**, current minable rate 2 sat/vByte – there the transaction does
   not compete in the mempool, MARA puts it straight into a block. The high fee is the **insurance for
   the case it becomes public after all**: if Slipstream is down, refuses it, or you end up having to
   broadcast. Then the rate decides how long it survives in the mempool. At 250 sat/vByte it is in the
   next block; at 2 sat/vByte it sits there in plain sight until a bot outbids it – exactly what cost
   puzzles 66 and 69. About 45 EUR out of 7.1 BTC is the cheapest protection in the whole procedure.
5. In the same window click **"Preview"**, then **"Share" at the bottom left** → **"Save to file"**.
   That gives you the unsigned transaction (PSBT). Do **not** press "Send/Broadcast".
   *Steps and names checked with Electrum 4.8.2 (18.09.2026); older versions called it
   "Preview/Advanced → Export". The next version may rename it again – then look for the item that
   matches the description.*

### 4b. Sign (wallet with the key, offline)

1. **Disconnect the network.** Start Electrum in offline mode:

   ```
   electrum.exe --offline
   ```

2. New wallet → **"Import Bitcoin addresses or private keys"** → paste the **WIF** from
   `pruefe.ps1`. The address shown must be `1PWo3J…`.
3. **Tools → Load transaction → From file** → load the PSBT from 4a.
4. Check: **recipient = your own address**, amount and fee plausible.
5. **Sign** → **Export** as **hex** (save to a file or copy).
   Do **not** press "Send".

   **Note the difference to 4a:** the unsigned file from 4a does not contain the public key yet and is
   harmless. This **signed** file does – which makes it, for anyone with Kangaroo, as good as the
   private key itself. It goes to Slipstream and nowhere else: no block explorer, no forum, no cloud,
   no chat, no AI tool.
6. Close Electrum.

---

## 5. Hand it privately to a miner

- [ ] **MARA Slipstream:** <https://slipstream.mara.com>
      Submit the signed transaction (hex) there. It goes directly to MARA Pool, not into
      the public mempool. According to reports from August 2026 it is free of charge, only the normal
      transaction fee applies.
- [ ] **Patience:** It is only included when MARA Pool finds a block – that can take
      hours. Do **not** additionally broadcast it publicly "to speed things up".
- [ ] Watch it on mempool.space (address from step 2). As soon as the transaction is in a
      block, it is safe.
- [ ] **If Slipstream is not available:** research beforehand which private
      submission routes are currently used (Bitcointalk thread about the puzzle,
      privatekeys.pw). **Unsuitable** are accelerators that require an already broadcast
      transaction or TXID.
- [ ] Remaining risk: the pool operator sees the transaction. There is currently no better
      way.

---

## 6. After confirmation

- [ ] Wait for **6 confirmations**.
- [ ] The puzzle address is burned from now on – **never** send anything to it again.
- [ ] Keep **silent**: anyone known to have won becomes a target for phishing,
      fraud and worse. Keep the seed of the destination wallet safe and offline.
- [ ] **Taxes:** the tax treatment of such a find is not clear-cut.
      Before any sale, ask a **tax advisor with crypto experience**.
- [ ] **Document** (for the tax office and for exchanges asking about the source of funds):
  - from `daten`: `found71-COMPUTER-gpuX.txt` with its date, `bitcrack71-COMPUTER-gpuX.log` / `.err`,
    `share71-COMPUTER-gpuX.txt`
  - TXID of the payout, date and exchange rate in your currency at the time of receipt
  - this checklist with notes on when what happened

---

## 7. Prepare now (dry run)

- [ ] Test `pruefe.ps1` – with the solved puzzle 20:

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File .\skripte\pruefe.ps1 -Hex D2C55 -Sprache en
  ```

  Expected: address `1HsMJxNiV7TLxmoF6uJNkydxPFDog4NQum`,
  WIF `KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rHfuE2Tg4nJW`

- [ ] Install Electrum and walk through step 4 once with a **small amount of your
      own** (watch-only → PSBT → sign offline → export hex).
      In the exercise the transaction may be broadcast normally.
- [ ] Check that the Heuhaufen folder is **not** inside a cloud folder.
- [ ] Keep the destination wallet (hardware wallet) ready.
- [ ] Bookmarks: mempool.space address, slipstream.mara.com, privatekeys.pw

---

## Appendix: pruefe.ps1

It is a separate file in the subfolder `skripte`. Without parameters it takes the first `found*.txt` from `daten` (otherwise from the current folder). If it is missing: save the content as `skripte\pruefe.ps1`.
The script works completely offline (Windows PowerShell 5.1). `-Sprache en` shows the output in English, `-Sprache de` in German; without it the Windows display language decides.

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
