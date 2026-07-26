# Switch-Debounce-Masken aller 32 WillFA7-Spiele

Ergaenzung zu `switch_debounce_analysis.md`. Dort steht das **Warum** (ROM-eigene
2-Read-Debounce, Confirm-Read-Problematik, warum globale Filter scheitern), hier steht
das **Was**: die konkrete Maske je Spiel und wie sie zustande kam.

Ab v3.20 ist die Maske in `lib_common/sw_debounce.vhd` nicht mehr fest verdrahtet,
sondern wird ueber die Spielnummer (`not game_select`, identisch zur `selection` von
SD-Card und EEprom) aus `MASK_ROM` gewaehlt. Ein freilaufender Refresh-Zaehler kopiert
die acht Spaltenbytes des aktiven Spiels nach `cur_mask`; der Lesepfad bleibt
kombinatorisch, also ohne zusaetzliche Latenz.

## Konvention

Aus der Switch-Nummer-Berechnung des ROMs (`$7EDD-$7EEA`) verifiziert:

    Switch-Nr = 8 x Strobe-Bit + Return-Bit + 1      (beide 0-basiert)

Maskenbit `n` von Spaltenbyte `c` gilt also fuer Switch `8*c + n + 1`.
**`1` = entprellen, `0` = Rohsignal durchreichen.**

## Klassifikationsregel

Vorrang: **STANDUP > DROP > uebrige RAW-Muster > uebrige DEB-Muster.**
Ein "... Drop Target Standup" ist der separate Standup-Kontakt an einer Drop-Bank und
damit ein reiner Momentschalter, nicht das versenkbare Target selbst. Das betrifft 24
Switches in 10 Spielen (u. a. Gorgar sw22/sw40, Pokerino sw22/sw45/sw46, Phoenix
sw22/sw24, Laser Ball sw39/sw48, Stellar Wars sw20/sw35) und deckt sich mit Alien Poker
sw41 "5 BANK STANDUP", der hardwarebestaetigt entprellt wird.

**RAW (Rohsignal)** - Switches, bei denen zusaetzliche Oeffnungs-Latenz das Spiel bricht
oder die zu schnell wiederholen:
Outhole, Trough, Drop-Targets, Eject-Loecher, Kicker, Saucer, Ball-Locks, Ball-Ramps,
Ball-Shooter, Magnete, Spinner, Jet-Bumper, Slingshots.

**DEBOUNCED** - reine Momentschalter ohne Confirm-Read:
Stand-up-Targets, Rollover, Lanes/Outlanes, Bull's-Eye-Targets, Specials, Lane-Change,
Kabinett (Tilts, Muenzen, Credit, Slam, High-Score-Reset).

Die Regel ist am hardwarebestaetigten Alien-Poker-Satz kalibriert und reproduziert ihn
**bitgleich**. Gegengeprueft an Black Knight, wo sie exakt die Switch-Definitionen des
PinMAME-Simulators (`src/wpc/sims/s7/full/bk.c`) trifft.

## Quellen und Konfidenz

| Tag | Bedeutung |
|---|---|
| `[HW ]` | auf echter Hardware bestaetigt (nur Alien Poker) |
| `[HB+]` | Switch-Namen aus einem Original-Handbuchblatt **und** ROM-Gegenprobe |
| `[ROM]` | Switch-Namen aus der Datenbank **und** Gegenprobe gegen die Handler-Gruppen des Spiel-ROMs |
| `[HB ]` | Switch-Namen aus einem Original-Handbuchblatt, keine ROM-Gegenprobe |
| `[MTX]` | nur Switch-Namen aus der Datenbank, keine ROM-Gegenprobe |

Die Switch-Namen stammen ueberwiegend aus der Pinitech-Switch-Matrix-Datenbank
(`pinitech.com/switch_database.php`). Elf Spiele kommen aus Original-Handbuchblaettern
und haben damit die bessere Quelle. Wo beide auseinanderlaufen, gilt das Handbuchblatt;
das war bisher dreimal der Fall:

- **Contact** (`docs/Contact_switchmatrix.png`) - die Datenbank fuehrt Spalte 1
  faelschlich komplett als "not used". Tatsaechlich ist sie regulaer belegt (Plumb Bob
  Tilt, Ball Roll Tilt, Credit Button, drei Muenzschalter, Slam Tilt). Betrifft nur
  Spaltenbyte 1 der Maske (`00` -> `7F`); die Playfield-Schalter 09-40 waren korrekt.
