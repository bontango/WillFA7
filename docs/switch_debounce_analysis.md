# Switch-Debounce-Analyse: Original-ROM vs. WillFA7-Emulation

**Ziel:** die originale Williams-System-7 Switch-Debounce im ROM identifizieren und
daraus belegen, warum die FPGA-Emulation anders reagiert als die echte CPU — insbesondere
warum jede zusätzliche FPGA-Debounce-Schicht die Drop-Target-Bänke und die Outhole bricht,
während das rohe Durchreichen (v3.17) sie einwandfrei laufen lässt.

**Analysebasis:** `roms/alpoker.bin` (Williams *Alien Poker*, System 7), 12 KB = 6×2 K,
CPU-Basis `$5000`, oberste 2 K auf `$F800–$FFFF` gespiegelt. Disassembliert mit einem
eigenen MC6800-Disassembler (Trace ab RESET `$7000`, IRQ `$60EE`→`JMP $6711`, NMI `$7BE0`).

---

## TL;DR (die Kernaussagen)

1. **Es gibt genau EINEN Switch-Lesepunkt im gesamten ROM** — die Scan-Routine bei
   `$7EB7–$7EDA` (PIA2 `$3000/$3002`). Ein Byte-Scan über das komplette Image findet
   keinen zweiten. **Jede** Spielentscheidung — auch die „Coil feuern → Zustand
   nachlesen"-Prüfungen von Bank-Reset und Outhole — liest aus **RAM-Tabellen**, die diese
   eine Routine pflegt. Es gibt keinen separaten Sofort-Read.

2. **Die Original-Debounce ist ein sehr schwacher 2-Read-Filter:** ein Schalter muss in
   **zwei aufeinanderfolgenden Scans** derselben Spalte geschlossen gelesen werden
   (`stabil = roh AND roh_vorher`), dann wird **einmalig** ein Schließ-Ereignis (Switch-
   Nummer) in eine 3-Slot-Queue `$0034/$35/$36` gelegt. Re-Arm braucht **einen** offenen
   Scan. Bei ~2 ms/Scan ist das Fenster nur **~2 ms**.

3. **Timing ist identisch zur echten HW:** CPU ≈ 892,5 kHz, IRQ ≈ 1 kHz, Matrix-Scan jeden
   2. IRQ ≈ alle 2 ms. Die Divergenz liegt **nicht** am Takt und **nicht** am Algorithmus,
   sondern an der **Signal-Aufbereitung** der Return-Leitungen.

4. **Fundamentaler FPGA-Constraint:** Weil das ROM den Strobe besitzt, sieht das FPGA jeden
   Schalter **nur einmal pro ~2-ms-Scan**. Jeder matrix-aware Filter fügt daher Latenz in
   **ganzen Scans** hinzu. Die Confirm-Read-Schalter (Drop-Targets, Outhole) prüfen die
   **Öffnungs**-Flanke innerhalb von ~1–2 Scans nach dem Coil-Puls und haben **kein**
   Latenz-Budget über die ROM-eigene Debounce hinaus. Deshalb bricht **jede** FPGA-Debounce
   (N-of-N, Lockout, Integrator, v3.18) genau diese Schalter — der Integrator addierte
   ~4 Scans ≈ **~8 ms** Öffnungs-Latenz.

5. **Momentschalter-Mehrfachtrigger (rohes v3.17)** ist die Kehrseite: der 2-Read-Filter
   verwirft nur Einzel-Scan-Glitches. Ein harter Treffer, dessen Kontakt über mehrere
   Scans hinweg schließt/öffnet/schließt, wird vom ROM mehrfach als Schließ-Ereignis
   registriert. Die echte 6821-/Driverboard-Analogstrecke verschleift diese Chatter-Flanken
   so weit, dass das ROM eine saubere Schließphase sieht; der scharfe FPGA-Eingang tut das
   nicht.

**Konsequenz:** Momentschalter-Entprellung und Confirm-Read-Treue sind auf dem FPGA
grundsätzlich in Konflikt, solange man beide über **einen** Filter behandelt. Williams
selbst löst das per **Schaltertyp** (s. u.) — das ist der Weg, nicht ein globaler Filter.

---

## 1. Die Scan-/Debounce-Routine (`$7EB5–$7F06`)

