# puzzle-config.ps1 - Einstellungen fuer diesen Rechner
# Alles hier ueberschreibt die Standardwerte aus skripte\puzzle.ps1. Zeilen mit # sind abgeschaltet.

$Puzzle = 71                 # 71-74 und 76-79 sind hinterlegt. 71 = rund 7,1 BTC.

# ---- Sprache ----
$Sprache = ''                # 'de' = Deutsch, 'en' = Englisch, '' = Windows-Anzeigesprache

# ---- Grafikkarte ----
$PowerLimit = 0              # Watt je Karte. 0 = Einstellung der Karte nicht anfassen (sicherste Wahl).
                             # Erst mit nvidia-smi -q -d POWER den erlaubten Bereich ansehen.
$Tuning = '-b 32 -t 256 -p 512'   # nur fuer BitCrack
                             # Passende Werte fuer die eigene Karte ermittelt tuning.bat und traegt
                             # sie auf Wunsch unten als Profil ein.
$PricePerKwh = 0.30          # nur fuer die Kostenanzeige

$Engine = 'cyclone'          # Suchprogramm: 'cyclone' = CUDACyclone (Standard, deutlich schneller) oder
                             # 'bitcrack' = BitCrack (langsamer, braucht weniger Grafikspeicher, laeuft
                             # auch auf aelteren Karten). Unterschiede siehe LIESMICH.txt.

# Profile je Karte (der Name wird im Kartennamen gesucht, erste Zeile die passt gewinnt):
# $GpuProfiles = [ordered]@{
#     'RTX 5060 Ti' = @{ PowerLimit = 150; Tuning = '-b 32 -t 256 -p 512';  PricePerKwh = 0.30 }
#     'RTX 2080 Ti' = @{ PowerLimit = 200; Tuning = '-b 64 -t 256 -p 1024'; PricePerKwh = 0.30 }
# }

# ---- Pause, wenn andere Programme die Karte brauchen ----
# Spiel, Videoschnitt, KI-Programm: Belegen andere Programme Grafikspeicher, haelt die Suche an und
# laeuft danach von selbst weiter. Taste V schaltet das im Fenster aus und ein.
$VramPauseMB  = 2000         # ab so viel fremdem Grafikspeicher pausieren (Fenster: "fremd ... MB"); 0 = aus.
                             # Liegt schon beim Start mehr an (z. B. mehrere grosse Monitore), schaltet
                             # sich die Automatik ab und sagt es - dann hoeher setzen, z. B. 3000.
$VramResumeMB = 0            # darunter wieder starten; 0 = VramPauseMB - 500
$VramHoldSec  = 6            # so lange muss der Speicher belegt sein, bevor pausiert wird
$VramBackSec  = 60           # so lange muss er frei sein, bevor es weitergeht

# Nur fuer KI-Programme wie Ollama auf demselben Rechner: direkt fragen statt Speicher messen.
# Pausiert, sobald Ollama rechnet; ein geparktes Modell darf liegen bleiben.
# $OllamaApi     = 'http://localhost:11434'
$OllamaIdleSec = 30          # so lange muss Ollama ruhig sein, bevor die Suche weiterlaeuft

# ---- Webseite im eigenen Netz ----
$WebPort = 8080              # Webseite http://<rechnername>:8080/ mit allen Karten, auch von einem anderen
                             # Rechner im selben Netz; 0 = keine Webseite. Die Firewall-Regel legt das
                             # Skript selbst an (nur private Netze). Steht das Netzwerk auf "Oeffentlich",
                             # bleibt die Seite unsichtbar - dann in Windows auf "Privat" umstellen.
                             # Kein Passwort: den Port nicht ins Internet weiterleiten.
$WebBind = '+'               # '+' = im Netz erreichbar, 'localhost' = nur dieser Rechner

# ---- MQTT / Home Assistant ----
# Werte an einen MQTT-Broker melden und Befehle (Pause, Weiter) von dort annehmen. Home Assistant
# legt die Geraete ueber MQTT Discovery selbst an. Broker ohne Passwort; leer = aus.
# $MqttHost = 'homeassistant.local'
# $MqttUser = ''             # nur wenn der Broker eine Anmeldung verlangt
# $MqttPass = ''

# Webseite (Taste W), Auto-Pause (Taste V) und ob zuletzt gesucht wurde merkt sich das Dashboard in
# daten\merken-<Rechner>-gpu<N>.json. Das hat Vorrang vor den Werten hier; Datei loeschen = wieder die Config.
# $WebPort = 0 schaltet die Webseite trotzdem immer ab.

# ---- Fenster ----
# $Fenster = 'tray'          # 'normal', 'minimiert' (Taskleiste) oder 'tray' (nur Symbol im Infobereich:
                             # Linksklick zeigt das Fenster, Rechtsklick: Suche, Auto-Pause, Webseite, Beenden)