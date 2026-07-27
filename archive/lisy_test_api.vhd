-- LISY 'Test' API protocol via uart 
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
-- Version 0.1 sys80/80A display output only
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lisy_test_api is
    Port ( 
           clk : in  STD_LOGIC; -- 50MHz
           rst : in  STD_LOGIC; --reset_l
           txd : out  STD_LOGIC; --txd pin	
			  rxd : in  STD_LOGIC; --rxd pin				  
			  --output (display control)
			  digit_strobe	: in std_logic_vector(3 downto 0);
			  segments			: in std_logic_vector(1 to 24)
			  
		);	  
end lisy_test_api;

architecture Behavioral of lisy_test_api is

-- constants
constant lisy_test_api_HW : string :="GOTTFA80" & NUL;
constant lisy_test_api_LISY_VER : string :="2.03 " & NUL;
constant lisy_test_api_VER : string :="0.09" & NUL;

--info, parameter none
constant LISY_G_HW            : integer := 0; --get connected LISY hardware -	return "LISY1" or "LISY80"
constant LISY_G_LISY_VER      : integer := 1; --get LISY Version - return String
constant LISY_G_API_VER       : integer := 2; --get API Version - return String

--switches, parameter byte/none
constant LISY_G_STAT_SW       : integer := 40; --get status of switch# - return byte "0=OFF; 1=ON; 2=Error"

-- lisy test codes, start at 0x80 (128)
constant LISY_G_DISP1     : integer := 16#80#; --get display string, Display1
constant LISY_G_DISP2     : integer := 16#81#; --get display string, Display2
constant LISY_G_DISP3     : integer := 16#82#; --get display string, Display3
constant LISY_G_DISP4     : integer := 16#83#; --get display string, Display4
constant LISY_G_DISP5     : integer := 16#84#; --get display string, Display5
constant LISY_G_DISP6     : integer := 16#85#; --get display string, Display6
constant LISY_G_DISPS     : integer := 16#88#; --get display string, Status Display
  
signal uart_data_tx : std_logic_vector (7 downto 0);   
signal uart_data_rx : std_logic_vector (7 downto 0);   
 
type STATE_T is ( get_opcode, get_parameter, Execute_op_code, Execute_parameter,
						wait_finish_rx, Send_byte, Check_byte, check_char, send_char, send_string,
						Finish_byte, Finish_char); 
signal state : STATE_T;        --State
  
  
type STATE2_T is (   assign_Seg, check_strobe, delay );
signal state2 : STATE2_T := assign_Seg;

  
signal string_to_send : string (1 to 12);
signal string_length : integer range 0 to 15;
signal tx_index : integer range 0 to 15 := 0;


signal r_TX_DV : std_logic := '0';
signal r_TX_ACTIVE : std_logic;
signal uart_rx_flag : std_logic;
signal op_code     : integer range 0 to 255; -- current opcode
signal parameter     : integer range 0 to 255; -- current parameter

signal Disp1_string : string (1 to 8) :="       " & NUL;
signal Disp2_string : string (1 to 8) :="       " & NUL;
signal Disp3_string : string (1 to 8) :="       " & NUL;
signal Disp4_string : string (1 to 8) :="       " & NUL;
signal Disp5_string : string (1 to 8) :="       " & NUL;
signal Disp6_string : string (1 to 8) :="       " & NUL;
signal DispS_string : string (1 to 5) :="    " & NUL;

signal Din_Seg_A			: character;
signal Din_Seg_B			: character;
signal Din_Seg_C			: character;

signal old_digit_strobe	: std_logic_vector(3 downto 0) :="0000";
signal counter  : integer range 0 to 18000 := 0;   -- delay, 20nS at 50MHz; for 10ms use 500.000
constant DISP_DELAY     : integer := 17500; -- 350uS as used with GODI80

