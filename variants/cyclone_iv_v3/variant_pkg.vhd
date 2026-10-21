-- variant_pkg - everything the shared top level needs to know about THIS board.
-- Variant: cyclone_iv_v3 - WillFA7 on EP4CE6F17C8, FPGA board v3.x.
--
library ieee;
use ieee.std_logic_1164.all;

package variant_pkg is
	-- First digit of the displayed version. Formerly SW_MAIN in WillFA7.vhd.
	constant BOARD_ID : std_logic_vector(3 downto 0) := x"2";

	-- How many 2K ROM blocks this board has. Six means the full 5000h-7FFFh, so every
	-- game runs, Defender and Star Light included.
	-- Since .22 this no longer decides the card format - there is only one, see
	-- SD_CHECK_CRC below.
	constant ROM_COUNT : integer := 6;

	-- USB monitor API (rtl/serial_api). Costs about 550 logic elements, so it has
	-- to generate away rather than be optimised away - the EP2C5 has no room for it.
	constant HAS_MONITOR : boolean := true;

	-- Integrated sound board (rtl/sound). Only the WillFA7S boards have one. Pulls in
	-- the WISOF core with its own 6802, five 4 KByte ROM blocks, the CVSD speech
	-- decoder, the sound test and a 4x4 DIP matrix. See docs/soundcard_variant.md.
	constant HAS_SOUND : boolean := false;

	-- CRC16-CCITT check of the SD card. Off on every board since x.30: the card is the
	-- x.20 one again (12 KByte slots, no CRC). The logic stays in SD_Card.vhd.
	constant SD_CHECK_CRC : boolean := false;

	-- Game ROMs from the configuration flash when no SD card answers
	-- (rtl/common/Flash_ROM.vhd). EPCS16 on this board too, same layout as WillFA7S:
	-- game n at 080000h + n * 8000h, of which only the 12 KByte MPU part is read.
	-- The flash pins are released in device.tcl, placed in pins.tcl.
	constant HAS_FLASH_ROM : boolean := true;
end package;
