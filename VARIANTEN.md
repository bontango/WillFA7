# WillFA7 – Varianten-Übersicht

Stand: 02.08.2026 · Ergänzt `CLAUDE.md` (dort steht die Architektur, hier die Varianten).

**Etappe 2 aus `PLAN_Zielstruktur.md` ist umgesetzt, und seit `.22` auch der Nachzug der
Soundkarten-Variante.** Sechs Varianten bauen aus **einem** `top/WillFA7.vhd` und **einem**
`rtl/`-Baum, ihre `.qsf` werden generiert. Nur `s_cyclone_10` ruht noch (Abschnitt 4).

## 1. Die sieben Ausprägungen

| `variants/<name>` | Version | FPGA | Familie | Sound | Status |
|---|---|---|---|---|---|
| `cyclone_ii` | **1.22** | EP2C5T144C8 | Cyclone II | – | aktiv, über `WillFA7_cii` |
| `cyclone_iv_v3` | **2.22** | EP4CE6F17C8 | Cyclone IV E | – | aktiv, mit USB-Monitor-API |
| `cyclone_iv_v4` | **3.22** | EP4CE6E22C8 | Cyclone IV E | – | aktiv ← **Leitvariante** |
| `cyclone_10` | **4.22** | 10CL006YE144C8G | Cyclone 10 LP | – | aktiv |
| `cyclone_iv_dev_open` | **5.22** | EP4CE6E22C8 | Cyclone IV E | – | aktiv, Aliexpress-Devboard |
| `s_cyclone_iv_v4` | **6.22** | EP4CE10E22C8 | Cyclone IV E | ja | **aktiv** seit `.22` |
| `s_cyclone_10` | **7.14** | 10CL010YE144C6G | Cyclone 10 LP | ja | **ruht**, unfertig, baut nicht |

Versionsschema: **erste Stelle = Board**, zweite und dritte = gemeinsamer Funktionsstand.
Quelle: `BOARD_ID` in `variants/<name>/variant_pkg.vhd` und `SW_SUB1`/`SW_SUB2` in
`rtl/common/version_pkg.vhd`. Seit `.22` gilt das auch für `s_cyclone_iv_v4`; nur `s_cyclone_10`
trägt seine Version noch als Konstante im eigenen Top-Level.

Funktionsstände: `.17` EEprom-Write-Robustness · `.18` Switch-Debouncer · `.19`
Spec-Sol-Debounce über DIP4 · `.20` Switch-Debounce-Maske spielabhängig + Fix `LED_active` =
Blanking-Leitung · `.21` Monorepo (kein Funktionsunterschied zu `.20`) · `.22` Soundkarten-Variante
im gemeinsamen Top-Level, eine `SD_Card` für alle, Platinenhülle für Cyclone II,
Soundkarten-Kern auf WISOF 0.9 (Abschnitt 3).

**`.22` ist gebaut, aber nicht veröffentlicht.** `bin/` endet bei `.21`. `release.ps1` läuft
erst nach bestandenem Hardwaretest – und dann **ohne** `-Note`, weil der `.22`-Eintrag in
`bin/changelog.txt` bereits ausformuliert ist.

## 2. Ressourcen auf Funktionsstand `.22`

Gemessen 02.08.2026, `check.ps1 -Fit`:

| Variante | Logic Elements | Memory Bits | Pins | Slack | vorher (`.21`) |
|---|---|---|---|---|---|
| `cyclone_ii` | 4.322 / 4.608 (**94 %**) | 94.208 / 119.808 | 82 / 89 | 3,434 ns | 4.313 LE, 86 Pins |
| `cyclone_iv_v3` | 5.033 / 6.272 (80 %) | 110.592 / 276.480 | 85 / 180 | 6,215 ns | 5.019 LE |
| `cyclone_iv_v4` | 4.476 / 6.272 (71 %) | 110.592 / 276.480 | 82 / 92 | 6,025 ns | 4.469 LE |
| `cyclone_10` | 4.488 / 6.272 (72 %) | 110.592 / 276.480 | 82 / 89 | 6,264 ns | 4.473 LE |
| `cyclone_iv_dev_open` | 4.477 / 6.272 (71 %) | 110.592 / 276.480 | 83 / 92 | 6,809 ns | 4.469 LE |
| `s_cyclone_iv_v4` | 6.303 / 10.320 (61 %) | 275.456 / 423.936 | 82 / 92 | 5,772 ns | 5.392 LE auf `.03` |

