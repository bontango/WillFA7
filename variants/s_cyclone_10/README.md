# s_cyclone_10 – WillFA7S HW1.0 with sound board, Cyclone 10 LP

**Dormant and unfinished. This variant does not build.** It is in the repository so the
structure is complete, not so that it can be compiled today.

## What is different about it

Unlike the five active variants it does **not** use `top/WillFA7.vhd` and it does **not**
use `rtl/common/`. It has its own `WillFA7.vhd`, its own frozen copies of the common
modules and of the megafunctions under `local/`, and it pulls the sound board modules
from `rtl/sound/` and `rtl/cyclone_10_s/`.

`WillFA7.qsf` here is **hand maintained**, not generated. `gen_qsf.ps1` skips this folder
(`Generated = $false` in `variant.psd1`), and `check.ps1` / `build.ps1` skip it unless
`-All` is given.

## Why it does not build

1. The `.qip` and `.vhd` paths pointed at `../lib_cyclone_IV/` and `../lib_common/` while
   the files lived elsewhere. Worse, this is a Cyclone 10 project that referenced the
   **Cyclone IV** megafunctions. **Both are fixed** – the paths now resolve and point at
   `rtl/cyclone_10_s/` and `rtl/sound/`. The old symptom (`Error (10481)`, `work` contains
   no primary unit `WISOF`) is gone with them.

2. Underneath that sits the actual defect. As of 27.07.2026, `quartus_map` reports:

   `WillFA7.vhd:1170`, `Error (10349)` – formal `Audio_O` does not exist. The port list of
   the instantiated entity does not match the instantiation.

   Note that the sibling variant `s_cyclone_iv_v4` produced a very similar looking 10349
   which turned out to be nothing but a missing file. Check the file list before assuming
   this one is a genuine port list mismatch.

3. **The `.qsf` has zero pin assignments.** Even if it compiled, nothing would be wired to
   the board.

The variant was never finished. Anyone reopening it should treat it as a starting point,
not as something that regressed.

## Version

7.14. Only the board ID digit was changed (from 3 to 7, in 07.2026). The version is
hard coded in the `boot_message` call in its own `WillFA7.vhd`, not in a constant, and
it does not read `variant_pkg.vhd`.
