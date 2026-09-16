Heuhaufen 1.23 - Searching for the key of a Bitcoin puzzle
==========================================================

What this is about
------------------
The Bitcoin puzzle transaction from 2015 contains addresses whose keys deliberately lie in a
small range. Puzzle 71 is still open and holds about 7.1 BTC. The chance of finding it is
tiny - this is a tinkering project, not an investment. The search runs exclusively in these
puzzle ranges, never for other people's wallets.

What you need
-------------
- An NVIDIA graphics card with a current driver; for the default search program CUDACyclone a
  GTX 16xx, RTX 20xx or newer (older cards: BitCrack, see below). CUDA does not need to be
  installed, the required runtime file is included. nvidia-smi comes with the driver.
- Windows 10 or 11.

Language
--------
Windows, web page and messages follow the Windows display language: German on a German Windows,
English otherwise. To fix it, set in puzzle-config.ps1:  $Sprache = 'en'  (or 'de').
Some settings, switches and file names keep their German names (e.g. -OhneLimit, $Fenster, daten\).
Log files are written in German.

What is where
-------------
  puzzle.bat              start the search
  tuning.bat              measure the best settings for your own card
  puzzle-config.ps1       settings (open with Notepad)
  HIT-Emergency-Plan.md   what to do if something is really found (German: TREFFER-Notfallplan.md)
  README.txt              this file (German: LIESMICH.txt)
  programm\               the search programs (CUDACyclone.exe, cuBitCrack.exe, cudart64_12.dll)
  skripte\                the PowerShell scripts - nothing to touch here
  homeassistant\          example cards for a Home Assistant dashboard (see "Home Assistant")
  daten\                  created while searching: sections (shares), progress, logs,
                          tuning report and - should it happen - the hit file found*.txt
Move or back up the folder as a whole, not single files from it.

Setup
-----
1. Unpack the zip, for example to C:\ - this creates the folder C:\Heuhaufen.
2. Windows marks unpacked files as "from the internet". Open a PowerShell once in the folder
   C:\Heuhaufen and enter:
       Get-ChildItem -Recurse | Unblock-File
3. Start tuning.bat (see below). It measures the best settings for your own card and enters
   them into puzzle-config.ps1 if you want. Takes about 5 to 20 minutes per card.
4. Open puzzle-config.ps1 with Notepad and look through it. The puzzle number matters most.
5. Start puzzle.bat. Windows asks for administrator rights; the script needs them only to set
   the power limit of the card and to end processes cleanly.

Installing a new version (a folder already exists, also the old C:\BitCrack)
---------------------------------------------------------------------------
1. End the search (in the window Ctrl+C, then Y).
2. Unpack the new zip, this creates C:\Heuhaufen (Unblock-File as above).
3. From the old folder copy the folder daten\ and your own puzzle-config.ps1 into the new folder,
   replacing the ones supplied. daten\ holds share, progress and the list of finished
   shares - the search continues exactly where it left off.
4. Start puzzle.bat in the new folder. If everything runs, the old folder can go. If you have a
   task in the Task Scheduler or a shortcut, point it to the new path.
The version number is shown at the top of the window and on the web page.

Finding the best settings (tuning.bat)
--------------------------------------
The script measures on its own, asks for administrator rights first (for the power limit)
and does the following per card model with the configured search program (default CUDACyclone):
- a calculation test: the search program must find the known key of the solved puzzle 32,
- a tuning series: the work packages are enlarged (CUDACyclone: --grid, BitCrack: -b
  and -p) until it no longer gets noticeably faster or graphics memory would run short.
  The smallest setting that is almost as fast as the best one is chosen - that leaves
  graphics memory free for other programs,
- a power series: the power limit is lowered in steps. The most economical step that still
  delivers at least 90 % of the speed is recommended,
- finally a second calculation test with the result,
- with several identical cards additionally a joint run: all cards compute at the same time
  with the recommended limit, 5 minutes per step. If a card gets too hot (throttling), the
  limit for all is lowered in 10 % steps until none throttles any more. A card measured on
  its own does not get as hot as in the group. This takes 5 to 15 minutes more.
Afterwards the power limit is reset, the result is in daten\tuning-<computername>.txt.
During the measurement do not use the graphics card otherwise and have no puzzle.bat open.
Cancel with Ctrl+C or by closing the window, the power limit is reset then.

