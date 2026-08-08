# Die Soundkarten-Variante – was `HAS_SOUND` wirklich ändert

Stand: 04.08.2026 · gilt für `variants/s_cyclone_iv_v4` (WillFA7S HW1.0, Version 6.22)

> **Abschnitt 4 und 5 sind seit `.22` allgemeingültig.** Das SD-Kartenformat dieser Platine und
> die CRC-Prüfung gelten jetzt für alle sechs Varianten; sie stehen weiter hier, weil sie von
> hier kommen. Alles andere in diesem Dokument ist nach wie vor sound-spezifisch.

`s_cyclone_iv_v4` ist eine `cyclone_iv_v4` mit auf demselben FPGA integrierter Williams-Soundkarte.
Seit `.22` baut sie aus demselben `top/WillFA7.vhd` wie alle anderen; was sie unterscheidet, hängt
an der einen Konstante `HAS_SOUND` in `variants/s_cyclone_iv_v4/variant_pkg.vhd`.

Vorher war sie ein Fork auf Funktionsstand `.03` mit eigenem Top-Level und eigenen Kopien der
gemeinsamen Module unter `local/`. Der alte Stand liegt in `archive/s_cyclone_iv_v4_603/`.

Dieses Dokument sammelt die Unterschiede an einer Stelle. Wer am gemeinsamen Sourcebaum arbeitet,
muss sie kennen – vor allem Punkt 7.

---

## 1. Pins: vier von 82

Die Platine ist zur v4.x pinkompatibel bis auf vier Leitungen. Die Soundkarte braucht drei Pins,
und die holt sie sich von den DIP-Strobes:

| Pin | `cyclone_iv_v4` | `s_cyclone_iv_v4` |
|---|---|---|
| PIN_34 | `DIP_Str_2` | `SB_Sound` – Audio, Delta-Sigma |
| PIN_39 | `DIP_Str_4` | `SB_Speech` – **seit `.22` unbenutzt**, fest auf `'0'`. War der zweite Delta-Sigma-Ausgang für die Sprache; die läuft jetzt gemischt über `SB_Sound`, siehe Abschnitt 8 |
| PIN_42 | `DIP_Str_3` | `SB_Test` – Taster Soundtest (Pull-up in `device.tcl`) |
| PIN_38 | `DIP_Str_1` | frei |
| PIN_11 | frei | `Dip_Ret_4` – vierter DIP-Rückläufer |

Alle anderen 78 Zuweisungen sind identisch. `DIP_Str_1..4` bleiben in der gemeinsamen Portliste
und sind auf dieser Platine `VIRTUAL_PIN` (`variant.psd1`), `SB_Sound`/`SB_Speech`/`SB_Test`/`Dip_Ret_4`
sind es umgekehrt auf allen anderen.

## 2. DIP-Matrix 4×4 statt 4×3

Ohne dedizierte Strobe-Pins müssen die DIP-Strobes woanders hin. Sie laufen deshalb während
Bootphase 1 über die ungeraden Switch-Strobes und werden danach an die Switch-Matrix zurückgegeben:

```
sw_strobe(7) <= game_sw_strobe(7) when boot_phase(1) = '1' else dipstrobe(0);
sw_strobe(5) <= game_sw_strobe(5) when boot_phase(1) = '1' else dipstrobe(1);
sw_strobe(3) <= game_sw_strobe(3) when boot_phase(1) = '1' else dipstrobe(2);
sw_strobe(1) <= game_sw_strobe(1) when boot_phase(1) = '1' else dipstrobe(3);
```

Vier Rückläufer statt drei ergeben **16 statt 12 Bits**: 6 × `game_select`, 6 × `game_option`
und zusätzlich **4 × `sb_option`** für die Soundkarte.

Die Bitzuordnung ist dadurch eine komplett andere als bei `rtl/common/read_the_dips.vhd` – kein
Parameter derselben Zustandsmaschine. Deshalb gibt es `rtl/sound/read_the_dips_s.vhd` als eigene
Entity.