Referenz für `scripts/check.ps1 -Fit`, gespiegelt in `scripts/baseline.csv`. Alle Slacks positiv
bei 20 ns Taktperiode. **Cyclone II ist mit 94 % die harte Randbedingung** – was dort nicht
passt, passt nirgends.

Woher die Differenz zu `.21` kommt, im Einzelnen nachgemessen:

- **+4 bis +19 LE** durch die vier zusätzlichen Top-Level-Ports (`SB_Sound`, `SB_Speech`,
  `SB_Test`, `Dip_Ret_4`). Reine Umpackung, keine neue Logik – aber reproduzierbar, zweimal
  dieselben Zahlen.
- **wenige LE** durch `address_sd_card` von 14 auf 16 Bit.
- **+7 LE** durch `SW_SUB2` von `x"1"` auf `x"2"` – die Ziffer geht in die Anzeigelogik. Beim
  Sprung `.20`→`.21` waren es 15 LE, dieselbe Größenordnung.
- **`cyclone_ii`: 86 → 82 Pins** durch die Platinenhülle, bei praktisch gleicher LE-Zahl.
- **`s_cyclone_iv_v4`: +916 LE und +2.048 Bit** gegenüber `6.03` – das ist der ganze Sprung von
  Funktionsstand `.03` auf `.22`. Die 2.048 Bit sind die spielabhängige Switch-Debounce-Maske.
  64 der 916 LE gehen auf den Nachzug des Soundkarten-Kerns von WISOF 0.8 auf 0.9: der
  vorzeichenbehaftete CVSD-Integrator mit Sättigung und Reset, der Audio-Mixer samt
  Synchronisierer – abzüglich eines der beiden bisherigen DACs.
- **`s_cyclone_iv_v4`: 6.308 → 6.303 LE** am 03.08.2026 durch die Richtungskorrektur an
  `sb_option` (Zuordnung zu `WISOF.SB_Opt` und Anzeigegewichte, s. `docs/soundcard_variant.md`
  Abschnitt 3). Die Registerzahl bleibt bei 2.409 – die vier DIP-Bits wechseln nur die Senken,
  den Rest packt der Fitter um: 6.294 mit der gespiegelten Verdrahtung, 6.293 nur mit der
  Portkorrektur, 6.303 mit beiden. Zweimal dieselben Zahlen.

**Die Sound-Blöcke kosten die fünf Boards ohne Soundkarte nachweislich nichts.** Der Schritt, der
sie ins gemeinsame Top-Level gebracht hat, lief mit *exakt* unveränderten LE-, Memory- und
Slack-Zahlen durch; in der Hierarchie dieser Varianten taucht kein einziger Sound-Knoten auf.

Die Slack-Werte streuen zwischen zwei Läufen über identische Quellen um bis zu 1,1 ns – das
ist Platzierungsrauschen, kein Signal. `check.ps1` toleriert deshalb 1,5 ns und schlägt
zusätzlich unterhalb von 1,0 ns absolut an. Die LE-Zahlen streuen nicht.

Quartus: Cyclone II braucht 13.0sp1 (`C:\altera\13.0sp1`), alle anderen 22.1std
(`C:\intelFPGA_lite\22.1std`). Beide installiert, `quartus_sh` nicht im PATH – die Skripte
kennen die Pfade.

