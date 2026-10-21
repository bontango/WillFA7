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

	-- CRC16-CCITT check of the SD card. Off on every board since x.30: the card is the
	-- x.20 one again (12 KByte slots, no CRC). The logic stays in SD_Card.vhd.
	constant SD_CHECK_CRC : boolean := false;

	-- Game ROMs from the configuration flash when no SD card answers
	-- (rtl/common/Flash_ROM.vhd). EPCS4 here: compact 10 KByte slots from 030000h
	-- (FL_BASE in top/WillFA7.vhd, follows ROM_COUNT = 5). The flash is reached through
	-- the ASMI block in top/WillFA7_cii.vhd - DCLK and DATA0 have no user I/O on this
	-- device.
	constant HAS_FLASH_ROM : boolean := true;
end package;