Variants (in a PowerShell in the folder C:\Heuhaufen):
    .\tuning.bat -OhneLimit       tuning only, power limit stays, no admin rights needed
    .\tuning.bat -Device 1        GPU 1 only (otherwise each card model once)
    .\tuning.bat -Einzeln         without the joint run of identical cards
    .\tuning.bat -MinTempo 95     power limit: at least 95 % instead of 90 % of the speed
    .\tuning.bat -Programm bitcrack   measure BitCrack instead of CUDACyclone (enters it that way too)

What the window shows
---------------------
Progress in the current section (share), speed in MKey/s, temperature, power draw and cost.
The search regularly saves its position (BitCrack every minute, CUDACyclone every one to two
minutes), a restart continues from there. Searched shares are recorded in
daten\done*.txt and never drawn again. So nothing is lost if the computer is off in between.

Keys
----
  P   Pause: the search program is ended, the card is free. P again resumes.
      If StartWartet is $true in the configuration, P starts the search in the first place.
  V   Automatic pause on/off (see "Automatic pause").
  W   Web page on/off (only if WebPort is set).
  Ctrl+C asks first: Y quits, N (or 30 s without input) keeps searching.

Automatic pause
---------------
If another program needs the graphics card, for example a game, video editing or an AI program,
the search pauses by itself and continues afterwards. This is detected from the graphics memory
used by other programs (window: "other ... MB"): pause from 2000 MB, continue below 1500 MB, each
after a short delay. Adjustable in puzzle-config.ps1 with $VramPauseMB and $VramResumeMB;
$VramPauseMB = 0 switches the automatic off completely. Key V switches it off and on in the window.
If the computer already uses more than the threshold at start (e.g. several large monitors or a
browser with many tabs) or the search pauses three times within 10 minutes, the automatic
switches itself off for this session and says so in the status line. Then set $VramPauseMB
higher, e.g. 3000.
If Ollama runs on the same computer, the dashboard can ask it directly ($OllamaApi in
puzzle-config.ps1). The search then pauses as soon as Ollama works, and a parked model does not
matter.