**Und ein Verhaltensunterschied, der leicht übersehen wird:** `read_the_dips_s` liest genau **eine**
Runde und bleibt dann in `Idle`. Die gemeinsame Fassung liest dauernd weiter. Das geht hier nicht –
dauerndes Lesen würde `sw_strobe(7,5,3,1)` im laufenden Spiel weitertreiben und die Switch-Matrix
stören. Wer die DIPs auf dieser Platine ändert, muss also **neu starten**, damit sie wirken.

## 3. Die Soundkarten-DIPs `sb_option(1..4)`

| Bit | Wirkung |
|---|---|
| `sb_option(1)` | Chime-Noten (ON) statt synthetisierter Klänge – geht auf `snd_ctl_i(6)` der Sound-PIA |
| `sb_option(2)` | Sprache vorhanden (ON) – `snd_ctl_i(5)`, nur bei Soundkarten vom Typ 2 sinnvoll |
| `sb_option(3)` | **reserviert seit 6.21.** War bis 6.03 die Umschaltung SYS3-/SYS7-Soundquelle; das macht jetzt `is_sys3`, siehe Punkt 6 |
| `sb_option(4)` | wählt, ob `SB_Test` den eingebauten Soundtest startet oder als Test-Eingang der Soundkarte durchgereicht wird |

`sb_option(n)` ist S5-Dip *n*, gelesen auf `return n` bei Strobe 4 (`read_the_dips_s`,
Zustand `Read4`). In der Statusanzeige wiegt Dip *n* damit 2^(n-1), Dip1 also 1 – dieselbe
Zählweise wie bei S1 und S2.

Auf der Credit-Anzeige stehen die **Soundkarten-Optionen links, die Spieloptionen rechts**
(`bm_status_d` im Top-Level, in Verbindung mit den Strobe-Nummern in `boot_message.vhd`:
14/15 ist das linke Ziffernpaar, 6/7 das rechte; innerhalb eines Paars Zehner vor Einer).

**Zwei Stellen im Top-Level, die von dieser Richtung abhängen:**

- `WISOF` deklariert `SB_Opt : in std_logic_vector(4 downto 1)`, das Signal hier ist
  `(1 to 4)`. VHDL ordnet ganze Arrays **positionsweise** zu, nicht nach Indexnamen –
  `SB_Opt => sb_option` würde die vier DIPs spiegeln (Chimes auf Dip4, Sprache auf Dip3),
  und Quartus sagt dazu nichts. Deshalb sind die vier Bits im Port Map einzeln zugeordnet.
  Bis 6.03 hieß das Signal `(4 downto 1)` und passte; die Umstellung auf aufsteigende
  Indizes hat die Zuordnung stumm gedreht.
- Die Anzeige `CONVSBO` konkateniert aus demselben Grund explizit
  `sb_option(4) & sb_option(3) & sb_option(2) & sb_option(1)`.

## 4. SD-Kartenformat: seit `.22` kein Unterschied mehr

**Dieser Abschnitt beschreibt seit `.22` keine Besonderheit der S-Platine mehr, sondern das
Kartenformat aller sechs Varianten.** Er steht hier, weil das Format von dieser Platine kommt.

Bis `.21` gab es drei Formate:

| | Cyclone II | Cyclone IV / 10 | WillFA7S |
|---|---|---|---|
| Startsektor Spiel 0 | 660 | 660 | 660 |
| Slot je Spiel | 24 Sektoren = 12 KByte | 24 Sektoren = 12 KByte | 128 Sektoren = 64 KByte |
| Nutzlast | 10 KByte, erstes 2K-Fenster auf **5800h** | 12 KByte, erstes 2K-Fenster auf 5000h | 12 KByte MPU + 20 KByte Sound |
| CRC | nein | nein | ja |

Seit `.22` gilt die rechte Spalte überall. Belegung eines Slots:

```
0x0000 - 0x2FFF   12 KByte   MPU-ROMs, 6 x 2K  -> Adressraum 5000h..7FFFh
0x3000 - 0x7FFF   20 KByte   Soundkarten-ROMs, 5 x 4K
0x8000 - 0xFFFD            frei
0xFFFE - 0xFFFF    2 Byte    erwartete CRC16-CCITT ueber die ersten 32 KByte
```

