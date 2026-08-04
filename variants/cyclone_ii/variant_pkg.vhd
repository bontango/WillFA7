-- variant_pkg - everything the shared top level needs to know about THIS board.
-- Variant: cyclone_ii - WillFA7 on EP2C5T144C8, Quartus 13.0sp1.
--
-- Careful: this device is at 95 % logic elements. Check every addition with
-- quartus_fit before committing.
--
library ieee;
use ieee.std_logic_1164.all;

package variant_pkg is
	-- First digit of the displayed version. Formerly SW_MAIN in WillFA7.vhd.
	constant BOARD_ID : std_logic_vector(3 downto 0) := x"1";

	-- How many 2K ROM blocks this board has. Five means there is no rom0: window 0 of
	-- the card image is read and dropped, 5000h-57FF reads FF, and the games that need
	-- the full 12 KByte (Defender, Star Light) do not run on this board.
	-- Since .22 this no longer decides the card format - there is only one, see
	-- SD_CHECK_CRC below.
	constant ROM_COUNT : integer := 5;

	-- USB monitor API (rtl/serial_api). Costs about 550 logic elements, so it has
	-- to generate away rather than be optimised away - the EP2C5 has no room for it.
	constant HAS_MONITOR : boolean := false;

	-- Integrated sound board (rtl/sound). Only the WillFA7S boards have one. Pulls in
	-- the WISOF core with its own 6802, five 4 KByte ROM blocks, the CVSD speech
	-- decoder, the sound test and a 4x4 DIP matrix. See docs/soundcard_variant.md.
	constant HAS_SOUND : boolean := false;

	-- Check the CRC16-CCITT the card carries in the last two bytes of the 64 KByte
	-- slot. One card format for every board since .22, so this is on everywhere; the
	-- only reason to turn it off is logic elements, and this is the only board that is
	-- anywhere near the limit. Off means: same card, same slots, but the read stops
	-- after the MPU payload and a corrupt card is not noticed. The boot display then
	-- keeps the build date instead of the two checksums.
	constant SD_CHECK_CRC : boolean := true;
end package;
