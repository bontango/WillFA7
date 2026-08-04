-- soundtest for WillFA7S (option 'sound')
-- bontango 12.2025
--
-- v 1.0 -- initial version
-- v 1.1 07.2026 moved from variants/s_cyclone_iv_v4/local/ into the shared tree.
--       No functional change.
-- v 1.2 08.2026 'seven_digit' passed through to the boot_message instance below, so
--       the sound number lands on the player display on a seven digit machine too.
--
-- Steps through the sound numbers with Diag_SW and plays the current one with
-- Enter_SW while SB_Test is pulled. Takes over the display for as long as it runs;
-- the top level blocks the diagnostic NMI meanwhile.

LIBRARY ieee;
USE ieee.std_logic_1164.all;
use IEEE.numeric_std.all;

   entity soundtest is        
        port(
            clk_in  : in std_logic;               						
				i_Rst_L : in std_logic;   
				-- input
				activate  : in std_logic;
				step  : in std_logic; -- sound plus one
				play  : in std_logic; -- play current sound
				-- display type of the selected game, just passed on to boot_message
				seven_digit : in std_logic;
				--output 
				is_active	: buffer std_logic;    
				
				--output
				soundtoplay: out 	std_logic_vector(4 downto 0);
				-- (display control)
				strobe: out 	std_logic_vector(3 downto 0);
				bcd: out 	std_logic_vector(7 downto 0)				

            );
    end soundtest;
    ---------------------------------------------------
    architecture Behavioral of soundtest is
	 	type STATE_T is ( Start, Idle, delay_step, delay_play, check_step, check_play ); 
		signal state : STATE_T := Start;    

		signal soundnu  : std_logic_vector(4 downto 0);
		signal dig0 : std_logic_vector(3 downto 0);
		signal dig1 : std_logic_vector(3 downto 0);
		signal counter  : integer range 0 to 100000000;   -- delay, for 10ms use 500.000
	begin
	
	
	 soundtest: process (clk_in, i_Rst_L, activate, step, play )
    begin
		if rising_edge(clk_in) then			
			if i_Rst_L = '0' then --Reset condidition (reset_l)    
			  state <= Idle;
			  counter <= 0;
			  soundnu <= "00001";
			  soundtoplay <= "11111";
			  is_active <= '0';
			else
				case state is
					when Idle =>							
						if ( activate = '1' ) then
							state <= Start;
							is_active <= '1'; 							
						end if;	
					when Start =>			
						-- step ?
						if ( step = '0' ) then
							soundnu <= std_LOGIC_VECTOR(unsigned(soundnu) +1);
							if ( soundnu = "11111" ) then -- overflow?
								soundnu <= "00001";
							end if;	
							state <= delay_step;
						elsif ( play = '0' ) then
							soundtoplay <= not soundnu;
							state <= delay_play;
						end if;												
					when delay_step =>																			
						counter <= counter +1;					
						if ( counter = 25000000 ) then --500ms 
							state <= check_step;
							counter <= 0;			
						end if;																													
					when check_step =>							
						if ( step = '1' ) then
							state <= Start;
						end if;						
					when delay_play =>																			
						counter <= counter +1;					
						if ( counter = 25000000 ) then --500ms 
							state <= check_play;
							counter <= 0;			
							soundtoplay <= "11111";
						end if;																													
					when check_play =>							
						if ( play = '1' ) then
							state <= Start;
						end if;						
				end case;
			end if; --reset				
		end if;	--rising edge		
		end process;
		
SB_TEST_MESSAGE: entity work.boot_message
port map(
	clk		=> clk_in, 	
	-- Control/Data Signals,
   show  => is_active,
	--show error
	is_error => '1', --active low
	seven_digit => seven_digit,
	-- output
	strobe	=> strobe,
	bcd	=> bcd,
	-- input (display data)
	display1	=> ( dig1,x"F",x"F",x"F",x"F",x"F"),
	display2	=> ( dig0,x"F",x"F",x"F",x"F",x"F"),	
	display3	=> ( x"F",x"F",x"F",x"F",x"F",x"F"),
	display4	=> ( x"F",x"F",x"F",x"F",x"F",x"F"),
	error_disp4 => ( x"F",x"F",x"F",x"F",x"F",x"F"),
	status_d	=> ( x"F",x"F", x"F", x"F" )
	);

-- for sound select to visiualize
CONVS: entity work.byte_to_decimal
port map(
	clk_in	=> clk_in, 	
	mybyte	=> "111" & not soundnu,
	dig0 => dig0,
	dig1 => dig1,
	dig2 => open
	);
	
    end Behavioral;