## 3. Was `.22` inhaltlich geändert hat

Der Auftrag war, `s_cyclone_iv_v4` von `6.03` auf den gemeinsamen Funktionsstand zu heben. Dabei
sind drei Dinge herausgekommen, die auch die anderen Varianten betreffen – deshalb `.22` und nicht
`6.21`. Ein vierter Punkt kam nachträglich dazu, noch bevor `.22` ausgeliefert war: der
Soundkarten-Kern wurde von WISOF 0.8 auf 0.9 nachgezogen.

1. **`s_cyclone_iv_v4` baut aus dem gemeinsamen Top-Level.** Eigenes `WillFA7.vhd` und `local/`
   entfallen (nach `archive/s_cyclone_iv_v4_603/`), alles Sound-spezifische hängt an der neuen
   Konstante `HAS_SOUND`. Die Variante erbt damit in einem Schritt `.17` bis `.22`: `cpu68` v0.85,
   den EEprom-Neubau, die Spezialsolenoid-Entprellung über DIP4, den Switch-Debouncer mit
   spielabhängiger Maske, SYS3/4 über `AM8T28`, `cpu_clk_gen` mit `mem_clk`, die CONTACT-Option
   und die Version aus den Packages. Was durch die Soundkarte anders bleibt, steht in
   **`docs/soundcard_variant.md`**.

2. **Eine `SD_Card.vhd` für alle.** Die Sound-Fassung war ein Fork auf dem Stand vor `.17` –
   ohne Watchdogs, ohne R1-Priority-Search, ohne Blinkcodes. Sie ist jetzt über die Generics
   `Slot_Sectors`, `Check_CRC` und `CRC_Bytes` in `rtl/common/SD_Card.vhd` aufgegangen; die
   S-Platine erbt die Stage-A-Robustheit, neu dazu kommt Blinkcode **7** für CRC-Fehler.
   `address_sd_card` ist dafür 16 statt 14 Bit breit – das kostet die anderen Varianten ein paar LE.

3. **Cyclone II baut über die Platinenhülle `top/WillFA7_cii.vhd`** – siehe Abschnitt 3a. Das ist
   der einzige Punkt, der ein *ausgeliefertes* Binary betrifft.

4. **Der Soundkarten-Kern steht auf WISOF 0.9.** Er stammt aus dem eigenständigen Projekt
   `N:\Projekte\Soundboards\FPGA Soundboard Williams\WISOF`, das inzwischen einen Schaltplan- und
   VHDL-Review hinter sich hat; hier lag bis dahin 0.8. Übernommen sind die dort auf Hardware
   bestätigten Befunde: der CVSD-Dekoder hatte durch eine Integerdivision **gar keinen
   Filterabfall** und einen unipolaren Integrator (F1/F3), der Soundkarten-RAM wurde bei **jedem**
   Schreibzugriff der Sound-CPU mitbeschrieben (F2), und Sound und Sprache teilen sich jetzt einen
   10-Bit-DAC an `clk_50` statt getrennter DACs, von denen der für die Sprache mit 763 Hz lief und
   auf einem Pin ohne Verstärkeranschluss endete (F4/F5). Kostet 64 LE.
   Die **sechste Sound-Auswahlleitung (F6)** aus 0.9 gilt hier nicht – es gibt keine zu
   verbinden. Einzelheiten: `docs/soundcard_variant.md`, Abschnitt 14.
   Zwei Nebenbefunde treffen alle Varianten und kosten 0 LE: `SS_R` ist aus `SD_Card.vhd`
   verschwunden (F12, eine Warnung weniger), `one_pulse_only.vhd` hat benannte Konstanten (F11).

### 3a. Befund: `VIRTUAL_PIN` funktioniert auf Cyclone II nicht

Beim Hinzufügen der vier Sound-Ports passte Cyclone II plötzlich nicht mehr: `Error (176205)`,
90 Pins gewollt, 89 vorhanden. Ursache:

