-- read the dips on WillFA
-- bontango 12.2025
--
-- v 1.0 -- 895KHz input clock
-- v 1.1 900Hz input clock, continous reading
-- v 1.2 adapted to WillFA7S

LIBRARY ieee;
USE ieee.std_logic_1164.all;

   entity read_the_dips is        
        port(
            clk_in  : in std_logic;               						
				i_Rst_L : in std_logic;     -- FPGA Reset					   
				--output 
				done		: out std_logic;        -- set to 1 when first read finished
				game_select	:	out std_logic_vector(5 downto 0);
				game_option	:	out std_logic_vector(1 to 6);
				sb_option	:	out std_logic_vector(1 to 4);
				-- strobes
			   dipstrobe1		: out std_logic;
				dipstrobe2		: out std_logic;
				dipstrobe3		: out std_logic;
				dipstrobe4		: out std_logic;
				-- input
				return1			: in std_logic;
				return2			: in std_logic;
				return3			: in std_logic;
				return4			: in std_logic				
            );
    end read_the_dips;
    ---------------------------------------------------
    architecture Behavioral of read_the_dips is
	 	type STATE_T is ( Start, Read1, Read2, Read3, Read4, Idle ); 
		signal state : STATE_T := Start;       		
	begin
	
	
	 read_the_dips: process (clk_in, return1, return2, return3, return4)
    begin
		if rising_edge(clk_in) then			
			if i_Rst_L = '0' then --Reset condidition (reset_l)    
			  state <= Start;
			  done <= '0';
			else
				case state is
					when Idle =>	
						done <= '1'; -- set after first round						
					when Start =>
						dipstrobe1 <= '0';
						dipstrobe2 <= '1';						
						dipstrobe3 <= '1';
						dipstrobe4 <= '1';												
						state <= Read1;						
					when Read1 =>
						game_select(0) <= return1;
						game_select(1) <= return2;
						game_select(2) <= return3;
						game_select(3) <= return4;
						dipstrobe1 <= '1';
						dipstrobe2 <= '0';
						dipstrobe3 <= '1';
						dipstrobe4 <= '1';																		
						state <= Read2;
					when  Read2 =>						
						game_select(4) <= return1;
						game_select(5) <= return2;
						game_option(6) <= return3;
						game_option(5) <= return4;						
						dipstrobe1 <= '1';
						dipstrobe2 <= '1';
						dipstrobe3 <= '0';
						dipstrobe4 <= '1';																		
						state <= Read3;
					when  Read3 =>
						game_option(4) <= return1;
						game_option(3) <= return2;
						game_option(2) <= return3;
						game_option(1) <= return4;						
						dipstrobe1 <= '1';
						dipstrobe2 <= '1';
						dipstrobe3 <= '1';
						dipstrobe4 <= '0';																		
						state <= Read4;
					when  Read4 =>
						sb_option(4) <= return1;
						sb_option(3) <= return2;
						sb_option(2) <= return3;
						sb_option(1) <= return4;
						dipstrobe1 <= '0';
						dipstrobe2 <= '1';						
						dipstrobe3 <= '1';
						dipstrobe4 <= '1';			
						state <= Idle;											
				end case;
			end if; --reset				
		end if;	--rising edge		
		end process;
    end Behavioral;