Aufgerufen aus dem IRQ-Handler `$6711` → `JMP $7E9D` (Display-Multiplex) → Switch-Scan bei
`$7EAC`, gegated auf **ungerades `$7D`** (Digit-Zähler) ⇒ **jeder 2. IRQ**. Zusätzliche
Gates: `$78 = $FF` (Scan aus) und `$7A ≠ 0` (Lockout-Countdown).

```
; --- Spalten-Scan: alle 8 Spalten in einem Durchlauf ---
7EB5: LDAA #$80        ; Strobe = Spalte 7 (%10000000)
7EB7: STAA $3002       ; PIA2 PB  -> SW_STROBE
7EBA: LDX  #$0024      ; X -> CUR-Tabelle ($0024..$002B)
7EBD: LDAA $3000       ; PIA2 PA  <- SW_RETURN (8 Zeilen dieser Spalte)   <<< EINZIGER READ
7EC0: BNE  $7ECC       ; irgendein Schalter zu? -> Verarbeitung
7EC2: STAA $00,X       ; sonst CUR[Spalte] = 0
7EC4: LSR  $3002       ; Strobe eins weiter (>>1)
7EC7: INX
7EC8: BCC  $7EBD       ; solange '1' nicht rausgeschoben -> nächste Spalte
7ECA: BRA  $7F08       ; fertig

; --- 2-Read-Debounce + Schließ-Erkennung (Spalte hat >=1 geschlossenen Schalter) ---
7ECC: TAB              ; B = roh
7ECD: ANDA $00,X       ; A = roh AND CUR_alt      = "stabil" (zu jetzt UND vorher)
7ECF: STAB $00,X       ; CUR = roh                (neuen Rohwert merken)
7ED1: TAB              ; B = stabil
7ED2: COMA             ; A = ~stabil
7ED3: ORAA $08,X       ; A = ~stabil OR DEB_alt   (DEB = $002C..$0033)
7ED5: STAB $08,X       ; DEB = stabil
7ED7: COMA             ; A = stabil AND ~DEB_alt  = "NEU geschlossen"
7ED8: BEQ  $7EC4       ; nichts neu -> nächste Spalte
7EDA: LDAB $3002       ; Strobe lesen -> Spaltennummer bestimmen
7EDD..7EEA:            ; Switch-Nummer = f(Spalte, Zeile), 0..63
7EEB: CMPA $6044       ; > MaxSwitch ($6044 = $2B = 43)?
7EEE: BHI  $7F04       ;   ja -> NICHT einreihen
7EF0: TST $0034 / STAA $34   ; sonst in Schließ-Queue Slot 0/1/2 ($0034/$35/$36)
   ... $0035 / $0036 ...
7F04: DECA / TSTB / BNE $7EE6 ; weitere neue Zeilen dieser Spalte
```

**Merkmale:**
- Der Filter verwirft nur **Einzel-Scan-Glitches** (ein „stabil" verlangt roh *und*
  roh_vorher). Ein Schließ-Ereignis entsteht **einmalig** beim Übergang `stabil ∧ ¬DEB`.
- **Re-Arm:** DEB wird beim ersten geschlossenen Read nach einer offenen Phase auf 0
  gerechnet (`stabil = roh ∧ CUR_alt`, CUR_alt=0). Also: Schalter muss **≥1 Scan offen**
  gewesen sein, dann **≥2 Scans geschlossen**, um erneut zu zählen.
- **Kein separater Sofort-Read** irgendwo (per Byte-Scan bestätigt): Confirm-Reads von
  Bank/Outhole lesen zwangsläufig die untenstehenden RAM-Tabellen.

## 2. RAM-Map der Switch-Tabellen

