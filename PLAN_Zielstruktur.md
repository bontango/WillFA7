# WillFA7 – Weg zur gemeinsamen Quell- und Repo-Struktur

Stand: 27.07.2026 · Status: **Etappe 1 und Etappe 2 umgesetzt**
Was dabei herausgekommen ist, steht in `VARIANTEN.md` und `CLAUDE.md`.
Dieses Dokument ist die Begründung – warum die Struktur so aussieht, wie sie aussieht.

---

## 1. Die Ausgangslage in einem Satz

Sieben Ausprägungen, deren Quellen sich **fast nicht** unterschieden (15 von 22 gemeinsamen
Modulen byte-identisch, die Entity-Portliste praktisch gleich), die aber in sieben getrennten
Ordnerbäumen mit sieben handgepflegten `.qsf` lagen – daher der hohe Pflegeaufwand und die
Fehleranfälligkeit. Die ursprüngliche Idee gemeinsamer `lib_*`-Ordner war richtig, wurde aber
nie durchgezogen: nur die beiden S-Varianten nutzten sie noch, und deren `lib_common` war
veraltet.

## 2. Die vier tragenden Mechanismen

### 2.1 Ein Top-Level statt sieben
Alle optionalen Ports (`LED_debug`, `USB_Tx/Rx`, `debug`) bleiben dauerhaft in der Portliste
deklariert. Ob dahinter Logik entsteht, entscheidet `variants/<name>/variant_pkg.vhd`:

```vhdl
package variant_pkg is
  constant BOARD_ID    : std_logic_vector(3 downto 0) := x"3";
  constant ROM_COUNT   : integer := 6;
  constant HAS_MONITOR : boolean := false;
end package;
```

Die familienabhängigen Megafunctions haben identische Entity-Namen – die Auswahl passiert
allein darüber, welchen `rtl/<familie>/`-Ordner die `.qsf` einbindet. Kein VHDL-Konstrukt nötig.

**Nicht** vorgesehen war, dass ein Pin ohne Location teuer ist: für Quartus ist ein deklarierter
Ausgangsport ein *benutzter* Pin, `RESERVE_ALL_UNUSED_PINS` greift nicht. Deshalb `VIRTUAL_PIN`
je Variante. Kostet 0 bis 22 LE.

### 2.2 Versionsnummer nur noch an einer Stelle
`SW_MAIN` ist zu `BOARD_ID` in `variant_pkg.vhd` geworden, `SW_SUB1`/`SW_SUB2` stehen in
`rtl/common/version_pkg.vhd`. Ein Release = eine Zahl ändern; alle Varianten zeigen automatisch
`x.NN`. Die frühere Diskrepanz (Header v3.19, Anzeige 3.18) ist strukturell unmöglich.

### 2.3 `.qsf` generieren statt pflegen
Handgepflegt bleibt pro Variante nur `device.tcl` (Family/Device) und `pins.tcl` (die ~82
`set_location_assignment`). Die Dateiliste kommt aus `scripts/files_common.tcl` plus der
Familien-/Optionsauswahl aus `variant.psd1`. `gen_qsf.ps1` setzt daraus die `.qsf` zusammen.
Damit kann eine neue `.vhd` nicht mehr in sechs von sieben `.qsf` fehlen – genau der Fehler,
der die gemeinsame lib-Struktur vorher unbrauchbar machte.

### 2.4 Compile-Check als Sicherheitsnetz
`check.ps1` wählt pro Variante die richtige Quartus-Version (13.0sp1 für Cyclone II, sonst
22.1std), fährt `quartus_map` bzw. mit `-Fit` zusätzlich Fitter und Timing, und vergleicht
LE/Memory/Slack gegen `scripts/baseline.csv`. Ohne diesen Vergleich hätte man den Umbau nicht
in kleinen Schritten absichern können.

## 3. Etappen

Bewusst in zwei Etappen: **erst inhaltlich angleichen, dann umziehen.** Andernfalls wäre die
Divergenz in die neue Struktur mitgewandert.

### Etappe 1 – alle auf einen Stand (im alten Ordnerbaum) — erledigt 27.07.2026

`.18`/`.19`/`.20` von IV_v4 auf Cyclone10, dev_open, IV_v3 und Cyclone_II portiert;
`sw_debounce.vhd`-Fork aufgelöst (IV_v4-Fassung gilt); Board-IDs kollisionsfrei neu vergeben;
voller Compile aller fünf ohne Fehler. Die beiden S-Varianten ruhten und wurden nur an der
Board-ID-Ziffer angefasst.

### Etappe 2 – Umzug in die Zielstruktur — erledigt 27.07.2026

Nach `N:\Projekte\WillFA7` (seit 28.07.2026 `N:\Projekte\WillFA7\FPGA_source`, damit die Doku
daneben passt), Historie von `WillFA7 - CycloneIV_v4` als Basis. In zwölf Schritten,
jeder einzeln mit `check.ps1 -Fit` gegen die Zahlen des Vorschritts abgesichert:

| # | Inhalt | Ergebnis |
|---|---|---|
| 0 | Baseline im alten Baum | Referenz |
| 1 | Baum kopieren, `init_file`-Pfade reparieren | 4× identisch, Cyclone II −56 LE (cpu68) |
| 2 | `version_pkg` + `variant_pkg` mit `BOARD_ID` | 5× identisch |
| 3 | `R5101` Cyclone II auf `clock_a`/`clock_b` | 0 LE, 0 Bit |
| 4 | interne Display-Signale, Ports überall `out` | 5× identisch |
| 5 | gemeinsame Portliste + `VIRTUAL_PIN` | 0 bis +22 LE |
| 6 | ROM-Block über `ROM_COUNT` | 5× identisch |
| 7 | Monitor über `HAS_MONITOR` | 5× identisch |
| 8 | ein `top/WillFA7.vhd` | 5× identisch |
| 9 | `gen_qsf.ps1`, `.qsf` generiert | Assignments Zeile für Zeile identisch |
| 10 | S-Varianten in die Struktur | `s_cyclone_iv_v4` baut wieder |
| 11 | Version `.21`, Release nach `bin/` | – |
| 12 | Git, GitHub, Projektdoku | – |

## 4. Was anders kam als geplant

- **Bit-für-Bit-Vergleich der Binaries** war als Abnahmekriterium vorgesehen. Ab Schritt 5
  hält er nicht mehr: zusätzliche Ports und Generate-Labels ändern Knotennamen und damit
  Platzierung, ohne dass sich funktional etwas ändert. Kriterium wurde auf *identische
  LE / Memory Bits / Slack + unveränderte Warnungsliste* umgestellt. Bis Schritt 4 hat die
  Bit-Identität gehalten und wurde genutzt.
- **Cyclone II hatte einen eigenen, älteren `cpu68` v0.83** – entgegen der Notiz aus Etappe 1.
  Der Umzug auf `rtl/common/` hebt ihn auf v0.85. Bewusst so entschieden: das ist der Sinn
  eines Monorepos. Kostet keine Ressourcen, sondern spart 56 LE, ist aber ein echter
  Funktionsunterschied auf einem ungetesteten Board und steht deshalb in `changelog.txt`.
- **Quartus löst Entity-Referenzen auch im nicht genommenen `generate`-Zweig auf.** Die drei
  `rtl/serial_api/`-Dateien mussten deshalb in *jede* Dateiliste, nicht nur in die von
  `cyclone_iv_v3`. Sie kosten dort nachweislich 0 LE.
- **`s_cyclone_iv_v4` baut wieder.** Der in Etappe 1 als „echter VHDL-Fehler" notierte
  `Error (10349)` war nur eine Folge der nicht auflösbaren `.qip`-Pfade.
- **Cyclone II passte problemlos.** Die härteste Randbedingung des Plans – 95 % Auslastung –
  hat sich entschärft: die Variante steht jetzt bei 94 %.

## 5. Ziel-Workflow

1. Änderung in `rtl/common/` bzw. `top/WillFA7.vhd`.
2. `scripts\build.ps1 cyclone_iv_v4` → auf der v4-Platine in Hardware testen.
3. `scripts\check.ps1 -Fit` → alle aktiven Varianten, Ergebnistabelle gegen Baseline.
4. Sub-Version in `rtl/common/version_pkg.vhd` hochziehen.
5. `scripts\release.ps1 -Note "..."` → volle Compiles, `.jic`/`.pof` nach `bin/`, Changelog.
6. Ein Commit, ein Tag – alle Varianten konsistent.

## 6. Was offen bleibt

- **Hardwaretest von `.21`** – auf keinem Board erfolgt. Für Cyclone II kommt der cpu68-Wechsel
  dazu, siehe `VARIANTEN.md` Abschnitt 5.
- **`s_cyclone_iv_v4`**: baut, ruht, steht auf Funktionsstand `.03`. Wer sie aufnimmt, muss
  `.17` bis `.21` nachziehen und `local/` gegen `rtl/common/` auflösen.
- **`s_cyclone_10`**: unfertig, 0 Pin-Zuweisungen, `Error (10349)` auf `Audio_O`.
- **`variants/cyclone_ii/WillFA7.sdc`** ist eine von Quartus 13 generierte Datei, kein
  handgeschriebener Constraint-Satz wie bei den anderen vier.
- **Der alte Ordnerbaum** `N:\Projekte\WillFA\FPGA_source\` steht unverändert als vorläufiges
  Backup – er ist seit 28.07.2026 der einzige Inhalt von `N:\Projekte\WillFA`. Rückbau erst
  nach ausdrücklicher Freigabe und nach dem Hardwaretest.
