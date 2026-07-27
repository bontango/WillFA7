-- variant_pkg - everything the shared top level needs to know about THIS board.
-- Variant: cyclone_iv_v4 - WillFA7 on EP4CE6E22C8, FPGA board v4.x.
-- This is the lead variant: development and hardware testing happen here.
--
library ieee;
use ieee.std_logic_1164.all;

package variant_pkg is
	-- First digit of the displayed version. Formerly SW_MAIN in WillFA7.vhd.
	constant BOARD_ID : std_logic_vector(3 downto 0) := x"3";
end package;