```
Warning (292013): Feature Virtual IO is only available with a valid subscription license.
```

Quartus II 13.0sp1 **Web Edition** nimmt `VIRTUAL_PIN` an und ignoriert es. Der Fitter-Report
sagt `Total virtual pins: 0`, auf 22.1std Lite steht dort 5 bis 8.

**Das steckt schon im ausgelieferten 1.21.** Nachgemessen an einem Rebuild dieses Standes:

| Port | Pin | Richtung | getrieben mit |
|---|---|---|---|
| `LED_debug` | PIN_26 | out, 24 mA | `reset_sw` |
| `debug` | PIN_27 | out, 24 mA | `'0'` |
| `USB_Rx` | PIN_73 | out, 24 mA | `'1'` |
| `USB_Tx` | PIN_80 | in | – |

Vom Fitter gewählt, 86 von 89 Pins belegt. Ob diese Pins auf der Cyclone-II-Platine an etwas
hängen, sagt der Schaltplan, nicht das Repo – geprüft werden sollte es.

`top/WillFA7_cii.vhd` deklariert nur die 82 real vorhandenen Ports und instanziert `WillFA7`
darunter; die optionalen Ports werden damit zu internen Signalen und verschwinden. 86 → 82 Pins,
LE unverändert. Welche Entity Top-Level ist, steht als `TopEntity` in `variant.psd1`.

**Preis:** eine Hierarchieebene mehr. `variants/cyclone_ii/WillFA7.sdc` musste angepasst werden –
und dabei nicht einheitlich: `get_registers` will `WillFA7:CORE|…`, die PLL dagegen ihren
SDC-Pinnamen `CORE|PLL|altpll_component|pll` **ohne** Entity-Präfix. Der erste Versuch mit dem
Präfix überall hat die PLL-Constraint stumm verworfen (`Warning (332174)`, `Ignored
create_generated_clock`). Der Fitter-Report druckt den richtigen Namen unter „SDC pin name".

### Aus `.21` weiterhin gültig

`.21` war ausdrücklich **kein** Funktionsschritt. Zwei Dinge waren trotzdem anders als in
`.20` und gehören weiter benannt:

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

**Erledigt in `.22` (02.08.2026):**

- ~~`s_cyclone_iv_v4` steht auf Funktionsstand `.03` mit eigenem Top-Level und `local/`~~ –
  aufgelöst, die Variante ist jetzt eine normale Ausprägung des gemeinsamen Baums und aktiv.
- ~~`rtl/sound/SD_Card.vhd` und `SPI_Master.vhd` sind ein alter Fork~~ – zusammengeführt.
- ~~`variants/cyclone_ii/WillFA7.sdc` ist eine von Quartus 13 generierte Datei~~ – ist sie
  immer noch, aber jetzt bewusst und kommentiert von Hand nachgezogen (Abschnitt 3a).

**Offen:**

1. **`s_cyclone_10` baut nicht.** Auch hier war der frühere `Error (10481)` (`WISOF` fehlt)
   nur die Folge der Pfade. Dahinter liegt jetzt der eigentliche Fehler
   (Stand 27.07.2026, `quartus_map`):
   `WillFA7.vhd:1170`, `Error (10349)` – Formal `Audio_O` existiert nicht; die Portliste
   der instanzierten Entity passt nicht zum Aufruf.
   Dazu: **0 Pin-Zuweisungen** in der `.qsf`. Die Variante wurde nie fertiggestellt.
   Details in `variants/s_cyclone_10/README.md`.
2. **`s_cyclone_10` benutzt weiterhin `variants/s_cyclone_10/local/`** und ein eigenes
   Top-Level. Wird nachgezogen, wenn die Variante wieder aufgenommen wird; der Weg dafür ist
   jetzt vorgezeichnet, `HAS_SOUND` gibt es schon. Fehlt dann noch: Pin-Zuweisungen und
   `MPU_RAM`/`SB_ROM` – letztere sind seit `.22` inferiertes VHDL und damit familienunabhängig,
   also kein Hindernis mehr.
