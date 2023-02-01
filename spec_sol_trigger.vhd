-- special solenoid trigger
-- bontango 12.2022
-- part of WillFA7
--
-- v 0.1
-- 895KHz input clock ( 1,1uS cycle )
-- fix puls time 60ms ( 53 700)
-- fix recycle time 200ms (179 000)

LIBRARY ieee;
USE ieee.std_logic_1164.all;

    entity spec_sol_trigger is        
        port(
            clk_in  : in std_logic;               						
			i_Rst_L : in std_logic;     -- Game on
			trigger : in std_logic;
			solenoid : out std_logic
            );
    end spec_sol_trigger;
    ---------------------------------------------------
    architecture Behavioral of spec_sol_trigger is
	 	type STATE_T is ( Idle, Pulse, Recycle ); 
		signal state : STATE_T := Idle;     
		signal counter : integer range 0 to 200000;
	begin
	
	
	 spec_sol_trigger: process (clk_in, i_Rst_L, trigger)
    begin
		if rising_edge(clk_in) then			
			if i_Rst_L = '0' then --Reset condidition (reset_l)    
			  state <= Idle;
			  solenoid <= '0';
			  counter <= 0;
			else
				case state is
					when Idle =>
					   if ( trigger = '1') then
							state <= Pulse;
							counter <= 0;
							solenoid <= '1';
						end if;
					when Pulse =>
					   if ( counter < 53700) then					
							counter <= counter +1;
						else
							counter <= 0;
							solenoid <= '0';
							state <= Recycle;
						end if;
					when  Recycle =>
					   if ( counter < 179000) then					
							counter <= counter +1;
						else
							counter <= 0;							
							state <= Idle;
						end if;
				end case;
			end if; --reset				
		end if;	--rising edge		
		end process;
    end Behavioral;