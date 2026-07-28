# WORKFLOW.md – Arbeiten am WillFA7-Monorepo

Wie man an diesem Repo arbeitet: mit der Quartus-IDE, mit den Skripten, und wo die
Grenze zwischen beiden verläuft. Architektur und Regeln stehen in `CLAUDE.md`,
Varianten und bekannte Defekte in `VARIANTEN.md`.

## Wo liegt was

| Ort | Inhalt |
|---|---|
| `N:\Projekte\WillFA7\` | Projektordner: `PROJECT.md`, Handbücher, Schaltpläne, Target3001, ROMs, SD-Images, DEBUG |
| `N:\Projekte\WillFA7\FPGA_source\` | **dieses Repo** – Quellen, Skripte, Release-Binaries |
| `variants\<name>\WillFA7.qpf` | das Quartus-Projekt der jeweiligen Platine |

Das Repo endet bei `FPGA_source\`. Die Doku daneben ist bewusst nicht versioniert –
sonst lägen mehrere GB SD-Images im Arbeitsbaum.

## Quartus-IDE: ja, aber

Die IDE ist weiter der normale Weg zum Kompilieren, Ansehen und Programmieren.
Projekt öffnen, z. B. `variants\cyclone_iv_v4\WillFA7.qpf`, und arbeiten wie immer.

**Ohne Einschränkung:** VHDL im Editor bearbeiten und speichern, Compile, RTL Viewer,
TimeQuest, Programmer.

**Nicht in der IDE festlegen:** alles, was Assignments schreibt. `WillFA7.qsf` ist eine
generierte Datei und wird vom nächsten `gen_qsf.ps1` überschrieben.

| Was du in der IDE ändern willst | Wo es hingehört |
|---|---|
| Pinbelegung (Pin Planner) | `variants\<name>\pins.tcl` |
| Device oder Family | `variants\<name>\device.tcl` |
| Datei zum Projekt hinzufügen oder entfernen | `scripts\files_common.tcl`, `files_<family>.tcl`, `files_<option>.tcl` |
| globale Settings, Assignment Editor | `scripts\common_header.tcl` |
| VIRTUAL_PIN für nicht vorhandene Ports | `variants\<name>\variant.psd1` |
| SignalTap instanziieren | schreibt ebenfalls in die `.qsf` – vor dem nächsten `gen_qsf.ps1` sichern |

Danach `scripts\gen_qsf.ps1` und die Änderung steht in allen betroffenen Varianten.

**Nach einer IDE-Sitzung einmal `scripts\gen_qsf.ps1 -Check` laufen lassen.** Quartus
schreibt die `.qsf` bei manchen Aktionen von sich aus um. Der Check meldet in Sekunden,
ob die Datei von der generierten Fassung abweicht:

- Abweichung nicht gewollt → `scripts\gen_qsf.ps1` ausführen, überschreibt sie.
- Abweichung gewollt → ins passende `.tcl` übernehmen, dann generieren.

**Ausnahme: die beiden ruhenden Sound-Varianten.** `s_cyclone_iv_v4` und `s_cyclone_10`
stehen in `variant.psd1` auf `Generated = $false`. Ihre `.qsf` ist handgepflegt und wird
von `gen_qsf.ps1` nie angefasst – dort ist die IDE auch für Assignments der normale Weg.

## Eine Änderung von Anfang bis Ende

1. **Ändern** in `rtl\common\` oder `top\WillFA7.vhd` – im Quartus-Editor oder in einem
   beliebigen anderen. Beides sind normale Dateien.
   *Achtung:* `rtl\common\` gilt für **alle sieben** Varianten. Das ist der Sinn des
   Monorepos und zugleich das Risiko – eine Änderung trifft auch Boards, die du gerade
   nicht im Blick hast.
2. **Bauen und in Hardware testen**: `scripts\build.ps1 cyclone_iv_v4` (Leitvariante).
3. **Alle Varianten prüfen**: `scripts\check.ps1 -Fit`. Vergleicht LE, Memory Bits und
   Slack gegen `scripts\baseline.csv`. Exit 1 = Build-Fehler, Exit 2 = Baseline-Abweichung.
   Eine unerklärte Abweichung ist ein Befund, keine Formalie.
4. **Version hochziehen** in `rtl\common\version_pkg.vhd` (`SW_SUB1`/`SW_SUB2`).
5. **Release**: `scripts\release.ps1 -Note "..."` – volle Compiles, `.jic`/`.pof` nach
   `bin\`, Eintrag in `bin\changelog.txt`.
6. **Ein Commit** für alle Varianten zusammen.

Cyclone II ist die harte Randbedingung (94 % LE). Was dort nicht mehr passt, passt
nirgends – deshalb prüft Schritt 3 alle Varianten und nicht nur die, an der du gebaut hast.

## Die Skripte

```powershell
scripts\gen_qsf.ps1                    # alle WillFA7.qsf neu erzeugen
scripts\gen_qsf.ps1 -Check             # nur pruefen, ob sie aktuell sind
scripts\check.ps1                      # quartus_map, alle aktiven Varianten
scripts\check.ps1 -Fit                 # + Fitter/Timing + Baseline-Vergleich
scripts\check.ps1 -Variants cyclone_ii -Fit
scripts\build.ps1 cyclone_iv_v4        # voller Compile, .sof/.pof/.jic
scripts\release.ps1 -Note "..."        # alles bauen, nach bin/ ablegen, changelog
```

`quartus_sh` ist nicht im PATH. Die Skripte kennen die Pfade selbst: `C:\altera\13.0sp1`
für Cyclone II, `C:\intelFPGA_lite\22.1std` für alle anderen. Sie arbeiten relativ zu
ihrem eigenen Ort, du kannst sie also aus jedem Verzeichnis aufrufen.

## Die Baseline

`scripts\baseline.csv` ist das Sicherheitsnetz: je Variante die erwarteten LE, Memory
Bits und der Slack. `check.ps1 -Fit` vergleicht dagegen.

- **Slack schwankt.** Zwei Läufe über byte-identische Quellen ergaben 5.690 und 6.791 ns;
  die Toleranz steht deshalb bei 1.5 ns, zusätzlich gibt es einen absoluten Boden von 1.0 ns.
- **LE schwanken nicht.** Eine Abweichung dort hat immer eine Ursache. Schon eine geänderte
  Konstante zählt: `SW_SUB2` von `x"0"` auf `x"1"` (Release `.21`) ist 15 LE wert.
- Nach einem Release, das die Zahlen bewusst verschiebt, gehört die Baseline neu gemessen –
  sonst schlägt sie bei jeder späteren Prüfung an und wird irgendwann ignoriert.

**Stand:** `baseline.csv` hält noch die Zahlen von `.20`. Auf `.21` ist sie nicht
nachgemessen, `cyclone_iv_v4` meldet deshalb `LE -15`.

## Git

Das Repo ist `N:\Projekte\WillFA7\FPGA_source` → `github.com/bontango/WillFA7`,
Branch `main`. Weil es auf einem Netzlaufwerk liegt, braucht der Pfad einen Eintrag in
`git config --global safe.directory` – ohne den verweigert Git jede Operation
("dubious ownership"). Bei einem Umzug des Ordners muss der Eintrag mitwandern.

Nicht im Repo, bewusst: `PROJECT.md` (liegt im Projektordner darüber), die Doku daneben,
`output_files\`, `db\`, `incremental_db\` und `WillFA7.pin` (Build-Artefakte).
