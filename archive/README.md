# archive/

Historic module versions, kept for traceability only. **Nothing in here is part of
any build** - no `.qsf` references these files.

Notable entries:

| File | Why it is kept |
|---|---|
| `cpu68_v08.vhd`, `cpu68_v084.vhd`, `cpu68_v083_cyclone_ii.vhd` | Older CPU cores. `cpu68_v083_cyclone_ii.vhd` is what the Cyclone II variant used up to v1.20, before the monorepo put every variant on the shared `rtl/common/cpu68.vhd` (v0.85). |
| `sw_debounce_lockout_v0.1.vhd` | The confirm+lockout debouncer from the dev_open fork. The per-game mask version in `rtl/common/sw_debounce.vhd` won (hardware verified on Alien Poker). |
| `lisy_api.vhd`, `lisy_test_api.vhd` | Serial API experiments, never referenced by a `.qsf`. |
| `boot_message_v00/v01.vhd`, `read_the_dips - v00.vhd`, `EEprom_v07_test.vhd` | Superseded early versions. |
| `WillFA7_*.sdc` | Older timing constraint sets. The live ones are `variants/<name>/WillFA7.sdc`. |
| `cmos.vhd`/`.qip`/`.cmp` | The pre-`R5101` name of the CMOS RAM megafunction. |

Large historic project trees (the former `archive src\`, about 630 MB) are deliberately
**not** in this repository. They sit in `N:\Projekte\WillFA\FPGA_source\archive src\`, which
is a temporary backup of the pre-monorepo tree and is meant to go away eventually.
