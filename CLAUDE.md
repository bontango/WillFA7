# CLAUDE.md – WillFA7 Monorepo

Williams-System-3-bis-7-MPU-Ersatz auf Altera-FPGA. VHDL, Quartus.
Autor: Ralf Thelen (bontango), www.lisy.dev · Repo: github.com/bontango/WillFA7

**Sieben Platinenvarianten, ein Sourcebaum, ein Top-Level.** Was pro Board unterschiedlich
ist, steht in `variants/<name>/` – Pins, Device und drei Konstanten. Sonst nichts.

## Die wichtigsten Regeln

- **`variants/<name>/WillFA7.qsf` ist generiert.** Nicht von Hand editieren. Änderungen gehören
  in `device.tcl`, `pins.tcl`, `variant.psd1` oder `scripts/files_*.tcl`, danach `gen_qsf.ps1`.
- **Alles muss VHDL-93 bleiben.** Cyclone II baut mit Quartus 13.0sp1. Kein `else generate`
  (VHDL-2008), und kein `numeric_std` neben `std_logic_unsigned` im Top-Level – die Operatoren
  würden mehrdeutig.
- **Nach jeder Änderung an `rtl/common/` oder `top/`: `scripts\check.ps1 -Fit`.** Das vergleicht
  LE/Memory/Slack gegen `scripts\baseline.csv`. Eine unerklärte Abweichung ist ein Befund.
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
rtl/serial_api/  USB-Monitor-API (Option 'serial_api')
rtl/sound/       Soundkarten-Module (Option 'sound', nur die ruhenden Varianten)
top/WillFA7.vhd  DAS Top-Level
variants/<name>/ variant_pkg.vhd · device.tcl · pins.tcl · variant.psd1 ·
                 WillFA7.sdc · WillFA7.qpf · willfa7.cof · WillFA7.qsf (generiert)