Web page
--------
A small web server starts with the search. In a browser, http://<computername>:8080/ shows all
cards with speed and temperature, also from another computer in the same network (on the search
computer itself http://localhost:8080/ works too). It also has buttons for pause, resume and automatic.
The script creates the required firewall rule on the first start, but only for private
networks. If the network is set to "Public" in the Windows settings, the page stays invisible to
other computers - then switch it to "Private" there. The page has no password: do not forward this
port to the internet. Switch it off with $WebPort = 0 in puzzle-config.ps1; if 8080 is already used
by another program, enter a different port, e.g. 8090.
When the search ends, the page still shows that briefly, then it is gone (the web server runs
inside the search window).

Window in the notification area (tray) or minimised
---------------------------------------------------
In puzzle-config.ps1:

    $Fenster = 'tray'             (or 'minimiert', default 'normal')

With 'tray' the window disappears and one icon per card appears in the notification area at the
bottom right. Left click shows or hides the window, minimising sends it back there. Right click:
search on/off, auto pause, web page, quit. Windows 11 first puts new icons into the overflow
(arrow up) - drag it into the bar once. While the window is hidden, Ctrl+C and the X do not
work; quit via the menu then. If the search ends with a hit or an error, the window appears
by itself.

What the dashboard remembers
----------------------------
Web page on/off, auto pause on/off and whether it was searching last are stored in
daten\merken-<computername>-gpu<N>.json. On the next start this takes precedence over the values
in puzzle-config.ps1: if the search was running when the window was closed, it continues
immediately, even with $StartWartet = $true; if it was paused by hand, the window just stands
ready. Delete the file = values from the configuration again. $WebPort = 0 always switches the
web page off.

Home Assistant (MQTT)
---------------------
If Home Assistant runs with an MQTT broker (e.g. Mosquitto), the dashboard reports there and
accepts commands. In puzzle-config.ps1:

    $MqttHost = 'homeassistant.local'     name or IP address of the broker
    $MqttUser = 'user'                    only if the broker requires a login
    $MqttPass = 'password'

Home Assistant creates the device "Heuhaufen <COMPUTERNAME> GPU <N>" by itself (MQTT Discovery):
state, speed, progress, time left, power, temperature, fan, energy, hit (yes/no only,
never the key) and the switches Search, Auto pause and Web page. The switches can also be used in
automations. When the dashboard is closed, HA shows the measurements as "unavailable".
With several computers: each reports under its own name, they do not interfere.

The sensor names follow the dashboard's language at the moment HA creates the device, and HA
builds the entity IDs from them (English: sensor.heuhaufen_mypc_gpu_0_speed, German:
sensor.heuhaufen_mypc_gpu_0_tempo). Changing the language later renames the sensors in HA but
keeps the entity IDs.

A ready-made card for the HA dashboard is in homeassistant\heuhaufen-card-en.yaml (for English
entity IDs; heuhaufen-karte.yaml is the German one). In the dashboard choose "Add card" ->
"Manual", paste the content and replace "computername" everywhere with your own computer name in
lower case, e.g. heuhaufen_mypc_gpu_0. For the second graphics card add a copy with gpu_1. The
exact names are shown in HA at the device. Border colour and progress bar need card-mod (from
HACS); without card-mod delete the card_mod blocks.

Several graphics cards
----------------------
puzzle.bat starts a separate window per card, each searches in a different section.

Two search programs: CUDACyclone (default) and BitCrack
-------------------------------------------------------
The folder programm contains two search programs. puzzle.bat and tuning.bat use CUDACyclone.
BitCrack is the somewhat slower but well-proven alternative. Switch in puzzle-config.ps1:

    $Engine = 'bitcrack'          (back with $Engine = 'cyclone')

or for one card only in its profile with  Engine = 'bitcrack'. tuning.bat follows that.

The differences (measured on an RTX 5060 Ti at 150 W):
- Speed: CUDACyclone 1,720 MKey/s, BitCrack 991 MKey/s. CUDACyclone therefore checks about 74 %
  more keys with the same power (11.5 instead of 6.6 MKey per joule).
- Graphics memory: CUDACyclone uses about 1.7 GB, BitCrack about 0.5 GB. That only matters if
  you run programs with a lot of graphics memory alongside (e.g. games, video editing or AI programs).
- Saving: BitCrack saves its position every minute. CUDACyclone searches in blocks and saves
  a checkpoint every one to two minutes; on pause or abort it continues from the last checkpoint.
  The window shows when the next checkpoint comes.
- Cards: CUDACyclone runs from GTX 16xx / RTX 20xx on. For older cards use BitCrack.
- Maturity: BitCrack has been widely used for years, CUDACyclone is newer. Both have found the
  known keys of solved puzzles in this package.
Both divide the range the same way: share, progress and done list are kept when switching.
If programm\CUDACyclone.exe is missing, puzzle.bat and tuning.bat search with BitCrack and say so.

Starting automatically at sign-in (optional)
--------------------------------------------
A shortcut in the Startup folder asks for administrator rights at every sign-in.
It works silently via the Task Scheduler. Open a PowerShell or command prompt once
AS ADMINISTRATOR and enter (adjust the path to your own folder):

    schtasks /create /tn Heuhaufen /tr "C:\Heuhaufen\puzzle.bat" /sc onlogon /rl highest /f

From then on the window opens by itself at every sign-in. Useful together with

    $StartWartet = $true

in puzzle-config.ps1: the window then just stands ready and only computes when you press P in
the window or click "Start search" on the web page. Exception: if the search was running when
the window was last closed, it continues immediately (see "What the dashboard remembers").

More commands:

    schtasks /run /tn Heuhaufen        start by hand, without a prompt
    schtasks /query /tn Heuhaufen      check whether the task exists
    schtasks /delete /tn Heuhaufen /f  remove the task again

If you prefer clicking: open Task Scheduler, create task, trigger "At log on", action
"Start a program" with puzzle.bat, and at the bottom tick "Run with highest privileges".
Without this tick the rights prompt still appears.

If something is actually found
------------------------------
The window shows a green box and beeps, the key is in daten\found*.txt.
Then please read HIT-Emergency-Plan.md before anything happens. The most important points:
- Do not type the key anywhere, not in chats, not in AI tools, not in the cloud.
- Do NOT send the transaction to the public network with a normal wallet. It would be
  visible there immediately and could be replaced by other people's bots; that has happened
  several times with earlier puzzles. The route goes via a miner who includes it privately.
- skripte\pruefe.ps1 recomputes the found line offline and shows address and WIF.

Have fun tinkering.