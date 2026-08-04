# Digit-Strobes: 6-stellige und 7-stellige Player-Displays

Betrifft `rtl/common/boot_message.vhd` und alles, was der FPGA **selbst** auf die Anzeige
schreibt, also Bootmeldung und Soundtest. Sobald das Spiel läuft (Bootphase 3), macht das
Spiel-ROM die Strobes und diese Datei ist gegenstandslos.

## Die Hardware

Die MPU treibt vier Adressleitungen (`disp_strobe`) und acht Datenleitungen (`disp_bcd`).
Ein 74154 dekodiert den Strobe auf 16 Digit-Leitungen; das **obere** Nibble der Daten geht
an Player 1 und 2, das **untere** an Player 3 und 4. Welche physische Stelle eine
Strobe-Nummer anspricht, hängt am Displaytyp – und nur daran.

## Die Belegung

| Strobe | 6-stellig, oberes Nibble | 6-stellig, unteres | 7-stellig, oberes | 7-stellig, unteres |
|---|---|---|---|---|
| 0 | Player 1, Stelle 1 | Player 3, Stelle 1 | **Status rechts, Zehner** | **Status links, Zehner** |
| 1 | Player 1, Stelle 2 | Player 3, Stelle 2 | Player 1, Stelle 1 | Player 3, Stelle 1 |
| 2 | Player 1, Stelle 3 | Player 3, Stelle 3 | Player 1, Stelle 2 | Player 3, Stelle 2 |
| 3 | Player 1, Stelle 4 | Player 3, Stelle 4 | Player 1, Stelle 3 | Player 3, Stelle 3 |
| 4 | Player 1, Stelle 5 | Player 3, Stelle 5 | Player 1, Stelle 4 | Player 3, Stelle 4 |
| 5 | Player 1, Stelle 6 | Player 3, Stelle 6 | Player 1, Stelle 5 | Player 3, Stelle 5 |
| 6 | **Status rechts, Zehner** | – | Player 1, Stelle 6 | Player 3, Stelle 6 |
| 7 | **Status rechts, Einer** | – | Player 1, Stelle 7 | Player 3, Stelle 7 |
| 8 | Player 2, Stelle 1 | Player 4, Stelle 1 | **Status rechts, Einer** | **Status links, Einer** |
| 9 | Player 2, Stelle 2 | Player 4, Stelle 2 | Player 2, Stelle 1 | Player 4, Stelle 1 |
| 10 | Player 2, Stelle 3 | Player 4, Stelle 3 | Player 2, Stelle 2 | Player 4, Stelle 2 |
| 11 | Player 2, Stelle 4 | Player 4, Stelle 4 | Player 2, Stelle 3 | Player 4, Stelle 3 |
| 12 | Player 2, Stelle 5 | Player 4, Stelle 5 | Player 2, Stelle 4 | Player 4, Stelle 4 |
| 13 | Player 2, Stelle 6 | Player 4, Stelle 6 | Player 2, Stelle 5 | Player 4, Stelle 5 |
| 14 | **Status links, Zehner** | – | Player 2, Stelle 6 | Player 4, Stelle 6 |
| 15 | **Status links, Einer** | – | Player 2, Stelle 7 | Player 4, Stelle 7 |

Stelle 1 ist jeweils die **linke**. „Status" ist die vierstellige Credit-/Ball-Anzeige.

Der wesentliche Unterschied steckt nicht in der Verschiebung der Spielerstellen, sondern
in der Statusanzeige: 6-stellig liegen alle vier Statusziffern auf dem **oberen** Nibble
(Strobe 6, 7, 14, 15), das untere Nibble ist dort unbeschaltet. 7-stellig bleiben nur zwei
Strobes übrig (0 und 8), und die vier Ziffern verteilen sich auf **beide** Nibbles: oberes
Nibble ist das rechte Paar, unteres das linke.

## Quellen

Drei unabhängige Quellen, die sich decken:

| Quelle | Datei | was sie sagt |
|---|---|---|
| PinMAME, System 6 | `src/wpc/s6.c`, `s6_6digit_disp` / `s6_7digit_disp` | beide Layouts nebeneinander |
| PinMAME, System 7 | `src/wpc/s7games.c`, `s7_dispS7` | dasselbe 7-stellige Layout als Default |
| LISY | `src/lisy/lisy_w.c`, `t_mysegments` | Segmentindizes mit Kommentaren `//1..7`, `//21..27` |

PinMAME schreibt das obere Nibble nach `segments[strobe]`, das untere nach
`segments[20+strobe]` (`s6_alpha_w`, `pia3b_w`). Damit lassen sich die Layout-Tabellen
direkt in Strobe-Nummern übersetzen.

Vorsicht bei den **Beschriftungen** in PinMAME: `s6_6digit_disp` nennt Position 14/15
„Right Side" und 6/7 „Left Side", rendert sie aber genau umgekehrt (Spalte 9 gegen Spalte
14), und `s6_7digit_disp` gegen `s7_dispS7` vertauschen „Credits" und „Balls". Konsistent
über alle Quellen ist nur die **Seite**: die Positionen 0/8 des oberen Nibbles stehen
rechts, die des unteren links – und für 6-stellig steht 14/15 links, 6/7 rechts, was durch
die Anzeige der Soundkarten-Optionen auf der S-Platine hardwarebestätigt ist (`CLAUDE.md`).

## Welches Spiel hat welches Display

Tabelle in `rtl/common/game_pkg.vhd`, Funktion `has_7digit`. Kurz:

| Spielnummer | Spiele | Display | Quelle |
|---|---|---|---|
| 0–15 | Hot Tip … Scorpion (SYS3, SYS4, SYS6) | 6-stellig | PinMAME-Default für s4/s6 |
| 16–17 | Algar, Alien Poker (SYS6A) | **7-stellig** | `s6games.c`, `INITGAMEFULL(algar/alpok, s6_7digit_disp, …)` |
| 18–31 | Black Knight … Star Light (SYS7) | 7-stellig | `s7games.c`, Default `s7_dispS7` |

Williams stellte mit den beiden letzten System-6-Spielen um; deshalb führen die Handbücher
sie in Anhang A schon als eigenen Typ `SYS6A`.

**Noch nicht auf Hardware geprüft: 16 und 17.** Alien Poker ist das Referenzgerät dieses
Projekts, und dort ist bisher keine verschobene Bootmeldung aufgefallen. Falls sich das
Gerät als 6-stellig herausstellt, sind es zwei Zeichen in `DISP_7DIGIT`.

Wer eine 7-stellig-Umbau-ROM auf einen Slot legt, der hier als 6-stellig geführt ist
(es gibt solche Sätze für Firepower), ändert ebenfalls nur das eine Zeichen.

## Was die Bootmeldung daraus macht

`boot_message.vhd` durchläuft immer 16 Zeitschlitze. `strobe_of()` bildet den Schlitz auf
die Strobe-Nummer ab:

- **6-stellig:** Strobe = Schlitznummer. Unverändert gegenüber allen Ständen bis `.22`.
- **7-stellig:** die sechs Zeichen gehen zwei Strobes höher (2…7 und 10…15), stehen damit
  **rechtsbündig**, und die linke Stelle bleibt dunkel. Schlitz 6 und 7 gehen auf Strobe 0
  und 8 und tragen jeweils zwei Statusziffern, eine pro Nibble. Schlitz 14 und 15 haben
  nichts mehr zu zeigen und werden dunkel getastet – sie adressieren weiterhin Strobe 0
  und 8, damit diese Stellen genauso hell sind wie die Spielerstellen und nicht doppelt.

Reihenfolge innerhalb eines Paares: Zehner links, Einer rechts. Auf der S-Platine stehen
damit weiterhin die Soundkarten-Optionen links und die Spieloptionen rechts.
