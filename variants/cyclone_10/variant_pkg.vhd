-- variant_pkg - everything the shared top level needs to know about THIS board.
-- Variant: cyclone_10 - WillFA7 on 10CL006YE144C8G, Cyclone 10 LP.
--
library ieee;
use ieee.std_logic_1164.all;

package variant_pkg is
	-- First digit of the displayed version. Formerly SW_MAIN in WillFA7.vhd.
	constant BOARD_ID : std_logic_vector(3 downto 0) := x"4";

	-- How many 2K ROM blocks this board has. CAREFUL: this also decides the SD
	-- card image format - 12 KByte, first 2K window at 5000h.
	-- A wrong value here does not break the build, it breaks the game at boot.
	constant ROM_COUNT : integer := 6;

	-- USB monitor API (rtl/serial_api). Costs about 550 logic elements, so it has
	-- to generate away rather than be optimised away - the EP2C5 has no room for it.
	constant HAS_MONITOR : boolean := false;

	-- Integrated sound board (rtl/sound). Only the WillFA7S boards have one. Pulls in
	-- the WISOF core with its own 6802, five 4 KByte ROM blocks, the CVSD speech
	-- decoder, the sound test and a 4x4 DIP matrix, and switches the SD card reader to
	-- 64 KByte slots with a CRC16. See docs/soundcard_variant.md.
	constant HAS_SOUND : boolean := false;
end package;