Was eine Variante ohne Soundkarte damit macht: sie liest den Bereich 12K–32K mit, dekodiert ihn
aber nicht – kein `wr_rom`-Fenster trifft ihn, die Bytes laufen durch den CRC und werden
verworfen. Ein Board mit `ROM_COUNT = 5` (Cyclone II) lässt zusätzlich **Fenster 0 liegen**;
es verschiebt die anderen fünf nicht nach unten, wie es das alte 10-KByte-Image verlangt hat.
Deshalb bootet eine `.21`-Karte unter `.22` nicht mehr.

Preis des gemeinsamen Formats: der ganze Slot wird gelesen, also 64 statt 12 KByte bei 400 kHz –
rund **eine Sekunde mehr Bootzeit** auf den Varianten, die vorher 12 KByte gelesen haben.

## 5. CRC-Prüfung beim Laden

`rtl/sound/crc16_ccitt.vhd` läuft über jedes geschriebene Byte unterhalb `CRC_Bytes` mit
(Generic in `rtl/common/SD_Card.vhd`, überall 32768). Am Slot-Ende werden die letzten beiden Bytes
zu `read_checksum`, und der Zustand `verify_crc` vergleicht. Auch das ist seit `.22` auf **jeder**
Variante scharf, geschaltet von `SD_CHECK_CRC` in `variants/<name>/variant_pkg.vhd`.

Sichtbar wird das in der Bootanzeige:

| Anzeige | Inhalt |
|---|---|
| `display3` | gerechnete Summe, vier Hex-Stellen |
| `display4` | gelesene Summe, vier Hex-Stellen |
| `error_disp4` | erste Ziffer `7` bei CRC-Fehler, sonst `F` |

Bei Abweichung geht der Lauf in `error`, `LED_SD_Error` blinkt den Code **7**, und die CPU startet
nicht – ein falsches Spiel laufen zu lassen wäre schlimmer als die Fehleranzeige.

`SD_CHECK_CRC = false` ist die Rückfallebene, falls einer Variante die Logikzellen ausgehen: das
Kartenformat bleibt dasselbe, der Lauf endet nach den 12 KByte MPU-Nutzlast, und `display3`/`4`
zeigen weiter das Build-Datum statt zweier Summen, die nie verglichen wurden. Auf Cyclone II
kostet die Prüfung 92 LE und passt (4404 von 4608), deshalb ist sie dort an.

## 6. Sound-Quelle: seit `.22` automatisch

Die Soundkarte muss wissen, woher ihre fünf Steuerleitungen kommen:

- **SYS6/7** – aus PIA5 Port A (`pia5_pa_o(4 downto 0)`)
- **SYS3/4** – aus den Solenoid-Ausgängen 9…13 (`not pia4_pb_o(4 downto 0)`)

Bis 6.03 wählte das der DIP `sb_option(3)`. Seit `.22` folgt es `is_sys3`, also der Spielnummer –
genau wie der Speicherschutz seit `.20`. Ein DIP weniger zu erklären, dieselbe Quelle der Wahrheit.

**Vorsicht beim Testen:** `is_sys3` war von `.16` bis in den `.22`-Umbau hinein konstant `'0'` –
der Vergleich lief gegen den rohen DIP-Wert statt gegen die Spielnummer. Die SYS3/4-Quelle war
damit nie ausgewählt. Der Fix steht in `VARIANTEN.md` Abschnitt 3b; die Solenoid-Quelle geht
mit ihm zum ersten Mal überhaupt in Betrieb.

Die ausgewählte Quelle heißt `sound_com` und geht an **zwei** Stellen: an die interne Soundkarte
*und* an den Sound-/Komma-Latch `FF_LAMPSS` (`ff3`), also auf den Steckverbinder für eine externe
Soundkarte. Das war schon in 6.03 so und ist bewusst beibehalten – auf einer Platine ohne
Soundkarte ist `sound_com` schlicht `sound`, damit ändert sich dort nichts.

