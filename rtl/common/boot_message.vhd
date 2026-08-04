-- boot message on Williams Display
-- part of  WillFA7
-- bontango 12.2022
--
-- v 1.0
-- v1.1 with error message at display4
-- v1.2 time adapted
-- v1.3 works on six AND seven digit player displays, see 'seven_digit' and
--      docs/display_layout.md

LIBRARY ieee;
USE ieee.std_logic_1164.all;

package instruction_buffer_type is
	type DISPLAY_T is array (0 to 5) of std_logic_vector(3 downto 0);
	type DISPLAY_TS is array (0 to 3) of std_logic_vector(3 downto 0);
end package instruction_buffer_type;

LIBRARY ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;

use work.instruction_buffer_type.all;

    entity boot_message is        
        port(
            clk  : in std_logic;
				show   : in  std_logic;
				is_error  : in  std_logic;		--active low
				-- '1' = seven digit player displays. Moves the whole message, see
				-- strobe_of below and docs/display_layout.md
				seven_digit : in  std_logic;
				-- input (display data)
			   display1			: in  DISPLAY_T;
				display2			: in  DISPLAY_T;
				display3			: in  DISPLAY_T;
				display4			: in  DISPLAY_T;
				error_disp4		: in  DISPLAY_T;
				status_d			: in  DISPLAY_TS;				
				--output (display control)
				strobe: out 	std_logic_vector(3 downto 0);
				bcd: out 	std_logic_vector(7 downto 0)				
            );
    end boot_message;
    ---------------------------------------------------
    architecture Behavioral of boot_message is
		  signal count : integer range 0 to 50001 := 0;
		  signal digit : integer range 0 to 15 := 0;
		  signal phase : integer range 0 to 23 := 0;

		-- Which digit strobe a message slot goes out on.
		--
		-- Six digit displays: the slot number itself. Slot 0..5 is player 1 (high
		-- nibble) and player 3 (low nibble), 8..13 player 2 and 4, and the four status
		-- digits sit on 6,7 (right pair) and 14,15 (left pair), all on the high nibble.
		--
		-- Seven digit displays: the player displays occupy strobe 1..7 and 9..15, and
		-- the status digits move to strobe 0 and 8 - two of them on the high nibble
		-- (right pair), two on the low one (left pair). So the six message characters
		-- move two strobes up, which puts them right aligned with the leftmost digit
		-- dark, and the two slots that have nothing left to show (14, 15) are blanked
		-- by the case below.
		--
		-- Derived from PinMAME (s6.c s6_6digit_disp / s6_7digit_disp, s7games.c
		-- s7_dispS7) and from lisy_w.c 't_mysegments'. Full table:
		-- docs/display_layout.md.
		function strobe_of (d : integer range 0 to 15; s7 : std_logic)
		         return std_logic_vector is
		begin
			if ( s7 = '0' ) then
				return std_logic_vector( to_unsigned( d, 4));
			elsif ( d = 6 or d = 14 ) then
				return "0000";                                     -- status, tens
			elsif ( d = 7 or d = 15 ) then
				return "1000";                                     -- status, ones
			else
				return std_logic_vector( to_unsigned( d + 2, 4));  -- six characters
			end if;
		end function;

	 begin
	
  boot_message: process (clk, show, is_error, seven_digit)
    begin
			if ( show = '0') then  -- Asynchronous reset
				--   output and variable initialisation
				strobe <= "0000";
				bcd <= "11111111";
				count <= 0;
				digit <= 0;
				phase <= 0;

			elsif rising_edge(clk) then
				-- inc count for next round
				-- 50MHz input we have a clk each 20ns
				-- phases are 56uS which is a count of 2800
				-- first phase bcd 0xff (anti flicker)
				-- then 19 phases with digit 
				-- results in 1,1mS per digit strobe
				count <= count +1;
				if ( count = 2800) then 					     
					phase <= phase +1;
					count <= 0;
				end if;	
				if ( phase > 19 ) then
					phase <= 0;
					-- overflow?
					if ( digit = 15) then
						digit <= 0;
						strobe <= strobe_of( 0, seven_digit);
					else
						digit <= digit +1;
						strobe <= strobe_of( digit +1, seven_digit);
					end if;
				end if;
				
				case digit is 		
				when 0 to 5 => 		
					if ( phase = 0) then
							bcd(7 downto 4) <= "1111";
					else
							bcd(7 downto 4) <= display1( digit); -- player 1 
					end if;
					if ( phase = 0) then
							bcd(3 downto 0) <= "1111";
					else
							bcd(3 downto 0) <= display3( digit); -- player 3
					end if;
										
				-- The four status digits. On a six digit display all four go out on the
				-- high nibble, this slot pair carrying the right one; the low nibble is
				-- not connected to anything there, so it gets the same value.
				-- On a seven digit display the two slots below are the ONLY status
				-- slots (strobe 0 and 8), and the two pairs share them: high nibble is
				-- the right pair, low nibble the left one. Slots 14 and 15 are blanked.
				when 6 =>
					if ( phase = 0) then
							bcd(7 downto 4) <= "1111";
							bcd(3 downto 0) <= "1111"; -- RTH
					else
							bcd(7 downto 4) <= status_d(3); -- status 0
							if ( seven_digit = '1') then
								bcd(3 downto 0) <= status_d(1); -- left pair, tens
							else
								bcd(3 downto 0) <= status_d(3); -- RTH
							end if;
					end if;

				when 7 =>
					if ( phase = 0) then
							bcd(7 downto 4) <= "1111";
							bcd(3 downto 0) <= "1111"; -- RTH
					else
							bcd(7 downto 4) <= status_d(2); -- status 1
							if ( seven_digit = '1') then
								bcd(3 downto 0) <= status_d(0); -- left pair, ones
							else
								bcd(3 downto 0) <= status_d(2); -- RTH
							end if;
					end if;
			
			
				when 8 to 13 => 	
					if ( phase = 0) then
							bcd(7 downto 4) <= "1111";
					else
							bcd(7 downto 4) <= display2( digit - 8 ); -- player 2 
					end if;		
					
					if ( phase = 0) then
							bcd(3 downto 0) <= "1111";
					else
						if ( is_error = '0' ) then						
							bcd(3 downto 0) <= error_disp4( digit - 8); -- player 4	
						else	
							bcd(3 downto 0) <= display4( digit - 8); -- player 4	
						end if;	
					end if;					
					
				-- Six digit: the left status pair. Seven digit: nothing left to show,
				-- the left pair went out on the low nibble of slot 6 and 7 already.
				-- These two slots still address strobe 0 and 8 (see strobe_of), they
				-- just stay dark - that keeps those digits at the same brightness as
				-- the player digits instead of lighting them twice per round.
				when 14 =>
					if ( phase = 0 or seven_digit = '1') then
							bcd(7 downto 4) <= "1111";
							bcd(3 downto 0) <= "1111"; --RTH
					else
							bcd(7 downto 4) <= status_d(1); -- status 2
							bcd(3 downto 0) <= status_d(1); -- RTH
					end if;

				when 15 =>
					if ( phase = 0 or seven_digit = '1') then
							bcd(7 downto 4) <= "1111";
							bcd(3 downto 0) <= "1111"; --RTH
					else
							bcd(7 downto 4) <= status_d(0); -- status 3
							bcd(3 downto 0) <= status_d(0); -- RTH
					end if;
					
				--when OTHERS =>
				end case;
			end if; --rising edge		
		end process;
    end Behavioral;