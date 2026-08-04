# WillFA7

A Williams System 3 to System 7 pinball MPU replacement on a low cost Altera FPGA.
VHDL, Quartus. By Ralf Thelen (bontango), <https://www.lisy.dev>.

The board loads the game ROMs from an SD card, keeps the game settings in an SPI
EEPROM and drives the original driver board, displays, switch matrix and solenoids
of the machine.

## One design, six boards

The same design runs on six different FPGA boards. They share **one** top level
(`top/WillFA7.vhd`) and one source tree; what differs per board is a handful of pin
locations, the FPGA device and five constants in `variants/<name>/variant_pkg.vhd`.

One of the boards, the WillFA7S, carries a complete Williams sound board on the same FPGA -
a second 6802 with its own ROMs, a delta sigma DAC and a CVSD speech decoder. That is the
`HAS_SOUND` constant; what it changes is written up in `docs/soundcard_variant.md`.

| Variant | Version | FPGA | Quartus | State |
|---|---|---|---|---|
| `cyclone_ii` | 1.22 | EP2C5T144C8 | 13.0sp1 | active, 96 % logic elements |
| `cyclone_iv_v3` | 2.22 | EP4CE6F17C8 | 22.1std | active, has the USB monitor API |
| `cyclone_iv_v4` | 3.22 | EP4CE6E22C8 | 22.1std | active, **lead variant** |
| `cyclone_10` | 4.22 | 10CL006YE144C8G | 22.1std | active |
| `cyclone_iv_dev_open` | 5.22 | EP4CE6E22C8 | 22.1std | active, off-the-shelf dev board |
| `s_cyclone_iv_v4` | 6.22 | EP4CE10E22C8 | 22.1std | active, **integrated sound board** |

The displayed version is `BOARD_ID.SW_SUB1 SW_SUB2`: the first digit identifies the
board (`variants/<name>/variant_pkg.vhd`), the last two are the common function
level for all variants (`rtl/common/version_pkg.vhd`). One release changes one
number and every board follows.

## Layout

```
rtl/common/      the modules every variant uses, plus version_pkg.vhd
rtl/cyclone_ii/  rtl/cyclone_iv/  rtl/cyclone_10/   family megafunctions,
                 same entity names everywhere - the family is chosen by the .qsf
rtl/serial_api/  USB monitor API (HAS_MONITOR)
rtl/sound/       sound board modules (HAS_SOUND)
top/WillFA7.vhd  the one top level
top/WillFA7_cii.vhd  board shell for Cyclone II, where VIRTUAL_PIN does not work
variants/<name>/ variant_pkg.vhd, device.tcl, pins.tcl, variant.psd1,
                 WillFA7.sdc, WillFA7.qpf, willfa7.cof, generated WillFA7.qsf
scripts/         gen_qsf.ps1, check.ps1, build.ps1, release.ps1 and the file lists
bin/             release binaries and changelog.txt
docs/            analyses (switch masks, blanking, EEprom, special solenoids) and the
                 two user manuals, WillFA7 and WillFA7S
archive/         historic module versions, not part of any build
```

## Building

`quartus_sh` is not on the PATH; the scripts know where the two installations are.
Cyclone II needs Quartus 13.0sp1, everything else 22.1std.

```powershell
scripts\gen_qsf.ps1                      # regenerate every WillFA7.qsf
scripts\check.ps1                        # Analysis & Synthesis, all active variants
scripts\check.ps1 -Fit                   # plus fitter and timing, with baseline check
scripts\build.ps1 cyclone_iv_v4          # full compile, produces .sof/.pof/.jic
scripts\release.ps1 -All                 # build everything, file it under bin/
```

`check.ps1 -Fit` compares logic elements, memory bits and setup slack against
`scripts/baseline.csv` and complains about any drift. That is the safety net that
makes a change to `rtl/common/` reviewable across all boards at once.

**Never edit `variants/<name>/WillFA7.qsf`** - it is generated. Change `device.tcl`,
`pins.tcl`, `variant.psd1` or the `scripts/files_*.tcl` lists and rerun `gen_qsf.ps1`.

## Third party cores

`cpu68` (Motorola 6800/6801) and `pia6821` come from OpenCores.org (John E. Kent),
GNU GPL, with bug fixes by bontango. The Altera IP (ALTPLL, altsyncram) is
regenerated with the Quartus MegaWizard.
