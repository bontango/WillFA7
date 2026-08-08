# s_cyclone_iv_v4 – WillFA7S HW1.0 with sound board

**Active since `.22`.** This used to be a dormant fork on function level `.03` with its own
top level and its own frozen copies of the common modules under `local/`. It is now an ordinary
variant of the shared source tree:

```
6,377 / 10,320 logic elements (62 %)   275,456 / 423,936 memory bits   36 / 46 M9K   slack 6.358 ns
```

Same `top/WillFA7.vhd`, same `rtl/common/`, generated `.qsf`, version from the packages -> 6.22.

**Still untested in hardware.** No board has run `.21` or `.22`; the last hardware tested build
is 3.20 on the plain Cyclone IV v4 board. What to check is listed in `VARIANTEN.md` section 5.

## What the sound board changes

Everything is collected in **`../../docs/soundcard_variant.md`**. The short version:

- **Four pins.** PIN_34/39/42 carry `SB_Sound`/`SB_Speech`/`SB_Test` instead of the DIP strobes,
  PIN_11 carries a fourth DIP return. The other 78 are identical to `cyclone_iv_v4`.
- **A 4x4 DIP matrix** instead of 4x3, with the strobes multiplexed onto `sw_strobe(7,5,3,1)`
  during boot phase 1. Read once, not continuously - **DIP changes need a restart.**
- **A different SD card format**: 64 KByte per game instead of 12, with a CRC16-CCITT in the
  last two bytes of the slot. A standard card does not boot here, and this card does not boot
  on a standard board.
- **A second 6802** (`rtl/sound/WISOF.vhd`) with its own PIA, 128 byte RAM, five 4 KByte ROM
  blocks, a CVSD speech decoder and one delta sigma DAC carrying sound and speech mixed.
  Only `SB_Sound` reaches the amplifier on this board; `SB_Speech` is pinned but idle.
- **A sound test** on `SB_Test`, which takes over the display.

## Three things to know before changing anything

1. **`WISOF` uses `cpu68`, `pia6821`, `one_pulse_only` and `Cross_Slow_To_Fast_Clock` from
   `rtl/common/`.** A change there hits both CPUs, the MPU one and the sound board one.
2. **The sound board core is foreign code with a version history of its own.** It comes from
   `N:\Projekte\Soundboards\FPGA Soundboard Williams\WISOF` and is at **0.9**. Do not simply
   copy the file from there - that one is a standalone board with its own SD card, PLL and
   LEDs. What has to be taken off is in `soundcard_variant.md`, section 14.
3. **This folder's `WillFA7.sdc` is not byte identical to the lead variant's.** It has two
   `set_false_path` lines appended for the audio outputs. Without them the build is formally
   "timing not met" on a path that does not physically exist - see `soundcard_variant.md`,
   section 11.

## Why the EP4CE10

**Two independent reasons, not one.** An EP4CE6E22C8 has 6,272 logic elements and 30 M9K blocks.

- **Memory.** What counts is blocks, not bits: at 8 bit width only 8,192 of an M9K's 9,216 bits
  are usable, the ninth column is parity. The ROM alone - 20 KByte sound plus 12 KByte MPU -
  therefore needs **exactly 32 M9K, and the EP4CE6 has 30**. Two blocks short before a single
  byte of RAM. Both ROM groups are packed 100 %, so there is nothing to regain by rearranging,
  and Cyclone IV E has no MLAB, so even the sound 6802's 128 byte RAM costs a full block.
- **Logic.** At fork level 6.03 this was 5,392 LE and the note here read "not the logic". Since
  `.22` it is **6,377 LE - 105 more than an EP4CE6 has at all.**

External memory - SPI RAM, QSPI PSRAM - would fix the first and make the second worse, since its
controller costs LEs; parallel SRAM needs 28 pins and only 10 are free. The full arithmetic,
including the options that were checked and rejected, is in
**`../../docs/memory_budget_willfa7s.md`**.

## Where the old state went

`../../archive/s_cyclone_iv_v4_603/` holds the 6.03 top level, its `local/` modules, the forked
`SD_Card`/`SPI_Master` and the Cyclone IV E megafunctions for `MPU_RAM`/`SB_ROM` that the
inferred VHDL in `rtl/sound/` replaced.
