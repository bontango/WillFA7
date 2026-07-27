-- WillFA7 Monitor modul
-- produces serial output to visualize in combination with WillFA7_Monitor.html (Web Application)
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
-- Version 0.1 system parameters only
-- Version 0.2 added SYS3 display
-- Version 0.3 always send all displays on update interval (no change detection)
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity willfa7_monitor is
    Port ( 
         clk : in  STD_LOGIC; -- 50MHz
         rst : in  STD_LOGIC; --reset_l
         txd : buffer  STD_LOGIC; --txd pin	
		   rxd : in  STD_LOGIC; --rxd pin			
			-- displays
			disp_strobe: in 	std_logic_vector(3 downto 0);	
			disp_bcd: in 	std_logic_vector(7 downto 0);
			-- debug
			debug: buffer STD_LOGIC
		);	  
end willfa7_monitor;

architecture Behavioral of willfa7_monitor is

-- constants
constant willfa7_monitor_HW : string :="WillFA7" & NUL;
constant willfa7_monitor_LISY_VER : string :="2.16" & NUL;
constant willfa7_monitor_API_VER : string :="0.09" & NUL;

constant LISY_DISPLAY_UPDATE_INT    : integer := 500; -- Display update rate in ms
constant DATA_READ_US_DELAY         : integer := 5;  -- Delay after strobe change before reading disp_bcd (µs)
constant DATA_READ_CLK_DELAY        : integer := DATA_READ_US_DELAY * 50; -- clock cycles at 50 MHz

--info, parameter none
constant LISY_G_HW            : integer := 0; --get connected LISY hardware - return String
constant LISY_G_LISY_VER      : integer := 1; --get LISY Version - return String
constant LISY_G_API_VER       : integer := 2; --get API Version - return String

--display data (autonomous output, no opcode request needed)
constant LISY_CODE_DISPLAY_DATA_SYS3 : integer := 200; -- 0xC8
    
signal uart_data_tx : std_logic_vector (7 downto 0);   
signal uart_data_rx : std_logic_vector (7 downto 0);   
 
type STATE_T is ( get_opcode, get_parameter, Execute_op_code, Execute_parameter,
						wait_finish_rx, Send_byte, Check_byte, check_char, send_char, send_string,
						Finish_byte, Finish_char,
						Disp_check_pending, Disp_load_buffer,
						Disp_send_next_byte, Disp_send_byte_active, Disp_send_byte_wait, Disp_send_byte_done);
signal state : STATE_T;        --State
    
signal string_to_send : string (1 to 12);
signal string_length : integer range 0 to 15;
signal tx_index : integer range 0 to 15 := 0;

signal r_TX_DV : std_logic := '0';
signal r_TX_ACTIVE : std_logic;
signal uart_rx_flag : std_logic;
signal op_code     : integer range 0 to 255; -- current opcode
signal parameter     : integer range 0 to 255; -- current parameter
signal strobe_counter  : integer range 0 to 1000; 

-- Display capture
type display_data_t is array (0 to 31) of std_logic_vector(3 downto 0);
signal display_data      : display_data_t := (others => "1111");
signal display_data_prev : display_data_t := (others => "1111");
signal disp_strobe_prev    : std_logic_vector(3 downto 0) := "0000";
signal disp_strobe_latched : std_logic_vector(3 downto 0) := "0000";
signal data_read_pending   : std_logic := '0';
signal data_read_delay_cnt : integer range 0 to 1023 := 0;
signal scan_complete       : std_logic := '0';

-- Change tracking (5 Displays: Player1-4, Status)
signal disp_changed : std_logic_vector(4 downto 0) := "00000";

-- Display send buffer (8 Bytes: Code + Nr + 6 Daten)
type disp_send_buf_t is array (0 to 7) of std_logic_vector(7 downto 0);
signal disp_send_buf   : disp_send_buf_t;
signal disp_send_index : integer range 0 to 8 := 0;
signal current_disp    : integer range 0 to 4 := 0;

begin

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

