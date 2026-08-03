-- HC55516/HC55564 Continuously Variable Slope Delta decoder
-- (c)2015 vlait
--
-- This is free software: you can redistribute
-- it and/or modify it under the terms of the GNU General
-- Public License as published by the Free Software
-- Foundation, either version 3 of the License, or (at your
-- option) any later version.
--
-- This is distributed in the hope that it will
-- be useful, but WITHOUT ANY WARRANTY; without even the
-- implied warranty of MERCHANTABILITY or FITNESS FOR A
-- PARTICULAR PURPOSE. See the GNU General Public License
-- for more details.
--
-- WISOF 0.9, findings F1 and F3 of its docs/vhdl_review.md:
--  * h and b were written as (1 - 1/8)*256 and (1 - 1/256)*256. Those are integer
--    divisions in VHDL, both 1/8 and 1/256 evaluate to 0, so both constants came out
--    as 256 and neither filter had any decay at all. Now written as the intended
--    values 224 and 255.
--  * the integrator is bipolar. It used to be unsigned, so its rest position was the
--    bottom of the DAC range and every downward excursion underflowed and was forced
--    to zero - a half wave rectified signal instead of speech. It is signed now and
--    saturates at both ends. sample_out is therefore a *signed* 16 bit value.
--  * synchronous reset (rst, active low): x starts at zero and s at s_min, so the
--    first syllables use a defined step size.
--  * bit_in removed from the sensitivity list, it had no effect for synthesis but made
--    RTL and gate level simulation differ.
--
-- Sign convention kept as it was: bit_in = '1' moves the integrator up, which is what
-- the HC55516 data sheet describes. PinMAME negates instead (sum = -sum). That is an
-- overall phase inversion of the speech channel, inaudible on its own and also when
-- summed with the uncorrelated DAC sound in WISOF.vhd.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hc55564 is
port
(
	clk        : in std_logic;
	cen        : in std_logic;
	rst        : in std_logic;  --active low
	bit_in     : in std_logic;
	sample_out : out std_logic_vector(15 downto 0)  --signed
);

end hc55564;

architecture hdl of hc55564 is
  constant h   	: integer := 224; --integrator decay, (1 - 1/8) * 256
  constant b   	: integer := 255; --syllabic decay, (1 - 1/256) * 256

  constant s_min  : signed(15 downto 0) := to_signed(40, 16);
  constant s_max  : signed(15 downto 0) := to_signed(5120, 16);
  constant x_max  : integer := 32767;
  constant x_min  : integer := -32768;

  signal runofn_new : std_logic_vector(2 downto 0);
  signal runofn 	: std_logic_vector(2 downto 0);
  signal res1 		: signed(31 downto 0);
  signal res2 		: signed(31 downto 0);
  signal x_decayed	: signed(16 downto 0);
  signal s_decayed	: signed(15 downto 0);
  signal x_new		: signed(16 downto 0);
  signal x   		: signed(15 downto 0);  --integrator
  signal s   		: signed(15 downto 0);  --syllabic
  signal old_cen  : std_logic;
begin

res1 <= x * to_signed(h, 16);
res2 <= s * to_signed(b, 16);

-- shift_right on signed is an arithmetic shift, so the decay works for both signs
x_decayed <= resize(shift_right(res1, 8), 17);
s_decayed <= resize(shift_right(res2, 8), 16);

runofn_new <= runofn(1 downto 0) & bit_in;
x_new <= x_decayed + resize(s, 17) when bit_in = '1' else x_decayed - resize(s, 17);

process(clk)
begin
	if rising_edge(clk) then
		if rst = '0' then
			old_cen <= '0';
			runofn  <= "000";
			s       <= s_min;
			x       <= (others => '0');
		else
			old_cen <= cen;
			if old_cen = '0' and cen = '1' then
				runofn <= runofn_new;
				if runofn_new = "000" or runofn_new = "111" then
					s <= s + 40;
					if (s + 40) > s_max then
						s <= s_max;
					end if;
				else
					s <= s_decayed;
					if s_decayed < s_min then
						s <= s_min;
					end if;
				end if;

				-- saturate instead of wrapping; the old code forced x to all-bit_in here
				if x_new > x_max then
					x <= to_signed(x_max, 16);
				elsif x_new < x_min then
					x <= to_signed(x_min, 16);
				else
					x <= resize(x_new, 16);
				end if;
			end if;
		end if;
	end if;
end process;

sample_out <= std_logic_vector(x);

end architecture hdl;
