-- SB_ROM - one 4 KByte sound board ROM block, filled from SD at boot
-- for the WillFA7S sound board (rtl/sound/WISOF.vhd), instantiated five times
-- bontango - www.lisy.dev
--
-- Plain inferred VHDL, NOT an Altera megafunction - same reason as MPU_RAM.vhd,
-- read the header there.
--
-- Behaviour matches the megafunction it replaces (rtl/cyclone_iv_s/SB_ROM.vhd):
-- single port, registered address, unregistered output, write-first.
--
-- Called ROM because that is what it is to the sound board CPU; it is writable only
-- while the SD card reader fills it during boot phase 2.
--
-- Five of these are 163,840 memory bits. That, not the logic, is why the WillFA7S
-- needs an EP4CE10 where the plain v4 board gets by with an EP4CE6.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SB_ROM is
	port(
		address	: in  std_logic_vector(11 downto 0);
		clock	: in  std_logic := '1';
		data	: in  std_logic_vector(7 downto 0);
		wren	: in  std_logic;
		q		: out std_logic_vector(7 downto 0)
	);
end SB_ROM;

architecture rtl of SB_ROM is
	type rom_t is array(0 to 4095) of std_logic_vector(7 downto 0);
	signal rom : rom_t;
begin

	process(clock)
	begin
		if rising_edge(clock) then
			if wren = '1' then
				rom(to_integer(unsigned(address))) <= data;
				q <= data;	-- write first, same as NEW_DATA on the megafunction
			else
				q <= rom(to_integer(unsigned(address)));
			end if;
		end if;
	end process;

end rtl;