## 7. Geteilte Kerne – die wichtigste Konsequenz für die Wartung

`rtl/sound/WISOF.vhd` ist ein vollständiger zweiter Rechner und instanziert dafür Module aus
`rtl/common/`:

- `cpu68` – der 6802 der Soundkarte
- `pia6821` – die Sound-PIA
- `one_pulse_only` und `Cross_Slow_To_Fast_Clock` – für den Test-NMI

**Ein Eingriff in diese vier Module trifft ab `.22` beide CPUs.** Der Wechsel auf `cpu68` v0.85
(DAA-Fixes, umgebauter NMI-Handler) betrifft damit auch den Sound-6802 – der lief bis 6.03 auf
v0.83. Wer `cpu68` anfasst, testet nicht nur das Spiel, sondern auch den Klang.

## 8. Der Soundkartenkern `WISOF`

Nachbau der Williams-Soundkarten Typ 1 und Typ 2 (System 3 bis 7).

```
0x0000 - 0x007F   128 Byte RAM   (MPU_RAM - das interne RAM des 6802)
0x0400 - 0x0403   PIA
0x3000 - 0x3FFF   4K ROM  IC7
0x4000 - 0x4FFF   4K ROM  IC5
0x5000 - 0x5FFF   4K ROM  IC6
0x6000 - 0x6FFF   4K ROM  IC4
0x7000 - 0x7FFF   4K ROM  IC12
```

Ausgabe – **seit `.22` ein gemischter Kanal**, siehe Abschnitt 14:

- **Sound** – PIA Port A (8 bit), nach `clk_50` synchronisiert
- **Sprache** – PIA `ca2`/`cb2` liefern Datenbit und Takt an den HC55564-CVSD-Dekoder
  (`clk_50`), der einen vorzeichenbehafteten 16-Bit-Abtastwert liefert
- beide werden 1:1 summiert, auf ±512 begrenzt und gehen über **einen** Delta-Sigma-DAC
  (10 bit an `clk_50` = 48,8 kHz) auf `SB_Sound`

`SB_Speech` (PIN_39) bleibt bestückt, wird aber auf `'0'` gehalten: auf der WillFA7S geht nur
`SB_Sound` zum Verstärker. Bis `.22` hing die Sprache allein an `SB_Speech` und war damit
**gar nicht zu hören**.

Die fünf Sound-Kommandoleitungen liegen auf PIA Port B, jede von ihnen zieht zusätzlich `cb1`
(`pia_cb1 <= not (sound(4) and … and sound(0))`) und löst so den IRQ aus. Anders als im
eigenständigen WISOF stehen sie hier **nicht** hinter einem Synchronisierer – sie kommen aus
PIA5 bzw. den Solenoid-Ausgängen der MPU, also aus demselben `cpu_clk`-Takt wie die Sound-CPU.

## 9. Soundtest

`SB_Test` (bei `sb_option(4)` entsprechend gesetzt) startet `rtl/sound/soundtest.vhd`:

- `Diag_SW` schaltet die Sound-Nummer weiter (1…31)
- `Enter_SW` spielt die aktuelle Nummer
- das Display zeigt die Nummer und wird dafür von der Bootmeldung übernommen
- der Diagnose-NMI ist solange gesperrt, damit `Diag_SW` nicht gleichzeitig die MPU unterbricht

Gibt es nur auf dieser Platine.

## 10. FPGA und Ressourcen

EP4CE10E22C8 statt EP4CE6E22C8 – aus **zwei** Gründen, nicht aus einem:

| | belegt | EP4CE10 | EP4CE6 |
|---|---|---|---|
| Logic Elements | **6.377** | 10.320 (62 %) | **6.272 – reicht nicht** |
| M9K-Blöcke | **36** | 46 (78 %) | **30 – reicht nicht** |
| Memory Bits (netto) | 275.456 | 423.936 | 276.480 |