- **Phoenix** (`docs/Phoenix_switchmatrix.png`) - die Datenbank fuehrt sw27 und sw43 als
  "not used". Tatsaechlich sind beide Drop Targets; jede der beiden Banks hat vier
  Targets, nicht drei. Das ROM bestaetigt es: 25/26/27/28 und 41/42/43/44 teilen sich
  alle acht den Handler `$619E`. **Ohne Maskenaenderung** - "not used" und "Drop Target"
  fuehren beide auf `0` (roh).
- **Stellar Wars** (`docs/Stellar_Wars_switchmatrix.png`) - die Datenbank fuehrt sw34
  *und* sw35 als "Series". Laut Handbuch ist sw34 die Series und sw35 der **Standup**
  der rechten 3-Bank; beide 3-Banks sind damit symmetrisch (16/17/18 + 19 Series +
  20 Standup links, 31/32/33 + 34 Series + 35 Standup rechts). **Maskenaenderung:**
  Spaltenbyte 5 `28` -> `2C`, sw35 wird nach der STANDUP-Regel entprellt.

**Laser Ball** (`docs/Laser_Ball_Switchmatrix.jpg`) ist in der Datenbank gar nicht
enthalten und stammt ausschliesslich aus dem Handbuchblatt.

Gescannt vorliegend sind Hot Tip, Lucky Seven, World Cup, Contact, Disco Fever,
Pokerino, Phoenix, Flash, Stellar Wars, Laser Ball und Scorpion. Die Scans selbst liegen
nur lokal in `docs/` und sind per `.gitignore` vom Repository ausgenommen; im Repo steht
ausschliesslich die daraus abgeleitete Textform.

Aufbereitete Matrizen aller 32 Geraete im MediaWiki-Format: `switch_matrix/`.

