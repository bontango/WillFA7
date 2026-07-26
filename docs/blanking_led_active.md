# `LED_active` ist die Blanking-Leitung — nicht nur eine LED

**Regel: PIN_3 (`LED_active`) darf ausschliesslich `blanking` fuehren.**
Keine Status-, Fehler- oder Fortschrittsanzeige auf diesen Pin legen. Das gilt fuer alle
WillFA7-Varianten.

## Hardware

```
FPGA PIN_3 (LED_active) ─┬─> "active"-LED auf dem FPGA-Board
                         ├─> IC13 74HCT240 /OE      (switch strobes)
                         └─> T9 (Inverter) ─> blanking_n
                                              ├─> /RESET IC3, IC4, IC5 (74HCT273, Solenoid-MOSFET-Treiber)
                                              └─> /RESET IC6, IC7      (74HCT273, Lamp strobe & rows)
```

`LED_active = '1'` (LED aus) bedeutet also gleichzeitig:

* alle Solenoid-Latches werden geloescht → Coin-Lockout-Coil faellt ab, Spulen aus
* alle Lamp-Latches werden geloescht → Lightshow aus, Switched Illumination aus,
  Williams-Diag-LED aus (haengt in FF3 der Lamp-Latches, `WillFA7.vhd`, `FF_LAMPSS`)
* die Switch-Strobes sind ueber `/OE` von IC13 abgeschaltet → Matrix tot

Das **Display bleibt dabei unberuehrt** — dessen Blanking laeuft ueber `LED_status`
(`LED_status <= not boot_phase(0); -- for display blanking`). Genau diese Kombination
(Spulen/Lampen aus, Display stabil) ist die Signatur eines Blanking-Einbruchs.

Quelle: `N:\Projekte\WillFA\doc\bugsv5.txt` ("Blanking ohne Treiber -> active LED!",
"Blanking fuer displays? -> LED"), `N:\Projekte\WillFA\doc\Blanking_wire_v05_new.png`.

## Wer treibt `blanking`

`COUNT_STROBES` (`entity count_to_zero`, `WillFA7.vhd`) zaehlt steigende Flanken von
`game_disp_strobe(2)`:

* `clear => reset_l` → beim Reset `blanking = '1'`, Maschine ist geblankt
* nach `count_a = 15` Display-Strobes → `blanking = '0'`, Maschine laeuft

Das ist die im Handbuch beschriebene Semantik: *"If the code runs (regular display strobes are
present) the 'active' LED will go ON."* Wichtig ist die Bootphase: solange die CPU im Reset
gehalten wird, **muss** `blanking = '1'` sein, sonst halten die 74HCT273 ihren undefinierten
Einschaltzustand und eine Spule kann anziehen.

## Die Regression v3.17 – v3.19

Commit `a25f2f1` (v3.17) hat den Pin fuer eine EEprom-Anzeige mitbenutzt:

```vhdl
-- FALSCH:
LED_active <= eeprom_error_sig when eeprom_wr_in_progress = '0' else blanking;
```

`eeprom_error_sig` ist `EEprom_error` aus `lib_common/EEprom.vhd`:

```vhdl
EEprom_error <= blink_q when (write_seen = '1' or error_latched = '1') else '0';
```

Damit hing die Blanking-Leitung an einem freilaufenden 1-Hz-Blinkgenerator.

### Symptome beim User (Alien Poker)

| Zeit | Vorgang | Wirkung auf Blanking |
|---|---|---|
| Power-On bis Boot-Ende | `EEprom.vhd` setzt im Reset `o_wr_in_progress <= '0'` → Mux nimmt `eeprom_error_sig` (`'0'`) | **Blanking freigegeben, obwohl die CPU im Reset ist.** Active-LED ist ab Einschalten an (bei v3.15 blieb sie bis Bootende aus). 273er nicht im Reset. |
| Boot-Ende + ~4,5 s | `COUNT_STROBES` `count_b = 511` setzt `eeprom_trigger` → `PH_SAVE_PREP` setzt `o_wr_in_progress <= '0'` | noch `'0'`, unauffaellig |
| + 1 s (`PRE_WRITE_CYCLES`) | Read-before-write-Scan findet die erste Abweichung → `PH_WRITE_WREN` setzt `write_seen <= '1'` | **Blanking folgt jetzt `blink_q`** → Coil faellt ab, Illumination aus, Diag-LED aus, Active-LED aus |
| Scan-Ende | `PH_NEXT_BYTE → PH_IDLE`: `write_seen <= '0'`, `o_wr_in_progress <= '1'` | wieder `blanking` |

4,5 s + 1 s + Blinkphase ≈ **6 s nach Bootende**, Dauer = Rest der Blink-Halbwelle bzw. des
Scans → "eine viertel Sekunde oder kuerzer". Waehrend des Spiels bei jedem Save, der
tatsaechlich Bytes schreibt (Trigger `GameOn`, `advance`, `enter_stable`) → "unregelmaessig".

Mit v3.15 trat es nicht auf: dort war `LED_active <= blanking;` und das alte EEprom-Modul
hatte gar keinen `EEprom_error`-Ausgang.

## Fix (v3.20)

`WillFA7.vhd`:

```vhdl
LED_active <= blanking;
...
EEprom_error => open
```

Die EEprom-Speicheranzeige entfaellt ersatzlos. Falls sie spaeter wieder gewuenscht ist, darf
sie **nur** auf einen Pin, dessen Beschaltung auf der Platine nachgewiesen ist —
`LED_status` ist ebenfalls tabu (Display-Blanking).

## Noch zu portieren

Die identische Zeile steht in:

* `WillFA7 - CycloneIV_v3`
* `WillFA7 - Cyclone10`
* `WillFA7 - Cyclone_II`
* `WillFA7 - CycloneIV_dev_open`

Die beiden `WILLFA7S`-Varianten haben noch `LED_active <= blanking;` und sind nicht betroffen.