**Der Speicher.** Die maßgebliche Größe ist die Blockzahl, nicht die Bitzahl: bei 8 bit Datenbreite
sind vom M9K nur 8.192 seiner 9.216 Bit nutzbar, die neunte Spalte ist Parity. Damit braucht das
ROM allein – 20 KByte Sound plus 12 KByte MPU – **exakt 32 M9K, und der EP4CE6 hat 30.** Vor dem
ersten Byte RAM fehlen also schon zwei Blöcke. Beide ROM-Gruppen sind zu 100 % gepackt, Umpacken
bringt null. Cyclone IV E hat kein MLAB, also kostet auch das 128-Byte-RAM des Sound-6802 einen
vollen Block.

**Die Logik.** Bis 6.03 lag die Variante bei 5.392 LE, und hier stand deshalb „nicht wegen der
Logik". Seit `.22` sind es **6.377 LE – 105 mehr, als der EP4CE6 überhaupt hat.** Der Satz ist
damit überholt; die +916 LE des Sprungs von `.03` auf `.22` sind in `VARIANTEN.md` Abschnitt 2
aufgeschlüsselt.

Beide Blocker sind voneinander unabhängig. Externer Speicher – SPI-RAM, QSPI-PSRAM – löst nur den
ersten und verschärft den zweiten, weil sein Controller Logik kostet; für paralleles SRAM sind
außerdem nur 10 von 28 nötigen Pins frei. Die vollständige Rechnung samt der geprüften Auswege
(`ROM_COUNT = 5`, kleinere Sound-ROMs, Wechsel auf `10CL010YE144C8G`) steht in
**`docs/memory_budget_willfa7s.md`**. Wer die Frage „geht das nicht auch auf dem kleinen Chip?"
noch einmal gestellt bekommt, findet sie dort beantwortet.

Die aktuellen LE-, Bit- und Slack-Zahlen stehen in `scripts/baseline.csv`. **Die M9K-Blockzahl
steht dort nicht** – sie ist aus `output_files/WillFA7.fit.rpt` zu holen.

## 11. Zeitverhalten

Bis 6.03 hatte die Variante eine eigene PLL mit zweitem Ausgang `c1`, der direkt als `cpu_clk`
diente, und eine `.sdc` ganz ohne CPU-Constraints. Seit `.22` benutzt sie `rtl/cyclone_iv/williams_pll`
und `cpu_clk_gen` wie alle anderen und damit die `.sdc` der Leitvariante – byte-identisch bis auf
zwei angehängte Zeilen, siehe unten.

Neu ist dadurch, dass `cpu_clk` und `clk_50` als asynchron deklariert sind. Das betrifft in der
Soundkarte die Übergabe von `dig55516`/`clk55516` (PIA, `cpu_clk`) an den HC55564-Dekoder (`clk_50`).
Das ist eine **Lockerung** gegenüber 6.03, kein neuer Pfad – aber es gehört beim Hardwaretest auf
die Liste: Sprachwiedergabe prüfen. Der Dekoder tastet `cen` mit einer eigenen Flankenerkennung
ab; ein Zweistufen-Synchronisierer wäre billig, WISOF 0.9 hat dort ebenfalls keinen, und er kommt
erst dazu, wenn der Hardwaretest an der Sprachqualität etwas zeigt.

Der zweite Übergang ist der **DAC-Wert** aus PIA Port A (`cpu_clk`) in den Mixer (`clk_50`).
Der steht seit `.22` hinter `rtl/sound/slow_to_fast_clock_bus.vhd` – bis dahin ging er
unsynchronisiert direkt an den 14-MHz-DAC.

Nebenbei bekommt die Variante damit auch den phasenverschobenen `mem_clk` für RAM und CMOS.

**Die zwei zusätzlichen `.sdc`-Zeilen.** `variants/s_cyclone_iv_v4/WillFA7.sdc` ist die der
Leitvariante plus:

```tcl
set_false_path -to [get_ports {SB_Sound}]
set_false_path -to [get_ports {SB_Speech}]
```

