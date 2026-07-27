---
titel:   WillFA7 - Williams SYS3-7 MPU-Ersatz (FPGA)
status:  aktiv
art:     fpga
system:  'Williams'
tools:   [Quartus, VHDL, PowerShell]
pfade:
  - N:\Projekte\WillFA7
github:  https://github.com/bontango/WillFA7
swrep:   https://lisy.dev/swrep/WillFA7
release: '3.21'
---

## Worum geht es?

FPGA-Nachbau der Williams-MPU System 3 bis 7. Ein Sourcebaum, ein Top-Level, sieben
Platinenvarianten (Cyclone II, drei Cyclone IV, Cyclone 10, zwei mit Soundkarte).
Die Platine lädt die Spiel-ROMs von SD-Karte, hält die Einstellungen in einem SPI-EEPROM
und treibt Treiberplatine, Displays, Switch-Matrix und Solenoide der Maschine.

## Aktueller Stand

Seit 27.07.2026 Monorepo (Etappe 2 aus `PLAN_Zielstruktur.md`). Vorher lagen sieben
getrennte Quartus-Projekte mit je eigener Kopie der gemeinsamen Module unter
`N:\Projekte\WillFA\FPGA_source\`.

- Fünf aktive Varianten auf Funktionsstand `.21`, alle bauen fehlerfrei.
- `s_cyclone_iv_v4` (6.03) baut seit dem Umzug wieder, ruht aber.
- `s_cyclone_10` (7.14) ruht und ist unfertig.
- **`.21` ist auf keinem Board in Hardware getestet.** Letzter getesteter Stand: 3.20.

Einstieg: `CLAUDE.md` (Architektur und Regeln), `VARIANTEN.md` (Varianten und Defekte),
`README.md` (öffentliche Kurzfassung).

## Wo liegt was?

| Ort | Inhalt |
|---|---|
| `N:\Projekte\WillFA7\` | dieses Repo – Quellen, Skripte, Release-Binaries, Doku |
| `N:\Projekte\WillFA\FPGA_source\` | **alter Ordnerbaum**, bleibt als Fallback stehen |
| `N:\Projekte\WillFA\FPGA_source\archive src\` | ~630 MB historische Projektstände, bewusst nicht im Repo |
| `N:\Projekte\WillFA\` | Handbücher, Schaltpläne, Target3001, ROMs, SD-Images, WillFA11 |

## Git-Repos

- `N:\Projekte\WillFA7` → https://github.com/bontango/WillFA7 (Monorepo, aktiv)
- abgelöst: `WillFA7_CycloneIV_v4`, `WillFA7---CycloneIV_v3` (auf GitHub archiviert)

## Hinweise

Konventionen: `N:\Projekte\_Uebersicht\KONVENTIONEN.md`
