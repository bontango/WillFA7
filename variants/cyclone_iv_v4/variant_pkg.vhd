-- variant_pkg - everything the shared top level needs to know about THIS board.
-- Variant: cyclone_iv_v4 - WillFA7 on EP4CE6E22C8, FPGA board v4.x.
-- This is the lead variant: development and hardware testing happen here.
--
library ieee;
use ieee.std_logic_1164.all;

package variant_pkg is
	-- First digit of the displayed version. Formerly SW_MAIN in WillFA7.vhd.
	constant BOARD_ID : std_logic_vector(3 downto 0) := x"3";

	-- How many 2K ROM blocks this board has. CAREFUL: this also decides the SD
	-- card image format - 12 KByte, first 2K window at 5000h.
	-- A wrong value here does not break the build, it breaks the game at boot.
	constant ROM_COUNT : integer := 6;

	-- USB monitor API (rtl/serial_api). Costs about 550 logic elements, so it has
	-- to generate away rather than be optimised away - the EP2C5 has no room for it.
	constant HAS_MONITOR : boolean := false;
end package;
