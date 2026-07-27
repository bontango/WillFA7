# WillFA7 – Varianten-Übersicht

Stand: 27.07.2026 · Ergänzt `CLAUDE.md` (dort steht die Architektur, hier die Varianten).

**Etappe 2 aus `PLAN_Zielstruktur.md` ist umgesetzt.** Die fünf aktiven Varianten bauen aus
**einem** `top/WillFA7.vhd` und **einem** `rtl/`-Baum, ihre `.qsf` werden generiert. Die beiden
Sound-Varianten sind in der Struktur, ruhen aber weiter und bauen nicht (Abschnitt 4).

## 1. Die sieben Ausprägungen

| `variants/<name>` | Version | FPGA | Familie | Sound | Status |
|---|---|---|---|---|---|
| `cyclone_ii` | **1.21** | EP2C5T144C8 | Cyclone II | – | aktiv |
| `cyclone_iv_v3` | **2.21** | EP4CE6F17C8 | Cyclone IV E | – | aktiv, mit USB-Monitor-API |
| `cyclone_iv_v4` | **3.21** | EP4CE6E22C8 | Cyclone IV E | – | aktiv ← **Leitvariante** |
| `cyclone_10` | **4.21** | 10CL006YE144C8G | Cyclone 10 LP | – | aktiv |
| `cyclone_iv_dev_open` | **5.21** | EP4CE6E22C8 | Cyclone IV E | – | aktiv, Aliexpress-Devboard |
| `s_cyclone_iv_v4` | **6.03** | EP4CE10E22C8 | Cyclone IV E | ja | **ruht**, baut aber wieder |
| `s_cyclone_10` | **7.14** | 10CL010YE144C6G | Cyclone 10 LP | ja | **ruht**, unfertig, baut nicht |

Versionsschema: **erste Stelle = Board**, zweite und dritte = gemeinsamer Funktionsstand.
Quelle: `BOARD_ID` in `variants/<name>/variant_pkg.vhd` und `SW_SUB1`/`SW_SUB2` in
`rtl/common/version_pkg.vhd`. Die S-Varianten lesen diese Packages nicht – ihre Version steht
weiterhin in ihrem eigenen Top-Level.

Funktionsstände: `.17` EEprom-Write-Robustness · `.18` Switch-Debouncer · `.19`
Spec-Sol-Debounce über DIP4 · `.20` Switch-Debounce-Maske spielabhängig + Fix `LED_active` =
Blanking-Leitung · `.21` Monorepo (kein Funktionsunterschied zu `.20`, siehe Abschnitt 3).

## 2. Ressourcen nach dem Umzug

| Variante | Logic Elements | Memory Bits | schlechtester Setup-Slack |
|---|---|---|---|
| `cyclone_ii` | 4.312 / 4.608 (**94 %**) | 94.208 / 119.808 | 4,392 ns |
| `cyclone_iv_v3` | 5.022 / 6.272 (80 %) | 110.592 / 276.480 | 6,471 ns |
| `cyclone_iv_v4` | 4.484 / 6.272 (71 %) | 110.592 / 276.480 | 6,725 ns |
| `cyclone_10` | 4.473 / 6.272 (71 %) | 110.592 / 276.480 | 5,690 ns |
| `cyclone_iv_dev_open` | 4.468 / 6.272 (71 %) | 110.592 / 276.480 | 6,209 ns |

Referenz für `scripts/check.ps1 -Fit`, gespiegelt in `scripts/baseline.csv`. Alle Slacks positiv
bei 20 ns Taktperiode. **Cyclone II ist mit 94 % die harte Randbedingung** – was dort nicht
passt, passt nirgends.

Quartus: Cyclone II braucht 13.0sp1 (`C:\altera\13.0sp1`), alle anderen 22.1std
(`C:\intelFPGA_lite\22.1std`). Beide installiert, `quartus_sh` nicht im PATH – die Skripte
kennen die Pfade.

## 3. Was der Umzug inhaltlich geändert hat

`.21` ist ausdrücklich **kein** Funktionsschritt. Zwei Dinge sind aber trotzdem anders als in
`.20` und gehören benannt:

1. **Cyclone II bekommt den gemeinsamen `cpu68` v0.85.** Diese Variante hatte bis `.20` eine
   eigene, ältere Fassung v0.83. Neu dabei sind die DAA-Fixes (Carry darf nie gelöscht werden,
   N-Flag wird gesetzt) und der umgebaute NMI-Handler – beides läuft seit 03.2026 auf der
   v4-Platine in Hardware. Nebeneffekt: 56 LE weniger, 95 % → 94 %. Die alte Fassung liegt als
   `archive/cpu68_v083_cyclone_ii.vhd`.
   *Hinweis: Etappe 1 hatte notiert, Cyclone II sei bei `cpu68` bereits auf dem aktuellen Stand.
   Das stimmte nicht.*
2. **Optionale Ports auf allen Boards.** `LED_debug`, `USB_Tx`, `USB_Rx` und `debug` stehen jetzt
   in jeder Portliste; wo der Pin nicht existiert, steht `VIRTUAL_PIN` in der `.qsf`. Kostet
   zwischen 0 und 22 LE je Variante.

Der Rest ist Umbau ohne Wirkung, jeweils einzeln durch `check.ps1 -Fit` gegen die
`.20`-Zahlen abgesichert: Packages statt Konstanten, `R5101`-Portliste, interne Display-Signale,
ROM-Block über `ROM_COUNT`, Monitor über `HAS_MONITOR`, generierte `.qsf`.

### Zwei Befunde aus dem Umbau, die man wissen sollte

