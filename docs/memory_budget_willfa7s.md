# Warum WillFA7S einen EP4CE10 braucht – die Speicher- und LE-Bilanz

Stand: 08.08.2026 · gilt für `variants/s_cyclone_iv_v4` auf Funktionsstand 6.22

Wiederkehrende Frage: der EP4CE10E22C8 ist spürbar teurer als der EP4CE6E22C8, den alle anderen
Varianten benutzen. Ginge die Soundkarten-Variante nicht auch auf den kleinen Chip – mit externem
seriellem RAM/ROM oder mit Optimierungen im Design?

Dieses Dokument beantwortet das mit den Zahlen aus dem Fitter-Report statt mit Schätzungen.
**Kurzfassung: nein, und zwar aus zwei unabhängigen Gründen.**

---

## 1. Die Bilanz

Aus `variants/s_cyclone_iv_v4/output_files/WillFA7.fit.rpt`, Quartus 22.1std.2, Build vom
04.08.2026 – dieselben Zahlen stehen in `scripts/baseline.csv`:

| | belegt | EP4CE10E22C8 | EP4CE6E22C8 |
|---|---|---|---|
| Logic Elements | **6.377** | 10.320 (62 %) | **6.272 – reicht nicht** |
| M9K-Blöcke | **36** | 46 (78 %) | **30 – reicht nicht** |
| Memory Bits (netto) | 275.456 | 423.936 | 276.480 |
| Pins | 82 (+8 virtual) | 92 | 92 |

**Die Netto-Bitzahl ist die irreführende Größe.** 275.456 von 276.480 Bit sähe aus, als passte es
gerade eben. Das gilt aber nur, wenn sich Speicher beliebig fein auf Blöcke verteilen ließe. Er
lässt sich nicht: das Device hat 30 physische M9K, gebraucht werden 36.

## 2. Wo die 36 M9K liegen

Aus der *Fitter RAM Summary* desselben Reports:

| Block | Instanz | Nutzbits | M9K | Auslastung |
|---|---|---|---|---|
| Sound-ROMs, 5 × 4K×8 | `SB_ROM:\GEN_SOUND:SB_ROM_1..5` | 163.840 | **20** | 100 % |
| MPU-ROMs, 6 × 2K×8 | `rom_2K:ROM_0..5` | 98.304 | **12** | 100 % |
| SYS7 Extended RAM, 1K×8 | `ram:RAM_S7` | 8.192 | 1 | 100 % |
| CMOS, 256×8, True Dual Port | `R5101:IC19` | 2.048 | 1 | 25 % |
| Sound-6802-RAM, 128×8 | `WISOF|MPU_RAM:RAM` | 1.024 | 1 | 12 % |
| Switch-Debounce-Maske, 256×8 | `sw_debounce:SWDEB` | 2.048 | 1 | 25 % |
| | | **275.456** | **36** | |

Der M9K hat 9.216 Bit, davon sind bei **8 bit Datenbreite nur 8.192 nutzbar** – die neunte
Spalte ist Parity und für Byte-Daten tot. Daraus folgt der entscheidende Satz:

> **Das ROM allein braucht 262.144 Bit = exakt 32 M9K. Der EP4CE6 hat 30.**

Bevor ein einziges Byte RAM, CMOS oder Debounce-Maske dazukommt, fehlen also schon zwei Blöcke.

**Cyclone IV E hat kein MLAB / LUT-RAM.** Anders als Cyclone V oder Stratix gibt es keine kleine
Speicherstufe unterhalb des M9K. Jeder noch so winzige Speicher kostet einen ganzen Block –
deshalb belegen die 1.024 Bit des Sound-6802-RAMs genauso einen M9K wie die 8.192 Bit des
Extended RAM.

## 3. Warum Umpacken nichts bringt

Beide ROM-Gruppen sind bereits zu **100 %** gepackt. Sechs 2K-Blöcke belegen dieselben 12 M9K wie
ein durchgehender 12K-Block; fünf 4K-Blöcke dieselben 20 wie ein 20K-Block. Eine Zusammenlegung
der Adressdekodierung spart also **null Blöcke** und kostet nur Logik.