scripts/         gen_qsf.ps1 · check.ps1 · build.ps1 · release.ps1 · files_*.tcl · baseline.csv
bin/             Release-Binaries + changelog.txt
docs/            Analysen (Switch-Masken, Blanking, EEprom, Spezialsolenoide)
archive/         historische Modulstaende, in keinem Build
```

## Die sieben Varianten

| `variants/<name>` | Version | FPGA | Quartus | Stand |
|---|---|---|---|---|
| `cyclone_ii` | 1.21 | EP2C5T144C8 | **13.0sp1** | aktiv, 94 % LE |
| `cyclone_iv_v3` | 2.21 | EP4CE6F17C8 | 22.1std | aktiv, mit USB-Monitor-API |
| `cyclone_iv_v4` | 3.21 | EP4CE6E22C8 | 22.1std | aktiv, **Leitvariante** |
| `cyclone_10` | 4.21 | 10CL006YE144C8G | 22.1std | aktiv |
| `cyclone_iv_dev_open` | 5.21 | EP4CE6E22C8 | 22.1std | aktiv, Aliexpress-Devboard |
| `s_cyclone_iv_v4` | 6.03 | EP4CE10E22C8 | 22.1std | **ruht**, mit Soundkarte |
| `s_cyclone_10` | 7.14 | 10CL010YE144C6G | 22.1std | **ruht**, unfertig |

Angezeigte Version = `BOARD_ID.SW_SUB1 SW_SUB2`. Erste Stelle aus
`variants/<name>/variant_pkg.vhd`, die beiden anderen aus `rtl/common/version_pkg.vhd`.
Ein Release ändert **eine** Zahl.

**Hardware-Teststand: nur 3.20 war getestet.** `.21` ist auf keinem Board getestet.
Die beiden S-Varianten bauen nicht (Gründe in `VARIANTEN.md`).

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

## Was pro Variante variiert

`variants/<name>/variant_pkg.vhd`:

| Konstante | Bedeutung |
|---|---|
| `BOARD_ID` | erste Stelle der Versionsanzeige |
| `ROM_COUNT` | 5 oder 6 ROM-Bloecke à 2K. **Bestimmt auch das SD-Kartenformat**: 5 = 10-KByte-Image ab 5800h, 6 = 12-KByte-Image ab 5000h. Ein falscher Wert bricht nicht den Build, sondern das Spiel beim Booten. |
| `HAS_MONITOR` | USB-Monitor-API, ca. 550 LE |

`variants/<name>/variant.psd1` (von den Skripten gelesen): `RtlFamily`, `Options`,
`VirtualPins`, `BinFolder`, `ReleaseArtifact`, `Dormant`.

### Optionale Ports

`LED_debug`, `USB_Tx`, `USB_Rx` und `debug` stehen in **jeder** Portliste. Boards ohne den Pin
bekommen `VIRTUAL_PIN` aus `variant.psd1`. Das ist keine Kosmetik: ein deklarierter
Ausgangsport ohne Location ist für Quartus ein *benutzter* Pin, `RESERVE_ALL_UNUSED_PINS`
greift dort nicht, und er würde irgendwo auf der Platine platziert und getrieben.

### `.sdc` bleibt pro Variante

`cyclone_iv_v3`, `cyclone_10` und `cyclone_iv_dev_open` sind byte-identisch zu `cyclone_iv_v4`.
**Cyclone II ist ein echter Fork** (von Quartus 13 generiert, andere PLL-Hierarchienamen).
Nicht zusammenlegen.

Die `.sdc` referenzieren `cpu_clk_gen:clock_gen`, `flipflops:FF_SOLS`, `flipflops:FF_LAMPSS`
und `PLL`. **Diese vier Instanzen nie in ein Generate wickeln** – Generate-Labels ändern den
Quartus-Hierarchienamen und die Constraints brechen stumm.

## Architektur

**Top-Level-Entity:** `WillFA7` in `top/WillFA7.vhd`

| Modul | Datei | Zweck |
|---|---|---|
| cpu68 | `rtl/common/cpu68.vhd` | Motorola 6800/6801 (OpenCores, John E. Kent, GPL), v0.85 |
| pia6821 | `rtl/common/pia6821.vhd` | PIA, 5 Instanzen |
| SD_Card | `rtl/common/SD_Card.vhd` | SPI-SD-Controller, lädt die Spiel-ROMs |
| EEprom | `rtl/common/EEprom.vhd` | SPI-EEPROM (M95256 / M95512), Spielstand |
| williams_pll | `rtl/<familie>/williams_pll.vhd` | 50 MHz → 14,28 MHz |
| ram / rom_2K / R5101 | `rtl/<familie>/` | System-RAM, ROM-Bloecke, CMOS-RAM |
| boot_message | `rtl/common/boot_message.vhd` | Boot-/Diagnoseanzeige |
| read_the_dips | `rtl/common/read_the_dips.vhd` | Spielauswahl über DIPs |
| flipflops | `rtl/common/flipflops.vhd` | Flipper-Solenoide |
| spec_sol_trigger | `rtl/common/spec_sol_trigger.vhd` | Spezialsolenoid-Trigger mit Entprellung |
| sw_debounce | `rtl/common/sw_debounce.vhd` | Switch-Matrix-Entpreller, Maske je Spiel |

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

## LED-Ausgänge sind keine LEDs

`LED_active` ist die **Blanking-Leitung** der Treiberplatine (IC13 74HCT240 `/OE` für die
Switch-Strobes plus `/RESET` der fünf 74HCT273-Latches), `LED_status` ist das Display-Blanking.
Nie für Status- oder Fehleranzeigen umwidmen – genau das war die `.17`–`.19`-Regression, siehe
`docs/blanking_led_active.md`. Nur `LED_SD_Error` ist eine echte LED.

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
| `SS_R` (SD_Card), `RX_Data_W` / `RX_Data_Cmd` (EEprom) | Altbestand in den Modulen |
| `wr_rom0` never read (nur `cyclone_ii`) | rom0 ist per `ROM_COUNT` weggeneriert |
| `parameter` (WillFA7_Monitor, nur `cyclone_iv_v3`) | Altbestand im Monitor |

## Historie und Altbestand

`VARIANTEN.md` beschreibt Stand, bekannte Defekte und Hardware-Teststand jeder Variante.
`PLAN_Zielstruktur.md` ist die Begründung für diese Struktur (Etappe 1 und 2 umgesetzt).
Der alte Ordnerbaum liegt weiterhin unter `N:\Projekte\WillFA\FPGA_source\` als Fallback,
zusammen mit `archive src\` (rund 630 MB historische Projektstände, bewusst nicht im Repo).
