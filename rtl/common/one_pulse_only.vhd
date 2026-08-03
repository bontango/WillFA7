-- one_pulse_only ( high pulse version)
-- gives a short high impuls on sig_out when sig_in goes to high
-- ( clk_in is cpu_clk ~894 KHz; 41 cycles gives ~45.9us pulse, sufficient for ISR entry)

LIBRARY ieee;
USE ieee.std_logic_1164.all;

    entity one_pulse_only is        
        port(
            sig_in  : in std_logic;                
            sig_out : out std_logic;
				clk_in  : in std_logic;               
				rst		: in std_logic               
				
            );
    end one_pulse_only;
    ---------------------------------------------------
    architecture Behavioral of one_pulse_only is
		type STATE_T is ( Idle, Pulse, Do_Wait);
		signal state_A : STATE_T;
		-- WISOF 0.9, finding F11: the two limits used to be bare numbers, which read as if
		-- they were dimensioned for the 50MHz clock. At cpu_clk = 894kHz they mean this:
		constant c_pulse_len : integer := 40;     -- 45us, the NMI needs at least 2 CPU cycles
		constant c_lockout   : integer := 100000; -- 112ms debounce of the push button
		signal count : integer range 0 to c_lockout := 0;
	begin
	
	 one_pulse_only: process (clk_in, rst)
    begin
			if rst = '0' then --Reset condidition (reset_l)    
				sig_out <= '0';
				count <= 0;
				state_A <= Idle;    
			elsif rising_edge(clk_in) then
				case state_A is
				when Idle =>
					if sig_in = '1' then 						
						sig_out <= '1';
						state_A <= Pulse;
					end if;	
				
				when Pulse =>						
						if count < c_pulse_len then
							count <= count +1;
						else
							count <= 0;
							sig_out <= '0';
							state_A <= Do_Wait;
						end if;	
				
				when Do_Wait =>
						if count < c_lockout then
							count <= count +1;
						else
							count <= 0;
							state_A <= Idle;
						end if;	
					
				end case;	
			end if; --rising edge		
		end process;
    end Behavioral;