begin

	sn7448_rev_gtb_1: entity work.sn7448_rev_gtb
	port map(   
		Dout 	=> Din_Seg_A,
		Din  => segments(1 to 8)
	);
	sn7448_rev_gtb_2: entity work.sn7448_rev_gtb
	port map(   
		Dout 	=> Din_Seg_B,
		Din  => segments(9 to 16)
	);	
	sn7448_rev_gtb_3: entity work.sn7448_rev_gtb
	port map(   
		Dout 	=> Din_Seg_C,
		Din  => segments(17 to 24)
	);	

UART_TX_INST : entity work.uart_tx 
--  generic map (
--    g_CLKS_PER_BIT => c_CLKS_PER_BIT 434 for 50MHz default
--      )
    port map (
      i_clk       => clk,
      i_tx_dv     => r_TX_DV,
      i_tx_byte   => uart_data_tx,
      o_tx_active => r_TX_ACTIVE,
      o_tx_serial => txd,
      o_tx_done   => open
      );


UART_RX_INST : entity work.uart_rx
    port map (
      i_clk       => clk,
      i_rx_serial => rxd,
      o_rx_dv     => uart_rx_flag,
      o_rx_byte   => uart_data_rx
      );

lisy_test_api : process (clk, rst, uart_rx_flag) is
  
