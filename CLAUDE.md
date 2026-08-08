# CLAUDE.md – WillFA7 Monorepo

Williams-System-3-bis-7-MPU-Ersatz auf Altera-FPGA. VHDL, Quartus.
Autor: Ralf Thelen (bontango), www.lisy.dev · Repo: github.com/bontango/WillFA7

**Sechs Platinenvarianten, ein Sourcebaum, ein Top-Level.** Was pro Board unterschiedlich
ist, steht in `variants/<name>/` – Pins, Device und fünf Konstanten. Sonst nichts.
Eine Ausnahme mit Grund: `cyclone_ii` baut über die Hülle `top/WillFA7_cii.vhd`, siehe unten.

Das Repo liegt unter `N:\Projekte\WillFA7\FPGA_source\` und endet dort. Eine Ebene höher,
in `N:\Projekte\WillFA7\`, steht die `PROJECT.md` mit den Projekt-Metadaten; daneben die
nicht versionierte Doku – Handbücher, Schaltpläne, Target3001, ROMs, SD-Images.

## Die wichtigsten Regeln

- **`variants/<name>/WillFA7.qsf` ist generiert.** Nicht von Hand editieren. Änderungen gehören
  in `device.tcl`, `pins.tcl`, `variant.psd1` oder `scripts/files_*.tcl`, danach `gen_qsf.ps1`.
- **Alles muss VHDL-93 bleiben.** Cyclone II baut mit Quartus 13.0sp1. Kein `else generate`
  (VHDL-2008), und kein `numeric_std` neben `std_logic_unsigned` im Top-Level – die Operatoren
  würden mehrdeutig.
- **Nach jeder Änderung an `rtl/common/` oder `top/`: `scripts\check.ps1 -Fit`.** Das vergleicht
  LE/Memory/Slack gegen `scripts\baseline.csv`. Eine unerklärte Abweichung ist ein Befund.
- **Ganze Vektoren werden im Port Map positionsweise verbunden, nicht nach Indexnamen.**
  Hängt ein `(1 to 4)`-Signal an einem `(4 downto 1)`-Port, sind die Bits gespiegelt – und
  Quartus sagt dazu **nichts**. Genau so lagen die Soundkarten-DIPs an `WISOF.SB_Opt`
  (Chimes auf Dip4 statt Dip1). Deshalb: bei jeder Portverbindung eines Vektors die Richtung
  beider Seiten vergleichen; stimmen sie nicht überein, die Bits einzeln zuordnen. Im
  Top-Level laufen `game_option` (`6 downto 1`) gegen `read_the_dips`/`read_the_dips_s`
  (`1 to 6`) – dort ist die Spiegelung gewollt und hardwareverifiziert, `game_option(n)` ist
  DIP *n*. Nicht „geradeziehen".
- **Cyclone II ist die harte Randbedingung** (4312 / 4608 LE = 94 %). Was dort nicht passt,
  passt nirgends. Optionale Blöcke müssen per `if ... generate` **weggenerieren** – nicht darauf
  hoffen, dass Quartus sie wegoptimiert.
- **`SPI_Master.vhd` nicht ohne ausdrückliche Aufforderung ändern** – hat schon Regressionen
  verursacht. Es ist bewusst die Pre-Stage-A-Fassung ohne synchronen Reset.
- **Nichts löschen oder verschieben ohne ausdrückliche Freigabe** (projektweit, siehe
  `N:\Projekte\CLAUDE.md`).
- **Deutsch antworten.** Kommentare in Quelltext, `changelog.txt` und `README.md` auf Englisch.
- PowerShell ist 5.1: kein `&&`, kein Ternary. Und Variablennamen sind **case-insensitiv** –
  `$T` und `$t` sind dieselbe Variable.

## Aufbau

```
rtl/common/      die Module, die jede Variante benutzt, plus version_pkg.vhd
rtl/cyclone_ii/  rtl/cyclone_iv/  rtl/cyclone_10/
                 Megafunctions je Familie, ueberall gleiche Entity-Namen -
                 welche Familie gilt, entscheidet allein die .qsf