Schlecht ausgelastet sind nur drei Blöcke – CMOS, Sound-RAM und Debounce-Maske, zusammen 5.120 Bit
auf 3 M9K. Selbst wenn man sie mit einigem Aufwand in einen einzigen Block zwänge (was an
unterschiedlichen Takten und am True-Dual-Port des R5101 scheitert), landet man bei **34 statt
30**. Es fehlt also nicht ein bisschen Sorgfalt beim Packen, es fehlen sechs Blöcke.

**Zur Vollständigkeit, die Parity-Spalte:** organisiert man ROM als 1024×9 statt 1024×8, kämen
262.144 Bit rechnerisch in 29 M9K. Praktisch müsste dann jeder Byte-Zugriff durch einen
8/9-Bit-Umsetzer, dessen Logik den gewonnenen Block um ein Vielfaches überkompensiert. Steht hier
nur, damit es niemand ein zweites Mal durchrechnet.

## 4. Der zweite, unabhängige Blocker: die Logik

`s_cyclone_iv_v4` belegt **6.377 LE. Der EP4CE6 hat 6.272.** Das sind 105 zu wenig, bevor der
Fitter überhaupt routen darf, und in der Praxis braucht ein routbarer Build auf diesem Device
Reserve – realistisch müssten rund 800 LE verschwinden, nicht 105.

**Diese Aussage ist neu und korrigiert eine ältere.** Bis zum Fork-Stand 6.03 lag die Variante bei
5.392 LE, und `soundcard_variant.md` sagte deshalb „nicht wegen der Logik". Der Sprung von `.03`
auf `.22` hat +916 LE gebracht (`VARIANTEN.md` Abschnitt 2). Seitdem stimmt der Satz nicht mehr.

Wo die Logik liegt, aus der Compilation-Hierarchy desselben Reports:

| Block | LE |
|---|---|
| `WISOF` gesamt (Sound-6802, PIA, CVSD, Mixer, DAC) | 1.432 |
| `SD_Card` inkl. `SPI_Master` und CRC16 | 720 |
| `EEprom` inkl. vier `SPI_Master` | 477 |
| Rest (MPU-CPU, 5 × PIA, Displays, Debounce, Boot, Top-Level) | ~3.750 |

Die naheliegenden Streichungen tragen nicht weit: `SD_CHECK_CRC = false` spart ~92 LE, der
Soundtest in derselben Größenordnung. Das ist ein Zehntel dessen, was fehlt.

## 5. Externer Speicher – warum das die Lage verschlechtert

### Paralleles SRAM

Scheitert an den Pins, nicht am Preis. Ein 128K×8-SRAM braucht 17 Adress- + 8 Daten- + 3
Steuerleitungen = **28 Pins. Frei sind 10** (82 von 92 belegt). Mit externen Adress-Latches käme
man auf ≥ 12 und bräuchte zusätzliche ICs auf einer Platine, die es dafür noch nicht gibt.

### QSPI-PSRAM (APS6404L, LY68L6400)

Das Einzige, was technisch ginge. 8 MByte, ~1 €, **6 Pins**. Zeitlich passt es:

```
QPI Fast Read bei 50 MHz: 2 Takte Kommando + 6 Adresse + 6 Wait + 2 Daten = 16 Takte = 320 ns
CPU-Zyklus bei 894 kHz:                                                              1.120 ns
```

Selbst mit Arbitration zwischen MPU-6800 und Sound-6802 bleibt Luft. Trotzdem ist es der falsche
Weg:

- **Es kostet Logik, die nicht da ist.** Ein QPI-Controller mit Arbiter liegt grob bei 300–500 LE
  (Schätzung, nicht gemessen). Der LE-Blocker aus Abschnitt 4 wird damit größer, nicht kleiner.
- **Platinenrevision zwingend.** WillFA7S HW1.0 hat weder Pads noch freie Pins dafür.
- **Neues Ausfallrisiko im ROM-Fetch-Pfad.** Jeder einzelne Befehl der beiden CPUs hinge an einem
  externen Bauteil und seiner Lötstelle. Für ein Gerät, das in einem Flipper zwanzig Jahre laufen
  soll, ist das ein schlechter Tausch gegen ein paar Euro Bauteilpreis.

