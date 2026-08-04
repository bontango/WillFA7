-- variant_pkg - everything the shared top level needs to know about THIS board.
-- Variant: s_cyclone_iv_v4 - WillFA7S HW1.0 on EP4CE10E22C8, with integrated sound board.
--
-- What the sound board changes about this variant is collected in
-- docs/soundcard_variant.md. Short version: same MPU, same 78 of 82 pins, but a
-- second 6802 with its own ROMs on the die and a 4x4 DIP matrix instead of 4x3.
-- The 64 KByte card format used to be on that list; since .22 every board reads it.
--
library ieee;
use ieee.std_logic_1164.all;

package variant_pkg is
	-- First digit of the displayed version. Formerly SW_MAIN in WillFA7.vhd.
	constant BOARD_ID : std_logic_vector(3 downto 0) := x"6";

	-- How many 2K ROM blocks this board has. Six means the full 5000h-7FFFh, so every
	-- game runs, Defender and Star Light included. Those 12 KByte are the first part
	-- of the 64 KByte slot; behind them sit the sound board ROMs, which only this
	-- board decodes. docs/soundcard_variant.md
	constant ROM_COUNT : integer := 6;

	-- USB monitor API (rtl/serial_api). Costs about 550 logic elements, so it has
	-- to generate away rather than be optimised away - the EP2C5 has no room for it.
	constant HAS_MONITOR : boolean := false;

	-- Integrated sound board (rtl/sound). Pulls in the WISOF core with its own 6802,
	-- five 4 KByte ROM blocks, the CVSD speech decoder, the sound test and the 4x4
	-- DIP matrix. It is also the only board that decodes bytes 12K..32K of the slot.
	constant HAS_SOUND : boolean := true;

	-- Check the CRC16-CCITT the card carries in the last two bytes of the 64 KByte
	-- slot. This board has done so since 6.03 and every other one does since .22 -
	-- docs/soundcard_variant.md.
	constant SD_CHECK_CRC : boolean := true;
end package;