| Adresse        | Bedeutung |
|----------------|-----------|
| `$0024–$002B`  | **CUR** — letzter Rohwert je Spalte (Latenz **1 Scan**, quasi „aktueller Zustand") |
| `$002C–$0033`  | **DEB** — 2-Read-entprellt je Spalte (Latenz **2 Scans**) |
| `$0034/$35/$36`| **Schließ-Queue** — bis zu 3 neue Switch-Nummern für die Main-Loop |
| `$0038/$0039`  | Solenoid-Timer / -Auswahl (IRQ-Solenoid-Treiber, Ausgabe nach `$2200`) |
| `$7C/$7D/$79`  | Display-Digit-Zähler / Multiplex-Phase |
| `$78/$7A`      | Scan-Enable (`$FF`=aus) / Lockout-Countdown |
| `$6044` (ROM)  | konstante Max-Switch-Nummer (`$2B`=43) für die Schließ-Queue |

## 3. Kadenz / Timing (FPGA == echte HW)

- `cpu_clk_gen`: 14,28 MHz / 16 = **892,5 kHz** CPU-Takt (echte HW ≈ 895 kHz).
- `irq_generator` (4020-Nachbau, `gen_irq = Q7·Q8·Q9` an φ2): IRQ bei Zählerstand ≈896 ⇒
  **~1,0 ms Periode (~1 kHz)**.
- Display: 8 Digits × 2 IRQs = 16 IRQs ≈ **16 ms Refresh (62,5 Hz)**.
- Switch-Matrix: jeder 2. IRQ ⇒ **~2 ms pro Voll-Scan (~500 Scans/s)**.
- Debounce-Fenster = 2 Scans ⇒ Schließ-Ereignis **~2 ms** nach dem ersten geschlossenen
  Read; Re-Arm ≥1 offener Scan (~2 ms).

## 4. Debounce je Schaltertyp (Pinwiki-Hinweis bestätigt — softwareseitig)

Es gibt **eine** Lese-/Entprell-Routine, aber Williams differenziert danach **per Software**:
- **Schließ-Ereignisse (Queue `$34–$36`)** — nur Switch-Nr. **≤ `$6044`** (=43). Das sind
  die „scorenden" Playfield-Schalter (Stand-Ups, Rollover, Spinner). Höher nummerierte
  (Coin-Door/Menu/Dedicated) werden **nicht** eingereiht, sondern separat gepollt.
- **Level-Polling (CUR/DEB-Tabellen)** — für Schalter, deren *Zustand* zählt: Drop-Targets
  (unten/oben), Outhole/Trough (Kugel da/weg). Diese liest die Spiel-/Bank-Logik direkt aus
  `$0024+`/`$002C+`, unmittelbar nach dem Feuern der Reset-/Kicker-Spule (`$2200/$2202`).

Die Solenoid-Treiber (`$71C9`, `$767x`: `ORAA/ANDA $2202`, bzw. IRQ-Treiber `$2200` bei
`$7F50`) pulsen die Spule; die **Erfolgskontrolle** ist ein Level-Read der Tabellen.

---

## 5. Warum die FPGA-Emulation divergiert (Root Cause)

**Alles Gemeinsame ist gleich:** dieselben physischen Schalter, derselbe ROM-Code,
derselbe CPU-Takt, dieselbe IRQ-/Scan-Kadenz. Übrig bleibt **nur die Signal-Aufbereitung
der Return-Leitungen** bis zum Sample-Zeitpunkt:

- **Echte HW:** Kontakt → Matrix-Dioden → Widerstands-/Pull-Netz → NMOS-6821-Eingang. Die
  Analogstrecke (Trace-/Eingangs-C, weichere NMOS-Schaltschwelle) **verschleift** schnellen
  Kontakt-Chatter. Beim ~µs-Sample pro Scan sieht das ROM eine **saubere** Schließphase.
- **WillFA7:** Kontakt → (Board-Inverter) → **scharfer FPGA-Eingang** + 2-FF-Sync. Jede
  Chatter-Flanke ist eine saubere Digitalflanke. Über aufeinanderfolgende 2-ms-Scans kann
  ein harter Treffer als `zu–zu–auf–zu–zu` erscheinen → das ROM registriert **mehrfach**.

Damit erklären sich **alle** Beobachtungen widerspruchsfrei:

| Beobachtung | Erklärung |
|---|---|
| Momentschalter mehrfach (rohes v3.17) | 2-Read-Filter zu schwach für scharfkantigen Chatter; ROM re-triggert im ~2-ms-Re-Arm-Fenster |
| Bänke/Outhole perfekt (rohes v3.17) | Level-Tabellen mit 1-/2-Scan-Latenz; Confirm-Read sieht Öffnen sofort → 1× Coil |
| Momentschalter gefixt (mit Debounce) | zusätzliche Scans erzwingen längere Stabilität → Chatter unterdrückt |
| **Bänke 2× / Outhole 2× (mit Debounce)** | Integrator addiert ~4 Scans (~8 ms) **Öffnungs**-Latenz; Confirm-Read liest „noch unten/Kugel da" → Coil erneut, Up/Down-Modell desynct |

**Der fundamentale Constraint:** Das FPGA kann jeden Schalter **nur 1×/Scan** abtasten (das
ROM besitzt den Strobe; zwischen den µs-schnellen Scan-Bursts wird keine Spalte getrieben).
Eine matrix-aware Entprellung addiert deshalb Latenz in **ganzen Scans**. Da die ROM-eigene
Debounce (2 Reads) plus die Confirm-Read-Prüfung das gesamte Latenz-Budget schon aufbrauchen,
**bricht jede weitere FPGA-Latenz** die Öffnungs-Kontrolle von Drop-Targets und Outhole.
Das ist der gemeinsame Nenner **aller** gescheiterten Versuche (N-of-N, Lockout, Integrator,
v3.18-Fast-Release).

Warum Momentschalter- und Confirm-Read-Anforderung unvereinbar sind (mit **einem** Filter):
„ein prellender Treffer" und „zwei echte Treffer" sehen bei Scan-Auflösung identisch aus
(`zu–auf–zu`). Sie trennt nur **Zeit** (echter 2. Treffer später). Ein Zeit-Lockout ist aber
auf HW gescheitert (Spinner begrenzt das Fenster auf ~20 ms, Ringing überdauert es).

---

## 6. Fix-Richtungen (Shortlist — nicht implementiert, gem. Entscheidung „erst nur diagnostizieren")

Sortiert nach Fidelity/Robustheit:

1. **Debounce nur nach Schaltertyp (game-aware Maske)** — *empfohlen, spiegelt Williams' eigene
   Logik.* Nur die problematischen scorenden Momentschalter (bestimmte Stand-Ups) entprellen;
   Drop-Target-Zeilen, Outhole/Trough und Spinner **roh** durchreichen. Kostet eine per-Spiel
   Switch-Typ-Tabelle (welche Matrixposition entprellen). Umgeht das Confirm-Read-Latenzproblem
   vollständig, weil die Zustands-Schalter unberührt bleiben. (LE-günstig: Maske statt breiterer
   Zähler.)
2. **Hardware-RC an den Return-Eingängen** — kleine Kondensatoren auf der WillFA7-Platine bilden
   die analoge Front-End-Verschleifung nach. **Null** digitale Latenz → Confirm-Reads unberührt,
   höchste Fidelity. Nachteil: HW-Änderung, empirisch zu dimensionieren (Zeitkonstante < 1 Scan).
3. **Asymmetrischer Filter (Öffnen sofort, Schließen verzögert)** — schützt Confirm-Reads (Öffnen
   0 Latenz), unterdrückt aber Mehrfachtrigger nur teilweise (lange geschlossene Chatter-Läufe
   zählen weiter doppelt). Begrenzt wirksam.
4. **Roh belassen (v3.17)** — gelegentliches Momentschalter-Doppeln akzeptieren; auf echten
   System-7-Maschinen ein bekanntes Phänomen (Pinwiki „Switch Problems").

**Empfehlung für den nächsten Schritt:** Variante 1 oder 2. Beide brauchen als Eingabe, **welche
Matrixpositionen** bei *Alien Poker* Drop-Targets/Outhole/Trough (Level-Schalter) vs. scorende
Momentschalter sind — diese Zuordnung ist die eigentliche offene Information, nicht mehr die
Algorithmik.

---

## 7. Per-Switch-Handling im ROM (verifiziert am Disassembly)

Der Weg eines Schalters durch das ROM, komplett rekonstruiert:

**Zwei UNIFORME Debounce-Schichten (für ALLE Matrixschalter gleich):**
1. **Scan-2-Read** (`$7ECC`): `stabil = roh AND roh_vorher` → Schließ-Ereignis (Switch-Nr.) in Queue `$34–$36`.
2. **Pending-Tabelle `$0048`** (4×{Timer,Switch-Nr.}): der IRQ-Consumer `$7FAE` legt jede neue Nr. dort ab (Timer `$D0`); ein **Dedup** (`CMPA $01,X;BEQ`) ignoriert dieselbe Nr., solange sie noch pending ist. Die Main-Loop-Routine `$71B3` holt einen „neuen" Eintrag (Bit7 gesetzt), löscht das New-Flag und setzt den Timer auf `$10`=16 → **~32 ms Refraktärzeit** pro Schalter (IRQ-Timer `$7F99` zählt ihn runter, dann frei). **Es gibt KEINE typabhängige Debounce** — alle Schalter laufen gleich durch beide Schichten.

**Per-Switch-Dispatch-Tabelle `$60F1`** (`$710D`: `LDX #$60F1; ASLB;ASLB; +switch#×4`; `LDX $00,X; JMP $00,X`). 4 Bytes/Schalter: Handler-Adresse (2) + Datenbytes (2 → `$8C/$8D`). Die *einzige* echte Typunterscheidung steckt hier — im Handler, NICHT im Debounce:

| Handler | Schalter | Klasse |
|---|---|---|
| `$63DA` | 10,18,26,34,42 | **Drop-Target-Bank** (Sequenz A-K-Q-J-10; Datenbyte = Kartenposition 5..1) |
| `$63CD` | 17,35,36,37,38 | **Spinner + 4 Jets** (schnell repetierend) |
| `$63AA` | 14,16,20,30 | Joker-Targets |
| `$6473` | 9 | **Outhole** (dediziert; feuert Kicker via `$71CB`) |
| `$7230` | 11,12,13,15,19,21,22,23,24,25,27,28,29,32,33,39,40,41 | Generischer Score-Handler (`$61xx`-Zeiger auf Score/Coil je Schalter) |
| `$6467`/`$7993`/`$79A3`/`$7571`/`$75FE`/`$7602`/`$7606`/`$7E36`/`$637F` | 7 / 1 / 2,31 / 3 / 6 / 5 / 4 / 8 / 43 | Slam / Tilts / Coin / Credit / HiScoreReset / Lane-Change |

**Refinierter Divergenz-Mechanismus (wichtig — korrigiert die erste Hypothese):**
Die Drop-Target- (`$63DA`) und Outhole-Handler (`$6473`) **pollen NICHT** die Switch-Level-Tabellen (`$24–$33`) — sie arbeiten rein **ereignisgetrieben** über die Schließ-Queue + Spiel-RAM (der Sequenzzähler steht im RAM, nicht in den Switch-Tabellen). Die Divergenz ist also KEINE Level-Read-Latenz, sondern:
- Der Integrator formt bauartbedingt marginales Mehr-Scan-Prellen in EIN sauberes, bestätigtes Schließ-Ereignis um (genau das Ziel für Stand-ups).
- Beim **Bank-Reset** schlagen die Drop-Targets hoch und **prellen mechanisch**. Roh (v3.17) ist das schnelles Chatter, das die ROM-eigene Debounce verwirft. MIT Integrator wird dieses Reset-Prellen zu **Phantom-Treffer-Ereignissen** → der Sequenzzähler verstellt sich / der Reset triggert erneut (2× Aufstellen, „abgeschossene Targets" unzuverlässig). Analog beim Outhole/Eject (ball-hold + Kick, dann mechanisches Nachprellen → Phantom-Schließung → 2× Auswurf).
- Deshalb ist die Kur, genau diese Schalter **roh** zu lassen (Maske), unabhängig vom exakten Prell-Detail robust — roh funktioniert nachweislich.

Die aktuelle Alien-Poker-Maske deckt sich sauber mit den ROM-Klassen: RAW = Drop-Bank (`$63DA`), Spinner+Jets (`$63CD`), Outhole (`$6473`), plus die Ball-Hold-&-Kick-Teilmenge von `$7230` (Eject-Holes 15/22/29, Left Kicker 13). Debounced = Joker-Targets (`$63AA`), Stand-ups/Rollovers/Specials/Lane-Change (Rest von `$7230`), Kabinett.

## Anhang: Vektoren & Werkzeug

- RESET `$7000` (`SEI/LDS #$7FDB…`), IRQ `$60EE`=`JMP $6711`, NMI `$7BE0`, SWI `$7000`.
- Disassembler + Listings: Scratchpad `dis6800.py` → `alpoker.lst`, `alpoker_io.txt`.
- Verifikation: Switch-Routine round-trippt byte-genau; Kadenz konsistent mit ~1-kHz-IRQ /
  62,5-Hz-Refresh; einziger PIA2-Read per Voll-Image-Byte-Scan bestätigt.