begin
  if rst = '0' then --Reset condidition (reset_l)
	 r_TX_DV <= '0';
    state <= get_opcode;    
  elsif rising_edge(clk)then
    case state is
	   when get_opcode => 
        if uart_rx_flag = '1' then -- rx flag is true, start decoding
			 op_code <= to_integer(unsigned(uart_data_rx)); -- Load the op-code						 
			 -- new state
          state <= Execute_op_code;
        end if;		    

  	   when wait_finish_rx => 
        if uart_rx_flag = '0' then -- wait for reset flag
			state <= get_parameter;
		  end if;
		  		  
  	   when get_parameter => 
        if uart_rx_flag = '1' then -- rx flag is true, start decoding
			 parameter <= to_integer(unsigned(uart_data_rx)); -- Load the parameter for this op_code					 
			 -- new state
          state <= Execute_parameter;
        end if;		    

		  
		when Execute_op_code =>   
			case op_code is
				when LISY_G_HW =>
					string_to_send(1 to lisy_test_api_HW'length) <= lisy_test_api_HW;
					string_length <= lisy_test_api_HW'length;
					tx_index <= 0;
					state <= Send_string;
				when LISY_G_LISY_VER =>
					string_to_send(1 to lisy_test_api_LISY_VER'length) <= lisy_test_api_LISY_VER;
					string_length <= lisy_test_api_LISY_VER'length;
					tx_index <= 0;
					state <= Send_string;
				when LISY_G_API_VER =>
					string_to_send(1 to lisy_test_api_VER'length) <= lisy_test_api_VER;
					string_length <= lisy_test_api_VER'length;
					tx_index <= 0;
					state <= Send_string;														
										
										
				when LISY_G_DISP1 =>
					string_to_send(1 to Disp1_string'length) <= Disp1_string;
					string_length <= Disp1_string'length;
					tx_index <= 0;
					state <= Send_string;														

					when LISY_G_DISPS =>
					string_to_send(1 to Disps_string'length) <= Disps_string;
					string_length <= Disps_string'length;
					tx_index <= 0;
					state <= Send_string;														
				
				
				when others => 	-- send '0'
					uart_data_tx <= "00000000"; --std_logic_vector(to_unsigned(0, uart_data_tx'length));					
					state <= Send_byte;
			end case;

		when Execute_parameter =>   
			case op_code is
				when LISY_G_STAT_SW => --RTH todo: send real state
					uart_data_tx <= "00000000";
					state <= Send_byte;
				
				when others =>
					uart_data_tx <= "00000000";
					state <= Send_byte;
				
			end case;	
						
			
		when Send_byte =>
        r_tx_DV <= '1';
		  state <= Check_byte;	
		  			
      when Check_byte =>   -- wait for active
        r_tx_DV <= '0';
		  if r_TX_ACTIVE = '1' then
			state <= Finish_byte;	
		  end if;
	
      when Finish_byte =>   -- wait in this state until flag to go down
			if r_TX_ACTIVE = '0' then
				state <= get_opcode;
			end if;
			
		when Send_string =>
		   if tx_index < string_length then			 
			 uart_data_tx <=   std_logic_vector(to_unsigned(character'pos(string_to_send(tx_index + 1)), 8));
		    -- next index
			 tx_index <= tx_index + 1;
			 state <= Send_char;
			else
			 state <= get_opcode;
			end if;

		when Send_char =>
        r_tx_DV <= '1';
		  state <= Check_char;	

      when Check_char =>   -- wait for active
        r_tx_DV <= '0';
		  if r_TX_ACTIVE = '1' then
			state <= Finish_char;	 -- next char
		  end if;

      when Finish_char =>   -- wait in this state until flag to go down
			if r_TX_ACTIVE = '0' then
				state <= Send_string;
			end if;
	  
      end case;
  end if;
end process;

get_display : process (clk, digit_strobe, segments, Din_Seg_A, Din_Seg_B, Din_Seg_C) is
  
begin
  if rising_edge(clk)then
	case state2 is 
		when check_strobe =>
			if ( digit_strobe /= old_digit_strobe ) then
				old_digit_strobe <= digit_strobe;
				state2 <= delay;
			end if;

			when delay =>			
					counter <= counter +1;					
					if ( counter > DISP_DELAY ) then 
						state2 <= assign_Seg;
						counter <= 0;						
					end if;																																

			when assign_Seg =>
				state2 <= check_strobe;
				old_digit_strobe <= digit_strobe;			
				case digit_strobe is
					when x"0" =>
						Disp1_string(7) <= Din_Seg_A;
						Disp3_string(7) <= Din_Seg_B;
					when x"1" =>
						Disp1_string(6) <= Din_Seg_A;
						Disp3_string(6) <= Din_Seg_B;
					when x"2" =>
						Disp1_string(5) <= Din_Seg_A;
						Disp3_string(5) <= Din_Seg_B;
					when x"3" =>
						Disp1_string(4) <= Din_Seg_A;
						Disp3_string(4) <= Din_Seg_B;
					when x"4" =>
						Disp1_string(3) <= Din_Seg_A;
						Disp3_string(3) <= Din_Seg_B;
					when x"5" =>
						Disp1_string(2) <= Din_Seg_A;
						Disp3_string(2) <= Din_Seg_B;
					when x"6" =>
						Disp2_string(7) <= Din_Seg_A;
						Disp4_string(7) <= Din_Seg_B;
					when x"7" =>
						Disp2_string(6) <= Din_Seg_A;
						Disp4_string(6) <= Din_Seg_B;
					when x"8" =>
						Disp2_string(5) <= Din_Seg_A;
						Disp4_string(5) <= Din_Seg_B;
					when x"9" =>
						Disp2_string(4) <= Din_Seg_A;
						Disp4_string(4) <= Din_Seg_B;
					when x"A" =>
						Disp2_string(3) <= Din_Seg_A;
						Disp4_string(3) <= Din_Seg_B;
					when x"B" =>
						Disp2_string(2) <= Din_Seg_A;
						Disp4_string(2) <= Din_Seg_B;
					when x"C" =>
						Disp2_string(1) <= Din_Seg_A;
						Disp4_string(1) <= Din_Seg_B;
						DispS_string(4) <= Din_Seg_C;
					when x"D" =>
						DispS_string(3) <= Din_Seg_C;
					when x"E" =>
						DispS_string(2) <= Din_Seg_C;
					when x"F" =>
						Disp1_string(1) <= Din_Seg_A;
						Disp3_string(1) <= Din_Seg_B;
						DispS_string(1) <= Din_Seg_C;						
					when OTHers =>	
				end case; --digit
		end case; --state
 end if;
end process;



end architecture;