- **Quartus löst Entity-Referenzen auch im *nicht* genommenen `generate`-Zweig auf.** Ohne die
  drei `rtl/serial_api/`-Dateien in der Dateiliste bricht jede Variante ohne Monitor mit
  `Error (10481)` ab. Deshalb stehen sie in **jeder** `.qsf`, obwohl nur `cyclone_iv_v3` sie
  instanziert. Synthetisiert wird davon nichts – nachgemessen, die LE-Zahlen bleiben gleich.
- **Quartus 13.0sp1 kann alles, was hier gebraucht wird**: Packages über Dateigrenzen,
  `if <konstante> generate`, `VIRTUAL_PIN`. Nur `else generate` nicht – das ist VHDL-2008.

## 4. Bekannte Defekte

**Erledigt in Etappe 1 (27.07.2026):**

- ~~IV_v4: Header v3.19, Anzeige 3.18~~ – seit `.21` strukturell unmöglich, die Version steht
  nur noch an einer Stelle.
- ~~Versionskollision Cyclone10 / dev_open~~ – dev_open hat Board-ID 5.
- ~~`sw_debounce.vhd`-Fork~~ – die IV_v4-Fassung gilt, der Lockout-Stand liegt in `archive/`.
- ~~Cyclone_II `SPECIAL1..6` mit `i_Rst_L => '1'`~~ – auf `reset_l` angeglichen.

**Erledigt in Etappe 2:**

- ~~vier Kopien von `lib_common`~~ – ein `rtl/common/`.
- ~~fünf handgepflegte `.qsf`~~ – generiert aus `device.tcl` + `pins.tcl` + Dateilisten.
- ~~`.qip`-Pfade der S-Varianten zeigten ins Leere~~ – aufgelöst; `s_cyclone_10` zeigte
  außerdem auf die Cyclone-**IV**-Megafunctions, jetzt auf `rtl/cyclone_10_s/`.
- ~~`init_file` der `R5101.vhd` war projektverzeichnisrelativ~~ – jetzt explizit
  `../../rtl/common/cmos_256_0Fh.hex`.

**Offen:**

1. **`s_cyclone_iv_v4` baut wieder** – unerwartet. Der Pfad-Fix hat gereicht:
   `5.392 / 10.320 LE (52 %)`, `273.408 / 423.936` Memory Bits, Slack 3,600 ns.
   Der in Etappe 1 gemeldete `Error (10349)` auf `calc_checksum` war eine **Folge** der
   nicht auflösbaren Pfade: `WISOF.vhd` und `crc16_ccitt.vhd` fehlten im Projekt, und
   Quartus hat den Fehler an der falschen Stelle gemeldet.

   **Baubar heißt nicht lauffähig.** Die Variante steht weiterhin auf Funktionsstand `.03`,
   benutzt unter `local/` alte Fassungen von `cpu68`, `EEprom` & Co. und ist in Hardware
   ungetestet. Sie bleibt `Dormant` – wer sie aufnimmt, fängt bei `.03` an, nicht bei `.21`.

2. **`s_cyclone_10` baut nicht.** Auch hier war der frühere `Error (10481)` (`WISOF` fehlt)
   nur die Folge der Pfade. Dahinter liegt jetzt der eigentliche Fehler
   (Stand 27.07.2026, `quartus_map`):
   `WillFA7.vhd:1170`, `Error (10349)` – Formal `Audio_O` existiert nicht; die Portliste
   der instanzierten Entity passt nicht zum Aufruf.
   Dazu: **0 Pin-Zuweisungen** in der `.qsf`. Die Variante wurde nie fertiggestellt.
   Details in `variants/s_cyclone_10/README.md`.
3. Die S-Varianten benutzen unter `variants/<n>/local/` **eingefrorene, ältere** Fassungen der
   gemeinsamen Module und über `rtl/sound/` ein älteres `SD_Card.vhd`/`SPI_Master.vhd`. Die
   Sound-Platine läuft damit weiter auf dem alten EEprom-Pfad. Wird nachgezogen, wenn die
   Varianten wieder aufgenommen werden.
4. **Cyclone II bei 94 %** – der nächste Funktionszuwachs passt dort nur, wenn er per
   `variant_pkg` weggeneriert werden kann.
5. Die `.sdc` von `cyclone_ii` ist eine von Quartus 13 **generierte** Datei, nicht der
   handgeschriebene Satz der anderen vier. Funktioniert, ist aber ein Fremdkörper.

## 5. Hardware-Teststand

**`.21` ist auf keinem Board getestet, auch 3.21 nicht.** Der letzte in Hardware getestete
Stand ist 3.20 auf der Cyclone-IV-v4-Platine.

Beim Test von 3.21 zu prüfen:

- **Bootanzeige** zeigt `3.21` – das ist zugleich der Beweis, dass `variant_pkg` und
  `version_pkg` greifen.
- **SD-Boot**: ROM_COUNT = 6, also 12-KByte-Image ab 5000h. Spiel muss normal starten.
- **Blanking**: `LED_active` führt ausschließlich `blanking`, kein Einbruch ~6 s nach Boot
  und bei EEprom-Save.
- **DIP4** ON = 250 µs Spezialsolenoid-Entprellung, OFF = 57 µs.
- **DIP5** ON = Switch-Debouncer, OFF = `.17`-Verhalten.

Für `1.21` kommt dazu: **Cyclone II läuft jetzt auf `cpu68` v0.85.** Zu prüfen sind vor allem
DAA-abhängige Anzeigen (Punktestände, BCD-Arithmetik) und das NMI-Verhalten. Ebenso hängen dort
seit `.20` die `SPECIAL1..6` an `reset_l` – beim Reset müssen laufende Spezialsolenoid-Pulse
sofort abfallen, und ein Reset darf keine Solenoide auslösen.
