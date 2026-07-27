-- variant_pkg - everything the shared top level needs to know about THIS board.
-- Variant: cyclone_iv_dev_open - WillFA7 on an off-the-shelf EP4CE6E22C8 dev board.
--
library ieee;
use ieee.std_logic_1164.all;

package variant_pkg is
	-- First digit of the displayed version. Formerly SW_MAIN in WillFA7.vhd.
	-- Was 4 until 07.2026 and collided with cyclone_10.
	constant BOARD_ID : std_logic_vector(3 downto 0) := x"5";
end package;
