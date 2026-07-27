-- variant_pkg - everything the shared top level needs to know about THIS board.
-- Variant: cyclone_10 - WillFA7 on 10CL006YE144C8G, Cyclone 10 LP.
--
library ieee;
use ieee.std_logic_1164.all;

package variant_pkg is
	-- First digit of the displayed version. Formerly SW_MAIN in WillFA7.vhd.
	constant BOARD_ID : std_logic_vector(3 downto 0) := x"4";
end package;
