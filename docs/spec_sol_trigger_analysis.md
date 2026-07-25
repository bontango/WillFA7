# Spezialsolenoide: Doppelauslösung Sol 19 / Sol 20

Analyse zum Fehlerbild aus dem v3.18-Hardwaretest (Alien Poker):
Beim Auslösen des Kontakts **bottom Jet Bumper (Sol 20)** feuerte in ca. 50 % der Fälle
**zeitgleich auch Sol 19 (right Jet Bumper)**.

## Signalkette

```
Playfield-Kontakt (nicht Teil der Switchmatrix)
   │  schliesst nach GND
   ├── 4,7 kΩ Pull-up nach +5 V      R1..R6
   └── C nach GND                    C3..C8
        │
   74HC4049  (Inverter, KEIN Schmitt-Trigger)     IC1
        │
   SPC_Sol_Trig(n)  ──►  FPGA-Pin
        │
   Cross_Slow_To_Fast_Clock (2-FF)   META_SPECIALn
        │
   spec_sol_trigger  (Idle → Debounce → Pulse → Recycle)   SPECIALn
        │
   sp_solenoid_trig(n)  ──OR──  not sp_solenoid_mpu(n)  ──AND── GameOn
        │
   flipflops (ff3, alle ~20 µs neu gelatcht)  ──►  externes 74HCT374  ──►  Treiber
```

Pinbelegung (`WillFA7.qsf`) und Steckerbelegung 2J10:

| Kanal | Solenoid | FPGA-Pin | 2J10 |
|-------|----------|----------|------|
| 1 | Sol 17 | PIN_91 | 5 |
| 2 | Sol 18 | PIN_88 | 3 |
| 3 | Sol 19 (right jet) | PIN_89 | 2 |
| 4 | Sol 20 (bottom jet) | PIN_90 | 4 |
| 5 | Sol 21 | PIN_113 | 8 |
| 6 | Sol 22 (left kicker) | PIN_114 | 9 |

## Was als Ursache ausscheidet

**Interner Übersprecher.** `WillFA7.vhd` instanziiert sechs voneinander unabhängige
`spec_sol_trigger`. Gemeinsam sind nur `reset_l`, `GameOn` und `game_option` — die
würden alle sechs Kanäle betreffen, niemals ein einzelnes Paar.

**MPU-Pfad.** SS3 und SS4 hängen an PIA2 `cb2_o` / `ca2_o`. Der Alien-Poker-ROM
schreibt PIA2 CRA/CRB ($3001 / $3003) ausschliesslich über die Init-Tabelle bei
$7FEC; im Spielbetrieb werden nur $2201 (SS5) und $2203 (GameOn) gepulst.
`sp_solenoid_mpu(3)` und `(4)` sind während des Spiels also statisch.

→ `SPC_Sol_Trig(3)` wird beim Feuern von Sol 20 **elektrisch tatsächlich aktiv**.

## Warum ausgerechnet ~50 %

Der Störimpuls koppelt von der Sol-20-Ansteuerung in die benachbarte Trigger-Leitung
ein und entlädt C3. Danach lädt die Leitung über den 4,7-kΩ-Pull-up zurück und braucht
1–2 τ, bis sie die Schaltschwelle des HC4049 wieder überschreitet — bei 10 nF sind das
**≈ 50–100 µs**. Solange meldet der HC4049 „Kontakt geschlossen".

Die Debounce-Schwelle in `spec_sol_trigger` lag bei fix **`counter > 50`** cpu_clk-Zyklen,
also **≈ 57 µs** (cpu_clk ≈ 894 kHz, 1,118 µs/Zyklus). Das ist **exakt dieselbe
Grössenordnung** wie die RC-Erholzeit — mal reicht die Störung über die Schwelle, mal
nicht. Daher die beobachteten ~50 %.

## Fix (v3.19)

`spec_sol_trigger` v0.6: Debounce-Schwelle zur Laufzeit umschaltbar über **DIP4**.

| DIP4 | Generic | Zyklen | Zeit |
|------|---------|--------|------|
| OFF | `DEBOUNCE_FAST_CYCLES` | 50 | ~57 µs (Verhalten bis v3.18) |
| ON | `DEBOUNCE_SLOW_CYCLES` | 220 | ~250 µs |

250 µs ist bewusst gewählt:

- **~5× Reserve** über der RC-Erholzeit der Eingangsstufe.
- **deutlich unter** der Prellzeit eines Blattkontakts (1–5 ms). Die bewährte Logik
  „erster stabiler Kontakt feuert, danach 200 ms Recycle" bleibt damit erhalten. Eine
  Schwelle im Millisekundenbereich würde gegen das Prellen arbeiten und leichte Treffer
  verschlucken — genau das soll nicht passieren.

Zusätzlich: `META_SPECIAL1..6` synchronisieren jetzt mit `cpu_clk` statt `clk_50`.
Die 2-FF-Kette lag vorher in der falschen Taktdomäne — konsumiert wird das Signal von
`spec_sol_trigger` auf `cpu_clk`, die Metastabilität am cpu_clk-Flop wurde also gar
nicht beseitigt. Nebeneffekt: bei 894 kHz Abtastung werden Glitches < 1 µs praktisch
nie erfasst.

## Falls 250 µs nicht reicht

1. `DEBOUNCE_SLOW_CYCLES` erhöhen — eine einzige Zahl in `spec_sol_trigger.vhd`.
   Obergrenze ~900 (≈ 1 ms), darüber kollidiert es mit der Kontakt-Prellzeit.
2. **Cross-Blanking** als eigener Schritt: bei jeder Flanke eines `sp_solenoid(k)` für
   ~4 ms die *anderen* Kanäle sperren (`trigger => SPC_Sol_Trig_stable(n) and not blank(n)`).
   Zielgenauer, lässt die Reaktion auf einen einzelnen Treffer völlig unverändert,
   kostet einen ~12-Bit-Zähler.

## Hardware-Seite

Der eigentliche Störpfad liegt ausserhalb des FPGA. Unabhängig vom Firmware-Fix lohnt:

- **Wert von C3–C8 prüfen.** Bei 10 nF ist τ = 47 µs. Eine Erhöhung auf 47–100 nF
  (τ = 220–470 µs) filtert die Störung direkt an der Quelle weg. Grenze ist auch hier
  die zulässige Verzögerung des Jet-Kicks.
- **Kabelführung** zwischen Jet-Bumper-Kontakten und 2J10 — die Trigger-Leitungen laufen
  offenbar parallel zu den Solenoid-Leitungen.

Schaltplan: `N:\Projekte\WillFA\target\v1.3\WillFA7_v1.3_00_SCH.PDF`
