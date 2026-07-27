# s_cyclone_iv_v4 – WillFA7S HW1.0 with sound board

**Dormant, but it builds again.** Fixing the file paths during the move turned out to be
enough:

```
5,392 / 10,320 logic elements (52 %)   273,408 / 423,936 memory bits   slack 3.600 ns
```

**Building is not the same as working.** This variant is still on function level `.03`,
it uses the old copies of `cpu68`, `EEprom` and friends under `local/`, and it has not
been tested in hardware. It stays `Dormant`: whoever picks it up starts at `.03`, not at
the `.21` the five active variants are on.

## What is different about it

Unlike the five active variants it does **not** use `top/WillFA7.vhd` and it does **not**
use `rtl/common/`. It has:

- its own `WillFA7.vhd` – roughly 300 lines of real difference from the shared top level,
  because of the sound board
- `local/` – its own frozen copies of the common modules (`cpu68`, `pia6821`, `EEprom`,
  `boot_message`, …) and of the Cyclone IV megafunctions. These are **older** than what
  is in `rtl/common/` today. Do not assume they are interchangeable.
- `rtl/sound/` – the sound board modules (`dac`, `hc55564`, `WISOF`, `crc16_ccitt`) plus
  the `SD_Card` and `SPI_Master` versions this board was built against, which are again
  not the ones in `rtl/common/`
- `rtl/cyclone_iv_s/` – `MPU_RAM`, `SB_ROM` and a `williams_pll` generated differently
  from the one in `rtl/cyclone_iv/`

`WillFA7.qsf` here is **hand maintained**, not generated. `gen_qsf.ps1` skips this folder
(`Generated = $false` in `variant.psd1`), and `check.ps1` / `build.ps1` skip it unless
`-All` is given.

## Why it used to fail, and why that was misleading

The `.qip` and `.vhd` paths pointed at `../lib_cyclone_IV/` and `../lib_common/` while the
files actually lived in the `_S` folders. `WISOF.vhd` and `crc16_ccitt.vhd` were therefore
missing from the project entirely.

The error Quartus reported for that was `WillFA7.vhd:430, Error (10349) - formal
calc_checksum does not exist`, which reads like a broken port list and sent the earlier
survey looking in the wrong place. It was a knock-on effect: with `crc16_ccitt` absent,
the instantiation could not resolve. Fixing the paths made it go away.

Lesson for the sibling variant: an `Error (10349)` here does not necessarily mean the VHDL
is wrong.

## Version

6.03. Only the board ID digit was changed (from 5 to 6, in 07.2026, to make the numbering
collision free). The function level is untouched and is **not** on `.21` like the active
variants. It does not read `variant_pkg.vhd`; its version is a constant in its own
`WillFA7.vhd`.