## 6. Was im Design selbst noch ginge – und was es kostet

| Maßnahme | M9K | LE | Preis |
|---|---|---|---|
| `ROM_COUNT = 5` | 36 → 34 | ± 0 | Defender und Star Light fallen weg |
| Sound-ROM 5 × 4K → 3 × 4K | 36 → 28 | ± 0 | Typ-2-Sprachboards nutzen den Vollausbau; Spiele fallen weg |
| `SD_CHECK_CRC = false` | ± 0 | −92 | keine Kartendiagnose mehr |
| Soundtest streichen | ± 0 | ~−150 | Diagnosefunktion weg |

Die Speicherzeile allein löst das M9K-Problem – aber **nicht** das LE-Problem, und sie bezahlt es
mit Spielen. Beide Blocker fallen mit keiner Kombination dieser Maßnahmen zugleich.

## 7. Der aussichtsreiche Weg: Cyclone 10 LP

Statt das Design zu verbiegen, das Device wechseln – auf einen mit denselben Ressourcen, der aber
neuer und noch in Produktion ist:

**`10CL010YE144C8G`** – 10.320 LE, 46 M9K, 414 kBit, EQFP144. Ressourcen identisch zum EP4CE10,
und Cyclone 10 LP ist als jüngere Serie oft günstiger; für den EP4CE10 läuft die Fertigung nicht
mehr überall.

Im Repo wäre das billig zu haben: `rtl/cyclone_10/` existiert bereits, ebenso die Variante
`cyclone_10`. Eine `s_cyclone_10` wäre im Wesentlichen ein neues `variants/`-Verzeichnis mit
`HAS_SOUND = true`, `RtlFamily = cyclone_10` und **`BOARD_ID` 7** – die ist seit dem 04.08.2026
frei und gehörte genau einer solchen Fassung.

**Zwei Punkte sind vorher zu klären, beide außerhalb dieses Repos:**

1. **Pinkompatibilität EP4CE10E22 → 10CL010YE144.** Intel führt Cyclone 10 LP als Migrationsziel
   für Cyclone IV E, aber das ist im Pin-Planner gegen beide Datenblätter zu verifizieren, nicht
   auf Zuruf zu glauben. Betroffen wären sonst `variants/s_cyclone_iv_v4/pins.tcl` **und** die
   Platine.
2. **Die realen Einkaufspreise** für EP4CE6E22C8 / EP4CE10E22C8 / 10CL010YE144C8G. Kommt der
   10CL010 in die Nähe des EP4CE6, erledigt sich die Frage, ohne dass eine Zeile VHDL angefasst
   wird.

## 8. Ergebnis

**Der EP4CE6E22C8 ist für WillFA7S ausgeschlossen.** Nicht knapp, sondern an zwei Stellen
unabhängig voneinander: 36 gebrauchte M9K gegen 30 vorhandene (davon 32 allein für ROM, das nicht
kleiner zu packen ist), und 6.377 LE gegen 6.272 vorhandene.

Externer Speicher löst nur den ersten der beiden und verschärft den zweiten. Die einzige Richtung,
in der Geld zu sparen ist, ist ein anderes Device gleicher Größe – nicht ein kleineres.

---

**Nachprüfen:** die Zahlen dieses Dokuments stammen aus
`variants/s_cyclone_iv_v4/output_files/WillFA7.fit.rpt`, Abschnitte *Fitter Summary*,
*Fitter Resource Usage Summary*, *Fitter RAM Summary* und *Compilation Hierarchy*. Nach jedem
`scripts\check.ps1 -Fit` stehen LE, Memory Bits und Slack aktuell in `scripts/baseline.csv`; die
**M9K-Blockzahl steht dort nicht** und ist bei Bedarf aus dem Report zu holen. Genau sie ist bei
dieser Frage die maßgebliche Größe, nicht die Bitzahl.