rtl/serial_api/  USB-Monitor-API (HAS_MONITOR)
rtl/sound/       Soundkarten-Module (HAS_SOUND) - in JEDER Dateiliste, nicht nur
                 in der der S-Variante, siehe 'weggenerieren' weiter unten
top/WillFA7.vhd  DAS Top-Level
top/WillFA7_cii.vhd  Platinenhuelle fuer Cyclone II (VIRTUAL_PIN geht dort nicht)
variants/<name>/ variant_pkg.vhd · device.tcl · pins.tcl · variant.psd1 ·
                 WillFA7.sdc · WillFA7.qpf · willfa7.cof · WillFA7.qsf (generiert)
scripts/         gen_qsf.ps1 · check.ps1 · build.ps1 · release.ps1 · files_*.tcl · baseline.csv
bin/             Release-Binaries + changelog.txt
docs/            Analysen (Switch-Masken, Blanking, EEprom, Spezialsolenoide, Speicherbilanz
                 der S-Variante) und die
                 beiden User Manuals (WillFA7 und WillFA7S). Manuals ohne Versionsnummer
                 im Dateinamen - die Version steht im Kopf des Dokuments
archive/         historische Modulstaende, in keinem Build
```

## Die sechs Varianten

| `variants/<name>` | Version | FPGA | Quartus | Stand |
|---|---|---|---|---|
| `cyclone_ii` | 1.22 | EP2C5T144C8 | **13.0sp1** | aktiv, 96 % LE, baut über `WillFA7_cii` |
| `cyclone_iv_v3` | 2.22 | EP4CE6F17C8 | 22.1std | aktiv, mit USB-Monitor-API |
| `cyclone_iv_v4` | 3.22 | EP4CE6E22C8 | 22.1std | aktiv, **Leitvariante** |
| `cyclone_10` | 4.22 | 10CL006YE144C8G | 22.1std | aktiv |
| `cyclone_iv_dev_open` | 5.22 | EP4CE6E22C8 | 22.1std | aktiv, Aliexpress-Devboard |
| `s_cyclone_iv_v4` | 6.22 | EP4CE10E22C8 | 22.1std | aktiv, **mit Soundkarte** – `docs/soundcard_variant.md` |

Angezeigte Version = `BOARD_ID.SW_SUB1 SW_SUB2`. Erste Stelle aus
`variants/<name>/variant_pkg.vhd`, die beiden anderen aus `rtl/common/version_pkg.vhd`.
Ein Release ändert **eine** Zahl. `BOARD_ID` 7 ist frei – es gehörte einer Cyclone-10-Fassung
der Soundplatine, die am 04.08.2026 aufgegeben und aus dem Repo entfernt wurde.

**Hardware-Teststand: nur 3.20 war getestet.** Weder `.21` noch `.22` ist auf einem Board
getestet. Gründe in `VARIANTEN.md`.

## Build

`quartus_sh` ist **nicht im PATH**, die Skripte kennen die Pfade
(`C:\altera\13.0sp1` für Cyclone II, `C:\intelFPGA_lite\22.1std` für den Rest).

```powershell
scripts\gen_qsf.ps1                    # alle WillFA7.qsf neu erzeugen
scripts\gen_qsf.ps1 -Check             # nur pruefen, ob sie aktuell sind
scripts\check.ps1                      # quartus_map, alle aktiven Varianten
scripts\check.ps1 -Fit                 # + Fitter/Timing + Baseline-Vergleich
scripts\check.ps1 -Variants cyclone_ii -Fit
scripts\build.ps1 cyclone_iv_v4        # voller Compile, .sof/.pof/.jic
scripts\release.ps1 -Note "..."        # alles bauen, nach bin/ ablegen, changelog
```

`check.ps1` liefert Exit 1 bei Build-Fehler, Exit 2 bei Baseline-Abweichung.

`check.ps1` und `build.ps1` rufen als Erstes `gen_qsf.ps1 -Quiet` auf (`release.ps1` erbt
das über `build.ps1`), weil Quartus die generierte `.qsf` aus der IDE heraus von sich aus
umschreibt. Musste dabei etwas zurückgesetzt werden, steht eine gelbe Zeile im Protokoll.
`-NoGen` schaltet es ab. Wer in der IDE bewusst ein Assignment setzt – SignalTap –, muss
es vorher ins passende `.tcl` übernehmen, sonst ist es beim nächsten Lauf weg.

Der Arbeitsablauf drumherum – Quartus-IDE neben den Skripten, was die IDE nicht festlegen
darf, eine Änderung von der ersten Zeile bis zum Release – steht in `WORKFLOW.md`.

## Was pro Variante variiert

`variants/<name>/variant_pkg.vhd`:

| Konstante | Bedeutung |
|---|---|
| `BOARD_ID` | erste Stelle der Versionsanzeige |
| `ROM_COUNT` | 5 oder 6 ROM-Bloecke à 2K. 5 heisst: kein rom0, Fenster 0 des Images wird gelesen und verworfen, 5000h–57FF liest FF, Defender und Star Light laufen nicht. **Seit `.22` kein Kartenformat mehr** – das ist für alle gleich. |
| `HAS_MONITOR` | USB-Monitor-API, ca. 550 LE |
| `HAS_SOUND` | integrierte Soundkarte, ca. 850 LE und 165 kBit. Aendert ausserdem die DIP-Matrix und ist das einzige, was die Bytes 12K–32K des Slots dekodiert. **`docs/soundcard_variant.md`** |
| `SD_CHECK_CRC` | CRC16-CCITT der Karte prüfen. Überall `true`; `false` spart auf Cyclone II ca. 90 LE, liest dieselbe Karte, merkt aber nichts von einer defekten und zeigt statt der beiden Summen weiter das Build-Datum. |

`variants/<name>/variant.psd1` (von den Skripten gelesen): `RtlFamily`, `Options`,
`VirtualPins`, `BinFolder`, `ReleaseArtifact`, `Dormant`, `TopEntity`.

### Optionale Ports

`LED_debug`, `USB_Tx`, `USB_Rx`, `debug`, `SB_Sound`, `SB_Speech`, `SB_Test` und `Dip_Ret_4`
stehen in **jeder** Portliste. Boards ohne den Pin bekommen `VIRTUAL_PIN` aus `variant.psd1`.
Das ist keine Kosmetik: ein deklarierter Ausgangsport ohne Location ist für Quartus ein
*benutzter* Pin, `RESERVE_ALL_UNUSED_PINS` greift dort nicht, und er würde irgendwo auf der
Platine platziert und getrieben.

**`VIRTUAL_PIN` funktioniert auf Cyclone II nicht.** Quartus II 13.0sp1 Web Edition nimmt die
Zuweisung an und ignoriert sie:

```
Warning (292013): Feature Virtual IO is only available with a valid subscription license.
```

Im Fitter-Report steht dann `Total virtual pins: 0`. Im ausgelieferten **1.21** lagen deshalb
`LED_debug` auf PIN_26, `debug` auf PIN_27, `USB_Rx` auf PIN_73 (alle drei getrieben, 24 mA) und
`USB_Tx` auf PIN_80 – vom Fitter gewählt. Seit `.22` baut Cyclone II über die Hülle
`top/WillFA7_cii.vhd`, die nur die 82 real vorhandenen Ports deklariert; die optionalen werden
damit zu internen Signalen und verschwinden. 86 → 82 Pins.

**Wer einen Port zum Top-Level hinzufügt, muss ihn auch in `WillFA7_cii.vhd` nachtragen.**
Die Hülle steht deshalb in *jeder* Dateiliste: dann bricht der Build überall laut, statt bei
Cyclone II stumm.

### `.sdc` bleibt pro Variante

`cyclone_iv_v3`, `cyclone_10` und `cyclone_iv_dev_open` sind byte-identisch zu `cyclone_iv_v4`.
`s_cyclone_iv_v4` ist es bis auf zwei angehängte `set_false_path` für die Audio-Ausgänge
(`docs/soundcard_variant.md`, Abschnitt 11).
**Cyclone II ist ein echter Fork** (von Quartus 13 generiert, andere PLL-Hierarchienamen).
Nicht zusammenlegen. Dort kommt seit `.22` der Hüllen-Präfix dazu: `get_registers` will
`WillFA7:CORE|cpu_clk_gen:clock_gen|…`, die PLL dagegen ihren SDC-Pinnamen
`CORE|PLL|altpll_component|pll` – **ohne** Entity-Präfix. Der Fitter-Report druckt den
richtigen Namen unter „SDC pin name". Ein Constraint, das nicht mehr trifft, wird **stumm**
verworfen; die Kontrolle ist der Slack gegen `scripts/baseline.csv`.

Die `.sdc` referenzieren `cpu_clk_gen:clock_gen`, `flipflops:FF_SOLS`, `flipflops:FF_LAMPSS`
und `PLL`. **Diese vier Instanzen nie in ein Generate wickeln** – Generate-Labels ändern den
Quartus-Hierarchienamen und die Constraints brechen stumm.

## Architektur

**Top-Level-Entity:** `WillFA7` in `top/WillFA7.vhd`

| Modul | Datei | Zweck |
|---|---|---|
| cpu68 | `rtl/common/cpu68.vhd` | Motorola 6800/6801 (OpenCores, John E. Kent, GPL), v0.85 |
| pia6821 | `rtl/common/pia6821.vhd` | PIA, 5 Instanzen |
| SD_Card | `rtl/common/SD_Card.vhd` | SPI-SD-Controller, lädt die Spiel-ROMs. Generics `Read_Bytes`, `Slot_Sectors`, `Check_CRC`, `CRC_Bytes`. Seit `.22` steht auf allen Varianten dasselbe drin: 128 Sektoren je Spiel, CRC über die ersten 32 KByte |
| crc16_ccitt | `rtl/sound/crc16_ccitt.vhd` | LFSR für die Kartenprüfsumme. Liegt aus historischen Gründen unter `rtl/sound/`, gehört seit `.22` aber zu jedem Build |
| EEprom | `rtl/common/EEprom.vhd` | SPI-EEPROM (M95256 / M95512), Spielstand |
| williams_pll | `rtl/<familie>/williams_pll.vhd` | 50 MHz → 14,28 MHz |
| ram / rom_2K / R5101 | `rtl/<familie>/` | System-RAM, ROM-Bloecke, CMOS-RAM |
| boot_message | `rtl/common/boot_message.vhd` | Boot-/Diagnoseanzeige, 6- **und** 7-stellig (`seven_digit`) |
| game_pkg | `rtl/common/game_pkg.vhd` | was an der Spielnummer hängt: `has_7digit`, `is_system3` |
| read_the_dips | `rtl/common/read_the_dips.vhd` | Spielauswahl über DIPs |
| flipflops | `rtl/common/flipflops.vhd` | Flipper-Solenoide |
| spec_sol_trigger | `rtl/common/spec_sol_trigger.vhd` | Spezialsolenoid-Trigger mit Entprellung |
| sw_debounce | `rtl/common/sw_debounce.vhd` | Switch-Matrix-Entpreller, Maske je Spiel |
| WISOF | `rtl/sound/WISOF.vhd` | Williams-Soundkarte Typ 1/2 – **zweiter 6802**, eigene PIA, 5×4K ROM, CVSD-Sprachdekoder und ein gemischter Delta-Sigma-DAC (nur `HAS_SOUND`). Stand **WISOF 0.9**, Herkunft und Befundliste in `docs/soundcard_variant.md` Abschnitt 14 |
| read_the_dips_s | `rtl/sound/read_the_dips_s.vhd` | 4×4-DIP-Matrix der S-Platine (nur `HAS_SOUND`) |
| soundtest | `rtl/sound/soundtest.vhd` | Soundtest über `SB_Test` (nur `HAS_SOUND`) |

### Taktdomänen

- **50 MHz** externer Oszillator
- **14,28 MHz** aus der PLL (×123 ÷430)
- **~894 kHz** CPU-Takt (`cpu_clk_gen`), dazu `mem_clk` (phasenverschoben, glitch-sicher)
- **900 Hz** IRQ-Generator
- Übergänge über `Cross_Slow_To_Fast_Clock`

### Memory Map (Williams SYS7)

```
$0000-$00FF  System RAM
$0100-$01FF  CMOS RAM (geschuetzt)
$1000-$13FF  SYS7 Extended RAM
$2100-$2103  PIA5 (Sound/Comma)
$2200-$2203  PIA4 (Solenoide)
$2400-$2403  PIA3 (Lampen)
$2800-$2803  PIA1 (Display/Diag)
$3000-$3003  PIA2 (Switch-Matrix)
$5000-$7FFF  Spiel-ROMs (6x2K von SD; bei ROM_COUNT=5 erst ab $5800, $5000-$57FF liest FF)
```

### Boot-Phasen

Phase 0 (Reset/Bootmeldung) → Phase 1 (DIP/Spielauswahl) → Phase 2 (ROMs von SD + EEprom laden)
→ Phase 3 (Spiel läuft).

### Options-DIPs (`game_option(6 downto 1)`)

DIP ON heißt `game_option(n) = '0'`, Verbraucher benutzen also `not game_option(n)`.

| Bit | DIP | Funktion |
|---|---|---|
| 1 | DIP1 | NVRAM-Init (`opt_nvram_init_n`) |
| 2,3 | DIP2/3 | Pulszeit Spezialsolenoide (35/40/50/60 ms) |
| 4 | DIP4 | Spezialsolenoid-Entprellung: ON = 250 µs, OFF = 57 µs (`.18`-Verhalten) – `docs/spec_sol_trigger_analysis.md` |
| 5 | DIP5 | Switch-Matrix-Entprellung: ON = entprellt, OFF = `.17`-Durchreichen – der globale Notausgang |
| 6 | DIP6 | Spiel CONTACT: Spezialsolenoid 6 permanent |

In der Bootanzeige stehen die Optionen auf der Credit-Anzeige, **DIP1 wiegt 1** – dieselbe
Zählweise wie bei `game_select` und den Soundkarten-DIPs. Auf der S-Platine liegen dort zwei
Werte: **Soundkarten-Optionen S5 links, Spieloptionen S2 rechts**.

## Switch-Debounce-Maske (`rtl/common/sw_debounce.vhd`)

Sitzt zwischen den `sw_return`-Pins und PIA2 und entprellt jeden der 8×8 Schalter einzeln.
**Nicht global**: Entprellen kostet Latenz auf der Öffner-Seite, und die ist für „Level"-Schalter
fatal, deren Zustand das ROM nach dem Feuern einer Spule zurückliest (Drop-Target-Bänke,
Outhole, Eject Holes) – das ROM sieht „noch unten / Ball noch da" und feuert nach.

- `MASK_ROM` hält **32 Spiele × 8 Spaltenbytes** (2048 bit), adressiert über die Spielnummer.
  Quartus macht daraus einen M9K-Block – 0 LE.
- Bit *n* von Spaltenbyte *c* deckt Schalter `8*c + n + 1` ab. **`1` = entprellen, `0` = roh.**
- Alien Poker ist der Regressionsanker: bit-identisch zur hardwareverifizierten `.18`/`.19`-Maske.
- **Der Fehler ist asymmetrisch.** Ein Taster roh gelassen = `.17`-Verhalten (harmlos); ein
  Level-Schalter fälschlich entprellt bricht dessen Rücklese-Prüfung. Im Zweifel Bit auf `0`.
- Bei einer Meldung „Spiel spinnt": erst **DIP5 OFF**, dann das Bit dieses Schalters löschen.

Herleitung und Masken je Spiel: `docs/switch_masks.md`, Matrizen: `docs/switch_matrix/`,
Hintergrund: `docs/switch_debounce_analysis.md`. Nur Alien Poker ist hardwareverifiziert.

## Displaytyp hängt an der Spielnummer (`rtl/common/game_pkg.vhd`)

Die Bootmeldung und der Soundtest sind das einzige, was der FPGA selbst auf die Anzeige
schreibt; ab Bootphase 3 macht das Spiel-ROM die Strobes. Welche physische Stelle eine
Strobe-Nummer trifft, hängt am Displaytyp:

- **6-stellig** (Spiel 0–15): Strobe = Zeitschlitz, Statusziffern auf 6/7 (rechts) und
  14/15 (links), alle vier auf dem **oberen** Nibble.
- **7-stellig** (Spiel 16–31, also Algar, Alien Poker und alle SYS7): die Spielerstellen
  liegen auf Strobe 1–7 und 9–15, die Statusziffern nur noch auf Strobe 0 und 8 – dort
  **oberes Nibble = rechtes Paar, unteres = linkes Paar**.

`boot_message` schaltet das über den Eingang `seven_digit` um; die sechs Zeichen stehen
7-stellig rechtsbündig, die linke Stelle bleibt dunkel. Vollständige Tabelle, Quellen
(PinMAME `s6.c`/`s7games.c`, LISY `lisy_w.c`) und die Spielliste: **`docs/display_layout.md`**.
Für 16/17 (Algar, Alien Poker) steht die Hardwarebestätigung noch aus.

`is_system3` aus demselben Package steuert Memory Protect und – auf der S-Platine – die
Soundquelle. Beide Funktionen erwarten die **Spielnummer** `game_no = not game_select`,
nicht den DIP-Rohwert. Genau diese Verwechslung hat `is_sys3` von `.16` bis `.22` konstant
auf `'0'` gehalten.

**Ein neuer Port an `boot_message` trifft immer zwei Instanzen** – die Bootmeldung im
Top-Level und die des Soundtests in `rtl/sound/soundtest.vhd`.

## SD-Karte: ein Format für alle (seit `.22`)

Bis `.21` gab es drei Formate – 10 KByte ab 5800h (Cyclone II), 12 KByte ab 5000h (alle
anderen) und 64 KByte mit CRC (WillFA7S). Seit `.22` gilt überall das dritte:

```
Slot je Spiel      128 Sektoren = 64 KByte, Spiel 0 ab Sektor 660
                   -> Startsektor = 660 + Spielnummer * 128
