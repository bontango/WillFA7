-- variant_pkg - everything the shared top level needs to know about THIS board.
-- Variant: cyclone_iv_dev_open - WillFA7 on an off-the-shelf EP4CE6E22C8 dev board.
--
library ieee;
use ieee.std_logic_1164.all;

package variant_pkg is
	-- First digit of the displayed version. Formerly SW_MAIN in WillFA7.vhd.
	-- Was 4 until 07.2026 and collided with cyclone_10.
	constant BOARD_ID : std_logic_vector(3 downto 0) := x"5";

	-- How many 2K ROM blocks this board has. Six means the full 5000h-7FFFh, so every
	-- game runs, Defender and Star Light included.
	-- Since .22 this no longer decides the card format - there is only one, see
	-- SD_CHECK_CRC below.
	constant ROM_COUNT : integer := 6;

	-- USB monitor API (rtl/serial_api). Costs about 550 logic elements, so it has
	-- to generate away rather than be optimised away - the EP2C5 has no room for it.
	constant HAS_MONITOR : boolean := false;

	-- Integrated sound board (rtl/sound). Only the WillFA7S boards have one. Pulls in
	-- the WISOF core with its own 6802, five 4 KByte ROM blocks, the CVSD speech
	-- decoder, the sound test and a 4x4 DIP matrix. See docs/soundcard_variant.md.
	constant HAS_SOUND : boolean := false;

	-- Check the CRC16-CCITT the card carries in the last two bytes of the 64 KByte
	-- slot. One card format for every board since .22 - docs/soundcard_variant.md.
	-- The only reason to turn this off is logic elements, which is a Cyclone II topic.
	constant SD_CHECK_CRC : boolean := true;
end package;