willfa7_monitor : process (clk, rst, uart_rx_flag, disp_strobe, display_data) is
  
begin
  if rst = '0' then --Reset condidition (reset_l)
	 r_TX_DV <= '0';
    state <= get_opcode;
    display_data <= (others => "1111");
    display_data_prev <= (others => "1111");
    disp_strobe_prev <= "0000";
    disp_strobe_latched <= "0000";
    data_read_pending <= '0';
    data_read_delay_cnt <= 0;
    scan_complete <= '0';
    disp_changed <= "00000";
    disp_send_index <= 0;
    strobe_counter <= 0;
  elsif rising_edge(clk)then
    -- Display capture logic (runs every clock cycle, independent of state)
    debug <= txd;

    -- Step 1: detect strobe change, latch strobe address, start delay
    if disp_strobe /= disp_strobe_prev and data_read_pending = '0' then
      disp_strobe_prev    <= disp_strobe;
      disp_strobe_latched <= disp_strobe;
      data_read_delay_cnt <= 0;
      data_read_pending   <= '1';
    end if;

    -- Step 2: wait DATA_READ_US_DELAY µs, then sample disp_bcd
    if data_read_pending = '1' then
      if data_read_delay_cnt < DATA_READ_CLK_DELAY then
        data_read_delay_cnt <= data_read_delay_cnt + 1;
      else
        data_read_pending <= '0';
        display_data(to_integer(resize(unsigned(disp_strobe_latched), 5)))      <= disp_bcd(7 downto 4);
        display_data(16 + to_integer(resize(unsigned(disp_strobe_latched), 5))) <= disp_bcd(3 downto 0);
        strobe_counter <= strobe_counter + 1;
        -- update display each LISY_DISPLAY_UPDATE_INT (one strobe each ms)
        if strobe_counter > LISY_DISPLAY_UPDATE_INT then
          scan_complete  <= '1';
          strobe_counter <= 0;
        end if;
      end if;
    end if;

    -- On scan complete: always send all displays
    if scan_complete = '1' then
      scan_complete <= '0';
      display_data_prev <= display_data;
      disp_changed <= "11111";
    end if;

    case state is
	   when get_opcode =>
        if uart_rx_flag = '1' then -- rx flag is true, start decoding
			 op_code <= to_integer(unsigned(uart_data_rx)); -- Load the op-code
			 -- new state
          state <= Execute_op_code;
        elsif disp_changed /= "00000" then
          state <= Disp_check_pending;
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
					string_to_send(1 to willfa7_monitor_HW'length) <= willfa7_monitor_HW;
					string_length <= willfa7_monitor_HW'length;
					tx_index <= 0;
					state <= Send_string;
				when LISY_G_LISY_VER =>
					string_to_send(1 to willfa7_monitor_LISY_VER'length) <= willfa7_monitor_LISY_VER;
					string_length <= willfa7_monitor_LISY_VER'length;
					tx_index <= 0;
					state <= Send_string;
				when LISY_G_API_VER =>
					string_to_send(1 to willfa7_monitor_API_VER'length) <= willfa7_monitor_API_VER;
					string_length <= willfa7_monitor_API_VER'length;
					tx_index <= 0;
					state <= Send_string;														
														
				when others => 	-- send '0'
					uart_data_tx <= "00000000"; --std_logic_vector(to_unsigned(0, uart_data_tx'length));					
					state <= Send_byte;
			end case;

		when Execute_parameter =>   
			case op_code is
--				when LISY_G_STAT_SW => --RTH todo: send real state
--					uart_data_tx <= "00000000";
--					state <= Send_byte;
				
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

		-- Display data autonomous send states
		when Disp_check_pending =>
			if disp_changed(0) = '1' then
				current_disp <= 0;
				disp_changed(0) <= '0';
				state <= Disp_load_buffer;
			elsif disp_changed(1) = '1' then
				current_disp <= 1;
				disp_changed(1) <= '0';
				state <= Disp_load_buffer;
			elsif disp_changed(2) = '1' then
				current_disp <= 2;
				disp_changed(2) <= '0';
				state <= Disp_load_buffer;
			elsif disp_changed(3) = '1' then
				current_disp <= 3;
				disp_changed(3) <= '0';
				state <= Disp_load_buffer;
			elsif disp_changed(4) = '1' then
				current_disp <= 4;
				disp_changed(4) <= '0';
				state <= Disp_load_buffer;
			else
				state <= get_opcode;
			end if;

		when Disp_load_buffer =>
			disp_send_buf(0) <= std_logic_vector(to_unsigned(LISY_CODE_DISPLAY_DATA_SYS3, 8));
			disp_send_buf(1) <= std_logic_vector(to_unsigned(current_disp + 1, 8));
			case current_disp is
				when 0 => -- Player 1: display_data(0..5)
					disp_send_buf(2) <= "0000" & display_data_prev(0);
					disp_send_buf(3) <= "0000" & display_data_prev(1);
					disp_send_buf(4) <= "0000" & display_data_prev(2);
					disp_send_buf(5) <= "0000" & display_data_prev(3);
					disp_send_buf(6) <= "0000" & display_data_prev(4);
					disp_send_buf(7) <= "0000" & display_data_prev(5);
				when 1 => -- Player 2: display_data(8..13)
					disp_send_buf(2) <= "0000" & display_data_prev(8);
					disp_send_buf(3) <= "0000" & display_data_prev(9);
					disp_send_buf(4) <= "0000" & display_data_prev(10);
					disp_send_buf(5) <= "0000" & display_data_prev(11);
					disp_send_buf(6) <= "0000" & display_data_prev(12);
					disp_send_buf(7) <= "0000" & display_data_prev(13);
				when 2 => -- Player 3: display_data(16..21)
					disp_send_buf(2) <= "0000" & display_data_prev(16);
					disp_send_buf(3) <= "0000" & display_data_prev(17);
					disp_send_buf(4) <= "0000" & display_data_prev(18);
					disp_send_buf(5) <= "0000" & display_data_prev(19);
					disp_send_buf(6) <= "0000" & display_data_prev(20);
					disp_send_buf(7) <= "0000" & display_data_prev(21);
				when 3 => -- Player 4: display_data(24..29)
					disp_send_buf(2) <= "0000" & display_data_prev(24);
					disp_send_buf(3) <= "0000" & display_data_prev(25);
					disp_send_buf(4) <= "0000" & display_data_prev(26);
					disp_send_buf(5) <= "0000" & display_data_prev(27);
					disp_send_buf(6) <= "0000" & display_data_prev(28);
					disp_send_buf(7) <= "0000" & display_data_prev(29);
				when 4 => -- Status: display_data(14,15,6,7)
					disp_send_buf(2) <= "0000" & display_data_prev(14);
					disp_send_buf(3) <= "0000" & display_data_prev(15);
					disp_send_buf(4) <= "0000" & display_data_prev(6);
					disp_send_buf(5) <= "0000" & display_data_prev(7);
					disp_send_buf(6) <= "00000000";
					disp_send_buf(7) <= "00000000";
				when others => null;
			end case;
			disp_send_index <= 0;
			state <= Disp_send_next_byte;

		when Disp_send_next_byte =>
			if disp_send_index < 8 then
				uart_data_tx <= disp_send_buf(disp_send_index);
				disp_send_index <= disp_send_index + 1;
				state <= Disp_send_byte_active;
			else
				state <= Disp_check_pending;
			end if;

		when Disp_send_byte_active =>
			r_tx_DV <= '1';
			state <= Disp_send_byte_wait;

		when Disp_send_byte_wait =>
			r_tx_DV <= '0';
			if r_TX_ACTIVE = '1' then
				state <= Disp_send_byte_done;
			end if;

		when Disp_send_byte_done =>
			if r_TX_ACTIVE = '0' then
				state <= Disp_send_next_byte;
			end if;

      end case;
  end if;
end process;


end architecture;