0x0000 - 0x2FFF    12 KByte   MPU-ROMs, 6 x 2K -> 5000h..7FFFh
0x3000 - 0x7FFF    20 KByte   Soundkarten-ROMs, 5 x 4K (nur HAS_SOUND dekodiert sie)
0x8000 - 0xFFFD               frei
0xFFFE - 0xFFFF     2 Byte    erwartete CRC16-CCITT ueber die ersten 32 KByte
```

- **Die sechs 2K-Fenster sind auf jeder Variante dieselben.** Ein Board mit `ROM_COUNT = 5`
  verschiebt nichts, es lässt Fenster 0 einfach liegen. Genau das war vorher anders, und es
  ist der Grund, warum eine `.21`-Cyclone-II-Karte unter `.22` nicht mehr läuft.
- **Gelesen wird immer der ganze Slot**, weil die erwartete Prüfsumme in den letzten beiden
  Bytes steht. Das kostet rund **1 Sekunde mehr Bootzeit** (64 KByte statt 12 bei 400 kHz).
  Nur mit `SD_CHECK_CRC = false` endet der Lauf nach `Read_Bytes`.
- **Die gerechnete Summe steht auf `display3`, die gelesene auf `display4`.** Stimmen sie
  nicht überein: Fehlerziffer `7` vorn auf `error_disp4`, Blinkcode 7 auf `LED_SD_Error`,
  und die CPU wird **nicht** freigegeben.
- Eine alte Karte meldet sich damit als CRC-Fehler statt stumm ein falsches Spiel zu laden.
  Das ist die gewollte Diagnose, kein Defekt.

Karten erzeugt `N:\Projekte\WillFA7\SD image WillFA7 (roms)\make_sd.bat` (ausserhalb des
Repos). Slot 30 ist Defender, Slot 31 Star Light – beide brauchen die vollen 12 KByte und
laufen deshalb nicht auf Cyclone II.

## LED-Ausgänge mit Doppelfunktion

Zwei der LED-Ausgänge treiben **eine LED und zugleich eine Steuerleitung**. Genau das macht sie
gefährlich: sie sehen aus wie freie Anzeigen und sind es nicht.

| Port | LED auf der Platine | zweite Funktion auf derselben Leitung |
|---|---|---|
| `LED_active` | „active" | IC13 74HCT240 `/OE` (Switch-Strobes) **und** über T9 `/RESET` der fünf 74HCT273 – Solenoid- und Lampenlatches |
| `LED_status` | „status" | Display-Blanking |
| `LED_SD_Error` | „SD card error" | keine – reine LED, blinkt die Fehlercodes 1–7 |
| `LED_debug` | – | nur Devboards, folgt `reset_sw` |

**`LED_active` und `LED_status` nie für Status- oder Fehleranzeigen umwidmen.** Wer dort etwas
anzeigt, löscht dabei die Solenoid- und Lampenlatches bzw. blankt das Display – genau das war die
`.17`–`.19`-Regression. Schaltbild, Symptome und Fix: `docs/blanking_led_active.md`.

## EEprom-Save-Pfad (`rtl/common/EEprom.vhd`)

Clean-Room-Neubau (nach v097), hierarchische FSM mit Read-before-Write-Scan, kein Shadow-Cache:

- **Zwei parallele Prozesse:** `TOP` (Phasen-FSM) und `SPI_SUB` (gemeinsames 3-Zustands-Handshake
  `SPI_IDLE → SPI_RUNNING → SPI_RELEASE`).
- **19 benannte Phasen** (`PH_BOOT_CHECK` … `PH_NEXT_BYTE`). Jeder Save-Schritt
  (READ → COMPARE → WREN → WRITE → POLL → VERIFY → REVERIFY) ist genau eine Phase.
- **Alle Zeiten sind Generics:** `INIT_DELAY_CYCLES` (2 s), `PRE_WRITE_CYCLES` (1 s),
  `GLITCH_CYCLES` (1 µs), `REVERIFY_CYCLES` (100 ms), `HOLD_CYCLES` (≈20 µs),
  `SCAN_SETTLE_CYCLES` (5), `MAX_RETRY` (2), `SPI_HZ` (100 kHz).
- **Wahrheit ist immer das EEPROM selbst** – kein Shadow-Drift, keine Init-Sonderfälle.
- **Verzögerter Re-Verify:** nach dem ersten Verify 100 ms warten und erneut lesen. Die 100 ms
  sind zugleich die empirisch nötige Erholungslücke zwischen zwei WRITEs marginaler M95512.
- **Kein LED-Feedback.** `EEprom_error` bleibt `open`, `o_wr_in_progress` ungenutzt – und darf
  **nicht** auf `LED_active` gelegt werden (siehe oben).

R5101-Port B ist asynchron mit registrierter Adresse, deshalb wartet `PH_SCAN_SETTLE` 5 Takte.

**Cyclone-II-Sonderfall:** dort ist die R5101-Megafunction Single-Clock. Die Entity hat trotzdem
`clock_a`/`clock_b`, damit das Top-Level einheitlich bleibt; `clock_a` ist bewusst **nicht**
angeschlossen. Nicht „aufräumen" – Port B würde sonst von `clk_50` auf `mem_clk` wandern.

## Erwartete Quartus-Warnungen

Diese `Warning (10036)` sind bekannt und in Ordnung. Kommt eine andere dazu, ist das ein Befund:

| Warnung | Grund |
|---|---|
| `eeprom_wr_in_progress` never read | `o_wr_in_progress` ist bewusst unbenutzt |
| `RX_Data_W` / `RX_Data_Cmd` (EEprom) | Altbestand im Modul |
| `wr_rom0` never read (nur `cyclone_ii`) | rom0 ist per `ROM_COUNT` weggeneriert |
| `parameter` (WillFA7_Monitor, nur `cyclone_iv_v3`) | Altbestand im Monitor |

Die drei Warnungen zu `crc16`, `crc16_r` und `crc_error` sind seit `.22` **weg** – die Summen
stehen jetzt auf der Bootanzeige jeder Variante. Sie kämen zurück, wenn ein Board
`SD_CHECK_CRC = false` bekäme.

## Die Soundkarten-Variante

`s_cyclone_iv_v4` ist seit `.22` eine ganz normale Variante des gemeinsamen Top-Levels; alles
Sound-spezifische hängt an `HAS_SOUND`. Drei Dinge, die man wissen muss, bevor man etwas anfasst:

- **`WISOF` benutzt `cpu68`, `pia6821`, `one_pulse_only` und `Cross_Slow_To_Fast_Clock` aus
  `rtl/common/`.** Eine Änderung dort trifft damit **beide** CPUs, die der MPU und die der
  Soundkarte.
- **Quartus löst Entity-Referenzen auch im nicht genommenen `generate`-Zweig auf.** Deshalb
  stehen *alle* `rtl/sound/`-Dateien in `files_common.tcl`, also in jeder `.qsf`. Aus demselben
  Grund sind `MPU_RAM` und `SB_ROM` inferiertes VHDL und keine Megafunctions – eine für
  Cyclone IV E erzeugte Megafunction hat im Cyclone-II-Projekt nichts zu suchen.
- **Das SD-Kartenformat der S-Platine ist seit `.22` das Format für alle** – 64-KByte-Slots ab
  Sektor 660, CRC16 auf 0xFFFE/0xFFFF. Die Bytes 12K–32K liest nur diese Platine wirklich;
  die anderen lesen sie mit und werfen sie weg. Siehe Abschnitt „SD-Karte" oben.
- **Der EP4CE10 ist nicht wegzuoptimieren.** Ein EP4CE6 scheitert an *zwei* unabhängigen Grenzen:
  36 gebrauchte M9K gegen 30 vorhandene – davon 32 allein fürs ROM, das zu 100 % gepackt ist –
  **und** 6.377 LE gegen 6.272. Externer Speicher (SPI/QSPI-RAM) löst nur die erste und verschärft
  die zweite. Die vollständige Rechnung samt geprüfter Auswege: **`docs/memory_budget_willfa7s.md`**.
  Maßgeblich ist die **M9K-Blockzahl**, nicht die Bitzahl aus `baseline.csv` – die steht nur im
  Fitter-Report.
- **Der Kern ist Fremdcode mit eigener Versionsgeschichte.** Er stammt aus
  `N:\Projekte\Soundboards\FPGA Soundboard Williams\WISOF` und steht auf **0.9**. Wer ihn
  weiterzieht, nimmt nicht einfach die Datei von dort – die dortige Fassung ist eine
  eigenständige Platine mit SD-Karte, PLL und LEDs. Was abgezogen gehört, steht in
  `docs/soundcard_variant.md` Abschnitt 14.

Alles Weitere – Pins, DIP-Matrix, Adressraum der Soundkarte, Soundtest, Zeitverhalten – steht in
**`docs/soundcard_variant.md`**. Der alte Fork-Stand 6.03 liegt in `archive/s_cyclone_iv_v4_603/`.

## Historie und Altbestand

`VARIANTEN.md` beschreibt Stand, bekannte Defekte und Hardware-Teststand jeder Variante.
`PLAN_Zielstruktur.md` ist die Begründung für diese Struktur (Etappe 1 und 2 umgesetzt).
Der alte Ordnerbaum liegt weiterhin unter `N:\Projekte\WillFA\FPGA_source\` als vorläufiges
Backup, zusammen mit `archive src\` (rund 630 MB historische Projektstände, bewusst nicht im
Repo). `N:\Projekte\WillFA` enthält seit 28.07.2026 nichts anderes mehr – die Doku ist nach
`N:\Projekte\WillFA7\`, WillFA11 nach `N:\Projekte\WillFA11\` gezogen.