3. **Die Pins PIN_26/27/73 der Cyclone-II-Platine** sollten gegen den Schaltplan geprüft
   werden – 1.21 hat sie getrieben (Abschnitt 3a).
4. **Cyclone II bei 94 %** – der nächste Funktionszuwachs passt dort nur, wenn er per
   `variant_pkg` weggeneriert werden kann.
5. Die `.sdc` von `cyclone_ii` ist eine von Quartus 13 **generierte** Datei, nicht der
   handgeschriebene Satz der anderen. Funktioniert, ist aber ein Fremdkörper – und seit `.22`
   einer, an dem von Hand nachgezogen werden muss (Abschnitt 3a).

## 5. Hardware-Teststand

**Kein Board ist auf `.21` oder `.22` bestätigt getestet.** Der letzte in Hardware getestete
Stand ist **3.20** auf der Cyclone-IV-v4-Platine.

**Der Test der WillFA7S läuft seit 02.08.2026.** Das Ergebnis gehört hierher, in diesen
Abschnitt – mit Datum, Spiel und Fundstelle.

### Für jedes Board

- **Bootanzeige** zeigt `x.22` – zugleich der Beweis, dass `variant_pkg` und `version_pkg` greifen.
- **SD-Boot**: Spiel startet normal (ROM_COUNT = 6 → 12-KByte-Image ab 5000h, bei `cyclone_ii`
  ROM_COUNT = 5 → 10-KByte-Image ab 5800h).
- **Blanking**: `LED_active` führt ausschließlich `blanking`, kein Einbruch ~6 s nach Boot
  und bei EEprom-Save.
- **DIP4** ON = 250 µs Spezialsolenoid-Entprellung, OFF = 57 µs.
- **DIP5** ON = Switch-Debouncer, OFF = `.17`-Verhalten.

### Zusätzlich für `6.22` (WillFA7S, die Soundkarten-Platine)

Diese Variante macht den größten Sprung – von `.03` auf `.22` – und ist noch nie in Hardware
gelaufen. Die vollständige Liste steht in `docs/soundcard_variant.md`; das Wichtigste:

- **SD-Karte im 64-KByte-Format** mit korrekter CRC16-CCITT auf `0xFFFE/0xFFFF`. Eine
  Standardkarte bootet hier nicht.
- **CRC-Anzeige**: `display3` (gerechnet) und `display4` (gelesen) müssen übereinstimmen. Bei
  Abweichung Fehlerziffer `7` und Blinkcode 7 auf `LED_SD_Error`, die CPU startet nicht.
- **Sound und Sprache** spielen. **Sprache ist der eigentliche Prüfpunkt:** bis `.22` lag der
  CVSD-Dekoder auf zwei Fehlern (kein Filterabfall, unipolarer Integrator) und sein DAC lief mit
  763 Hz effektiver Abtastrate auf `SB_Speech` – einem Pin, der gar nicht am Verstärker hängt.
  Seit `.22` sind Sound und Sprache gemischt und gehen zusammen über `SB_Sound`. Sprache muss
  also überhaupt erst einmal zu hören und dann verständlich sein.
- **Sound und Sprache gleichzeitig** dürfen nicht verzerren – der Mixer begrenzt auf ±512.
  Auch das Lautstärkeverhältnis der beiden beurteilen (fest 1:1, entspricht R8 in Mittelstellung).
- **Ein Spiel prüfen, das bisher ohne erkennbaren Sprachgrund auffällig war** – der
  Soundkarten-RAM wurde bis `.22` bei jedem Schreibzugriff der Sound-CPU mitbeschrieben.