Die ROM-Gegenprobe nutzt die Dispatch-Tabelle der System-6-Codebasis (`$60F1`,
4 Bytes/Switch: Handler-Adresse + Datenzeiger). Switches mit gemeinsamem Handler gehoeren
funktional zusammen; eine Gruppe wird einheitlich klassifiziert. Das schliesst zwei
Luecken der Namensquelle:
- Targets, die die Matrix nicht als "Drop" benennt (Firepower "1".."6" TARGET,
  Blackout GREEN TARGET #1..#5, Algar CENTER 3-BANK ... TARGET),
- Switches, die in der Matrix ganz fehlen (Firepower sw56, Scorpion sw29).

## Die vier ROM-Codebasen

Alle vier benutzen denselben schwachen 2-Read-Filter (`stabil = roh AND roh_vorher`) bei
~2 ms Scan-Takt - die Debounce-Problematik ist ueber alle Spiele identisch.

| Basis | Scan-Routine | Dispatch | Spiele |
|---|---|---|---|
| SYS3/4 | `LDAA $3000` @ `$70D5` | `$609C`, 2 B/Switch | 0-6 |
| SYS6 | `LDAA $3000` @ `$7EBD` | `$60F1`, 4 B/Switch | 7, 9-17 |
| SYS6-Var | `$7EA5` | `$60DF` | 8 (Stellar Wars) |
| SYS7 | `EORA $3000` @ `$70E3` | Bytecode-Interpreter | 18-31 |

SYS7 hat zusaetzlich eine per-Spalte Invert-Maske (`$61..$68`) fuer Ruhekontakte. Seine
Spiellogik laeuft ueber einen Bytecode-Interpreter, weshalb dort keine
Handler-Gruppen-Gegenprobe moeglich war (Tag `[MTX]`).

## Maskentabelle

| # | Spiel | Sys | Quelle | Col1..Col8 | RAW-Switches |
|---|---|---|---|---|---|
| 0 | Hot Tip | SYS3 | `[HB ]` | `7F 2E D8 88 03 00 00 00` | 9, 13, 15, 16, 17, 18, 19, 22, 25, 26, 27, 29, 30, 31, 35, 37 |
| 1 | Lucky Seven | SYS3 | `[HB ]` | `7F 1F 3E 7C F4 01 02 00` | 14, 15, 16, 17, 23, 24, 33, 34, 36 |
| 2 | World Cup | SYS3 | `[HB ]` | `7F 4E F7 FE 0F 00 00 00` | 9, 13, 14, 16, 20, 25, 37, 38 |
| 3 | Contact | SYS3 | `[HB ]` | `7F FD F7 81 F8 00 00 00` | 10, 20, 26, 27, 28, 29, 30, 31, 33, 34, 35 |
| 4 | Disco Fever | SYS3 | `[HB ]` | `7F FB 86 2F 86 00 00 00` | 11, 17, 20, 21, 22, 23, 29, 33, 38, 39 |
| 5 | Pokerino | SYS4 | `[HB+]` | `FF FD E0 C4 10 3D 00 00` | 10, 17, 18, 19, 20, 21, 25, 26, 28, 29, 30, 33, 34, 35, 36, 38, 39, 40, 42 |
| 6 | Phoenix | SYS4 | `[HB+]` | `FF 3F FC C0 E0 C0 00 00` | 15, 16, 17, 18, 25, 26, 27, 28, 29, 30, 33, 35, 37, 41, 42, 43, 44, 45, 46 |
| 7 | Flash | SYS4 | `[HB+]` | `FF FF F0 03 E0 7C 00 00` | 17, 18, 19, 20, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 41, 42, 48 |
| 8 | Stellar Wars | SYS4 | `[HB+]` | `FF 0E C8 3E 2C 87 01 00` | 9, 13, 14, 16, 17, 18, 19, 21, 22, 25, 31, 32, 33, 34, 37, 40, 44, 45, 46, 47, 50, 51, 52, 53, 54 |
| 9 | Tri Zone | SYS6 | `[ROM]` | `FF 0E 77 9C 02 00 00 00` | 9, 13, 14, 15, 16, 20, 24, 25, 26, 30, 31, 33, 35 |
| 10 | Time Warp | SYS6 | `[ROM]` | `FF BE 03 C0 F0 0C 00 00` | 9, 15, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 33, 34, 35, 36, 41, 42 |
| 11 | Gorgar | SYS6 | `[ROM]` | `FF B6 A1 DF 87 00 00 00` | 9, 12, 15, 18, 19, 20, 21, 23, 30, 36, 37, 38, 39, 41, 42, 43, 44 |
| 12 | Laser Ball | SYS6 | `[ROM]` | `FF AC 02 7F 41 86 FF 07` | 9, 10, 13, 17, 19, 20, 21, 22, 23, 24, 32, 34, 35, 36, 37, 38, 40, 41, 44, 45, 46, 47 |
| 13 | Firepower | SYS6 | `[ROM]` | `FF A6 00 D0 37 DC 03 00` | 9, 12, 13, 15, 17, 18, 19, 21, 22, 23, 25, 26, 27, 28, 30, 36, 39, 40, 41, 42, 46, 51, 53, 54, 57, 58 |
| 14 | Blackout | SYS6 | `[ROM]` | `FF 02 0C F0 20 33 00 00` | 9, 11, 12, 13, 14, 15, 18, 21, 22, 23, 25, 26, 27, 28, 33, 34, 35, 36, 37, 39, 40, 43, 44 |
| 15 | Scorpion | SYS6 | `[ROM]` | `FF 70 1F 00 00 FF FF 01` | 9, 10, 11, 12, 16, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40 |
| 16 | Algar | SYS6A | `[ROM]` | `FF 1C DA ED 13 34 1E 00` | 9, 10, 14, 15, 16, 17, 19, 22, 26, 29, 35, 36, 38, 39, 40, 41, 42, 44, 47, 48, 49 |
| 17 | Alien Poker | SYS6A | `[HW ]` | `FF AC DC ED C1 05 00 00` | 9, 10, 13, 15, 17, 18, 22, 26, 29, 34, 35, 36, 37, 38, 42 |
| 18 | Black Knight | SYS7 | `[MTX]` | `FF CC 40 00 00 20 00 00` | 9, 10, 13, 14, 17, 18, 19, 20, 21, 22, 24, 25, 26, 27, 29, 30, 31, 33, 34, 35, 36, 37, 38, 39, 41, 42, 43, 44, 45 |
| 19 | Jungle Lord | SYS7 | `[MTX]` | `FF F0 FF 80 00 79 00 00` | 9, 10, 12, 25, 26, 27, 28, 29, 30, 31, 33, 34, 35, 36, 37, 38, 39, 40, 42, 43, 49, 50 |
| 20 | Pharaoh | SYS7 | `[MTX]` | `FF F0 00 88 00 02 00 00` | 9, 10, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 29, 30, 31, 33, 34, 35, 36, 38, 39, 40, 41, 43, 44 |
| 21 | Solar Fire | SYS7 | `[MTX]` | `FF F0 00 01 80 06 00 00` | 9, 10, 11, 12, 17, 18, 19, 20, 21, 22, 23, 24, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 41 |
| 22 | Barracora | SYS7 | `[MTX]` | `FF 01 C7 CE FF 00 00 00` | 10, 11, 12, 13, 14, 15, 16, 20, 21, 22, 25, 29, 30, 41, 42, 43, 44, 45, 46, 47, 48 |
| 23 | Cosmic Gunfight | SYS7 | `[MTX]` | `FF FF 0E E0 67 00 0B 00` | 21, 22, 23, 24, 25, 26, 27, 28, 29, 36, 37, 40, 41, 42, 43, 44, 45, 46, 47, 48, 51 |
| 24 | Varkon | SYS7 | `[MTX]` | `FD F1 FF 7F F8 00 00 00` | 10, 32, 33, 34, 35, 41 |
| 25 | Warlok | SYS7 | `[MTX]` | `FF 80 C7 03 78 00 00 00` | 9, 10, 11, 12, 13, 14, 15, 20, 21, 22, 27, 28, 29, 30, 31, 32, 33, 34, 35 |
| 26 | Time Fantasy | SYS7 | `[MTX]` | `FF FF FF FF 88 03 00 00` | 33, 34, 35, 37, 38, 39 |
| 27 | Joust | SYS7 | `[MTX]` | `FD 00 38 40 00 38 40 01` | 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 23, 24, 25, 26, 27, 28, 29, 30, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 47, 48, 49, 50, 51, 52, 53, 54, 58, 59, 60, 61 |
| 28 | Firepower II | SYS7 | `[MTX]` | `FF 90 AD FF 7F 30 01 00` | 9, 10, 11, 12, 14, 15, 18, 23, 40, 41, 42, 43, 44, 47, 48 |
| 29 | Laser Cue | SYS7 | `[MTX]` | `FF CE 78 FF FF 06 00 00` | 9, 17, 18, 19, 24, 41 |
| 30 | Defender | SYS7 | `[MTX]` | `FF 0F 1C 70 38 01 3C 5C` | 13, 14, 15, 16, 17, 23, 24, 25, 26, 27, 33, 34, 35, 39, 40, 42, 43, 44, 45, 46, 47, 48, 49, 50, 55, 56, 57, 58 |
| 31 | Star Light | SYS7 | `[MTX]` | `FF F0 FF FE FF F8 31 00` | 9, 10, 11, 12, 25, 41, 42, 43, 50, 51, 52 |

## Offene Punkte

- **Laser Ball (12)** wurde aus dem Original-Handbuchblatt nachgetragen. Die
  ROM-Handler-Gruppen bestaetigen die Klassifikation unabhaengig: `$635C` x10 =
  Star-1..10-Rollover (alle entprellt), `$630F` x5 = die Doppel-Rollover
  "1"&"2".."9"&"10" (alle entprellt), `$6380` x2 = Left/Right Shooter (beide roh) -
  jede Gruppe einheitlich.
- **31 Spiele sind ungetestet.** Klassifiziert wurde nach bester Schaetzung. Faellt bei
  einem Spiel ein Auswurf doppelt aus oder desynchronisiert eine Drop-Bank, ist mit hoher
  Wahrscheinlichkeit ein Level-Switch faelschlich als entprellt eingestuft. Sofortmassnahme:
  **DIP5 OFF** - das schaltet global auf v3.17 zurueck. Danach den betreffenden Switch in
  der Tabelle auf `0` setzen.
- Die Fehlerrichtung ist asymmetrisch: ein faelschlich **roh** gelassener Momentschalter
  kostet nur die Entprellung (heutiges Verhalten), ein faelschlich **entprellter**
  Level-Switch bricht dagegen den Confirm-Read.