Grund: die gemeinsame `.sdc` legt pauschal `set_output_delay -clock clk_50 0 [all_outputs]` an.
`sound_DAC` läuft aber auf `clk_14`, und Quartus meldete dafür −3,445 ns. Die beiden Pins sind
Delta-Sigma-Ausgänge auf ein RC-Glied, es gibt keinen empfangenden Takt und damit keine Setup-
oder Hold-Bedingung. Ohne die zwei Zeilen ist der Build formal „timing not met" – an einem Pfad,
den es physikalisch nicht gibt.

## 12. Was *nicht* anders ist

MPU-Adressraum, Switch-Matrix und ihre Entprellung, Solenoide, Spezialsolenoide, Lampen, Displays,
EEprom-Save-Pfad, Blanking, Bootphasen, `ROM_COUNT = 6`, SYS3/4-Unterstützung über `AM8T28` –
alles identisch zur Leitvariante. Die Soundkarte hängt an der Seite dran, sie greift nicht in die
MPU ein.

## 13. Warum die Sound-Speicher kein Megafunction mehr sind

`MPU_RAM` und `SB_ROM` liegen seit `.22` als schlichtes inferiertes VHDL in `rtl/sound/`, nicht
mehr als Altera-Megafunction unter `rtl/cyclone_iv_s/`.

Der Grund ist die Regel, an der schon `serial_api` hängengeblieben ist: **Quartus löst
Entity-Referenzen auch im *nicht* genommenen `generate`-Zweig auf.** `WISOF` steht in
`if HAS_SOUND generate`, referenziert aber `MPU_RAM` und `SB_ROM` – also müssen beide in *jeder*
`.qsf` stehen, auch in der von Cyclone II und Cyclone 10. Eine für Cyclone IV E erzeugte
Megafunction hat dort nichts zu suchen. Inferierter Speicher hat keine Gerätefamilie in sich.

Verhalten ist identisch zu den ersetzten Megafunctions: Single Port, registrierte Adresse,
unregistrierter Ausgang, Write-First. Die alten Dateien liegen in
`archive/s_cyclone_iv_v4_603/cyclone_iv_s_megafunctions/`.

**Kontrolle:** wenn die Memory Bits in `scripts/baseline.csv` je fallen, ist die Inferenz in
Logikzellen gekippt statt in Blockram. Das ist ein Befund, keine Nebensache.

## 14. Herkunft und Stand des Soundkarten-Kerns

`rtl/sound/WISOF.vhd`, `hc55564.vhd`, `dac.vhd` und `slow_to_fast_clock_bus.vhd` stammen aus dem
eigenständigen Projekt

```
N:\Projekte\Soundboards\FPGA Soundboard Williams\WISOF
```

Das ist eine echte Soundkarte auf eigener Platine, mit eigener SD-Karte, PLL und LEDs. Für die
WillFA7S ist daraus der reine Kern herausgelöst: die fünf ROM-Blöcke liegen im MPU-Top-Level,
weil sie von derselben SD-Karte gefüllt werden, und `clk_50`/`cpu_clk` kommen von der MPU.

**Stand: WISOF 0.9.** Übernommen wurde er mit `.22`; bis dahin lag hier 0.8. Zwischen beiden
liegt ein Schaltplan- und VHDL-Review des WISOF-Projekts (`docs/schematic_analysis.md`,
`docs/vhdl_review.md`, Befunde F1…F13). Die vier hörbaren Befunde sind dort **auf Hardware
bestätigt**.

