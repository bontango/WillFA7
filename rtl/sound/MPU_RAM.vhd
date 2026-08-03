-- MPU_RAM - the 128 byte RAM that sits inside a real 6802
-- for the WillFA7S sound board (rtl/sound/WISOF.vhd)
-- bontango - www.lisy.dev
--
-- Plain inferred VHDL, NOT an Altera megafunction, and that is deliberate:
-- WISOF is instantiated inside 'if HAS_SOUND generate' in the top level, and Quartus
-- resolves entity references in a not taken generate branch as well. MPU_RAM and
-- SB_ROM therefore have to be part of EVERY variant's file list - including the
-- Cyclone II and Cyclone 10 ones, where a megafunction generated for Cyclone IV E
-- has no business being. Inferred memory has no device family in it.
--
-- Behaviour matches the megafunction it replaces (rtl/cyclone_iv_s/MPU_RAM.vhd):
-- single port, registered address, unregistered output, write-first
-- (read_during_write_mode_port_a = NEW_DATA_NO_NBE_READ).
--
-- Quartus maps this to one block RAM. If the memory bit count in
-- scripts/baseline.csv ever drops, it has fallen back to logic elements instead -
-- that is a finding, not a detail.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity MPU_RAM is
	port(
		address	: in  std_logic_vector(6 downto 0);
		clock	: in  std_logic := '1';
		data	: in  std_logic_vector(7 downto 0);
		wren	: in  std_logic;
		q		: out std_logic_vector(7 downto 0)
	);
end MPU_RAM;

architecture rtl of MPU_RAM is
	type ram_t is array(0 to 127) of std_logic_vector(7 downto 0);
	signal ram : ram_t;
begin

	process(clock)
	begin
		if rising_edge(clock) then
			if wren = '1' then
				ram(to_integer(unsigned(address))) <= data;
				q <= data;	-- write first, same as NEW_DATA on the megafunction
			else
				q <= ram(to_integer(unsigned(address)));
			end if;
		end if;
	end process;

end rtl;