- **Sound-Quelle folgt jetzt automatisch der Spielnummer** (`is_sys3`) statt dem DIP
  `sb_option(3)`. Je ein SYS3/4- und ein SYS6/7-Spiel prüfen.
- **Soundtest** über `SB_Test` durchsteppbar (`Diag_SW` weiter, `Enter_SW` spielen), Display
  übernimmt, Diag-NMI bleibt dabei gesperrt.
- **S5 Dip für Dip durchprobieren.** Nur Dip1 ON muss Chimes geben und in der Statusanzeige
  `01` zeigen, nur Dip2 ON die Sprache freigeben und `02` zeigen, nur Dip4 ON den eingebauten
  Soundtest auf `SB_Test` legen und `08`. Bis kurz vor `.22` waren diese Zuordnungen gespiegelt
  (Chimes lagen auf Dip4), weil `WISOF.SB_Opt` absteigend deklariert ist und die Verbindung des
  ganzen Arrays positionsweise zugeordnet wird – Quartus warnt dabei nicht.
- **DIPs wirken erst nach Neustart** – die 4×4-Matrix wird nur einmal gelesen.

### Zusätzlich für `1.22` (Cyclone II)

- **Vier Pins sind frei geworden.** 1.21 trieb PIN_26, PIN_27 und PIN_73; die neue Hülle tut das
  nicht mehr. Falls dort etwas angeschlossen ist, ändert sich das Verhalten – gegen den
  Schaltplan prüfen.
- **Timing**: die `.sdc` wurde von Hand auf die neue Hierarchie gezogen. Wenn eine Constraint
  nicht mehr trifft, verwirft Quartus sie stumm; die Absicherung ist der Slack gegen
  `scripts/baseline.csv`, und der stimmt.
- Weiter gültig aus `.21`: Cyclone II läuft auf `cpu68` v0.85 – DAA-abhängige Anzeigen
  (Punktestände, BCD-Arithmetik) und NMI-Verhalten prüfen. Die `SPECIAL1..6` hängen seit `.20`
  an `reset_l`: beim Reset müssen laufende Spezialsolenoid-Pulse sofort abfallen, und ein Reset
  darf keine Solenoide auslösen.

### Nach dem Test

**Bestanden:**

```powershell
scripts\release.ps1
```

Ohne `-Note` – der `.22`-Eintrag in `bin/changelog.txt` ist bereits ausformuliert, ein
zusätzliches `-Note` hängt nur eine zweite, kürzere Zeile an. `release.ps1` legt die Binaries
unter `bin/` ab und erzeugt dabei `bin/WillFA7S/`. Danach oben in diesem Abschnitt den
Teststand nachtragen und in `PROJECT.md` das Feld `release:` auf `3.22` setzen.

**Nicht bestanden:** Befund hier eintragen, `bin/` unangetastet lassen. Die drei
wahrscheinlichsten Stellen bei Sound-Auffälligkeiten:

| Symptom | Wo zuerst schauen |
|---|---|
| Sprache verzerrt oder zu leise/laut gegenüber dem Sound | die Skalierung im Mixer, `rtl/sound/WISOF.vhd` – `sound_s` und `speech_s` sind fest 1:1 |
| Sprache kratzt oder setzt aus | `dig55516`/`clk55516` kreuzen unsynchronisiert von `cpu_clk` nach `clk_50`; zwei `Cross_Slow_To_Fast_Clock` wären der nächste Schritt, siehe `docs/soundcard_variant.md` Abschnitt 11 |
| ein Spiel spielt falsche Sounds | erst prüfen, ob es eines der fünf aus `docs/soundcard_variant.md` Abschnitt 14 ist (World Cup, Contact, Disco Fever, Phoenix, Warlok) – die sind bekannt unvollständig |

Bei Auffälligkeiten, die *nichts* mit Sound zu tun haben, gilt weiter der globale Notausgang:
**DIP5 OFF** schaltet den Switch-Debouncer ab und stellt `.17`-Verhalten her.