| Befund | Was er hier bewirkt hat |
|---|---|
| **F1** | `h` und `b` in `hc55564.vhd` waren als `(1 - 1/8)*256` geschrieben – Integerdivision, beide ergaben 256 statt 224/255. Damit fiel **weder** der Integrator **noch** der Silbenfilter je ab: `s` kletterte auf `s_max` und blieb dort, der Dekoder gab eine Rechteckschwingung im CVSD-Bittakt aus statt Sprache. |
| **F3** | Der CVSD-Integrator war `unsigned`, seine Ruhelage lag am unteren Ende des DAC-Bereichs. Jede negative Auslenkung lief unter und wurde auf 0 gezwungen – halbwellengleichgerichtet. Jetzt `signed` mit Sättigung, plus synchroner Reset auf `s_min`. `sample_out` ist dadurch **vorzeichenbehaftet**. |
| **F2** | `wren => not cpu_rw` ohne Adressdekodierung: **jeder** Schreibzugriff der Sound-CPU landete zusätzlich im 128-Byte-RAM. Die PIA-Register auf `0x0400`–`0x0403` überschrieben damit RAM `0x00`–`0x03`, und `0x00` bei **jedem einzelnen Sample** mit dem aktuellen DAC-Wert. Ob ein Spiel das überlebt, hing allein daran, ob sein ROM die Direct-Page-Adressen 0…3 benutzt – der wahrscheinlichste Grund für „läuft bei manchen Spielen, bei anderen nicht". Jetzt `ram_we <= ram_cs and not cpu_rw`. |
| **F4/F5** | Sound und Sprache werden summiert und teilen sich einen 10-Bit-DAC an `clk_50`. Der alte Sprach-DAC lief mit 16 bit an 50 MHz; `dac.vhd` braucht 2^(n+1) Takte je Sample, also 50 MHz / 65536 = **763 Hz** effektive Abtastrate. Auf der WillFA7S kommt dazu, dass `SB_Speech` gar nicht am Verstärker hängt – ohne den Mixer war Sprache überhaupt nicht zu hören. |
| **F10** | `ca1` liegt auf `'1'`; das Original zieht CA1 über R33 hoch. |
| **F8/F9** | Bewusst unverändert, nur begründet: die ROM-Adresse darf unsynchronisiert kreuzen (die CPU liest erst eine `cpu_clk`-Periode später), und die schmale PIA-Dekodierung auf vier Bytes deckt sich mit PinMAME. |
| **F11/F12** | Betreffen `rtl/common/one_pulse_only.vhd` und `rtl/common/SD_Card.vhd`, gelten also für **alle** Varianten. Beide sind reine Lesbarkeits- bzw. Warnungspflege, 0 LE. |

**Was hier nicht gilt:**

- **F6 – die sechste Sound-Auswahlleitung.** In WISOF 0.9 kommt sie über einen zusätzlichen
  FPGA-Pin und braucht eine Platinenänderung. Auf der WillFA7S gibt es **keine sechste Leitung
  zu verbinden**: der Williams-Sound-/Komma-Latch führt fünf, `sound <= pia5_pa_o(4 downto 0)`
  bildet genau das nach, und SYS3/4 hat mit Solenoid 9…13 ebenfalls fünf.
  Betroffen sind dieselben Spiele wie dort: **World Cup (2), Contact (3), Disco Fever (4),
  Phoenix (6)** – die frühen SYS3-Spiele mit PinMAMEs abweichendem Kommandoformat
  (`subType & 2`: Bit 4 auf PB7, PB4/PB5 hoch, CB1 gegen `0xbf`) – und **Warlok (25)** über
  den Jumper W12. Das wäre auf dieser Platine intern über die Spielnummer machbar, ist aber
  in WISOF 0.9 bewusst nicht umgesetzt und bleibt hier ebenfalls offen.
- **F7** – die Zeit-Constraints. Die `.sdc` der MPU erklärt `clk_50` und `cpu_clk` ohnehin als
  asynchrone Gruppen, siehe Abschnitt 11.
- **F12 (LEDs, `DFP_tx`)** und **F13 (`option(3)` im Audiopfad)** – gibt es hier beides nicht.

**Wenn WISOF weiterentwickelt wird**, ist der Weg hierher: `WISOF.vhd`, `hc55564.vhd` und
`dac.vhd` gegen die dortigen Fassungen halten, die Unterschiede aus dieser Tabelle abziehen
(kein SD-Karten-Teil, keine PLL, keine LEDs, kein Eingangs-Synchronisierer, keine sechste
Leitung), und danach `scripts\check.ps1 -Fit`.
