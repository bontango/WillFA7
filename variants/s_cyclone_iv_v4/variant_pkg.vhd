-- variant_pkg - everything the shared top level needs to know about THIS board.
-- Variant: s_cyclone_iv_v4 - WillFA7S HW1.0 on EP4CE10E22C8, with integrated sound board.
--
-- What the sound board changes about this variant is collected in
-- docs/soundcard_variant.md. Short version: same MPU, same 78 of 82 pins, but a
-- second 6802 with its own ROMs on the die, a 4x4 DIP matrix instead of 4x3 and a
-- different SD card format (64 KByte slots with a CRC).
--
library ieee;
use ieee.std_logic_1164.all;

package variant_pkg is
	-- First digit of the displayed version. Formerly SW_MAIN in WillFA7.vhd.
	constant BOARD_ID : std_logic_vector(3 downto 0) := x"6";

	-- How many 2K ROM blocks this board has. CAREFUL: this also decides the SD
	-- card image format - 12 KByte, first 2K window at 5000h.
	-- A wrong value here does not break the build, it breaks the game at boot.
	-- On this board those 12 KByte are the first part of a 64 KByte slot, see
	-- HAS_SOUND below and docs/soundcard_variant.md.
	constant ROM_COUNT : integer := 6;

	-- USB monitor API (rtl/serial_api). Costs about 550 logic elements, so it has
	-- to generate away rather than be optimised away - the EP2C5 has no room for it.
	constant HAS_MONITOR : boolean := false;

	-- Integrated sound board (rtl/sound). Pulls in the WISOF core with its own 6802,
	-- five 4 KByte ROM blocks, the CVSD speech decoder, the sound test and the 4x4
	-- DIP matrix, and switches the SD card reader to 64 KByte slots with a CRC16.
	constant HAS_SOUND : boolean := true;
end package;
