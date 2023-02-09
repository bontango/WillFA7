--
-- EEprom.vhd 
-- read/write eeprom content to and from ram
-- for BallyFA
-- bontango 09.2020
--
-- eeprom content is red into ram at start of routine ( reset going low)
-- we use a dual port ram in main, with 4bit and 8bit outputs
--
-- code is specific for SPI EEPROM M95640-R
-- fix SPI mode : C remains at 0 for (CPOL=0, CPHA=0)
-- to save memory we do 16 rounds a 8 Byte, even the eeprom has a 32byte page size
--
-- v 0.1
-- v 0.2 selection 6bit version for GottFA
-- v 0.3 added second delay for trigger 
-- v 0.4 selection 8bit version for GottFA v3.x
-- v 0.5 with init set we do an initial write at beginning
-- v 0.6 initial wait time reduced from 10seconds to 2 seconds
-- v 0.7 set output when first reading is done
-- v 0.8 with init set no read/write done, meaning cmos will have initial values ( $0F )
-- v 0.9 added another 2 second delay before write eeprom after trigger
-- v 091 256byte at eeprom, stores full cmos
-- v 092 added 'offset_correction' ( workaround only, why does this happen?)

library IEEE;
use IEEE.std_logic_1164.all;
--use IEEE.std_logic_arith.all;
--use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all;

	entity EEprom is
		port(		
		i_Clk	: in std_logic;
		done : out std_logic; --set to '1' when first read/write is done
		-- sd card
		address_eeprom	: buffer  std_logic_vector(7 downto 0); -- 256 words a 8 bit (dual port ram) with cmos
		data_eeprom	: out std_logic_vector(7 downto 0); --
		q_ram	: in std_logic_vector(7 downto 0);
		wr_ram :  out std_logic;				
		-- Control/Data Signals,
		i_Rst_L : in std_logic;     -- FPGA Reset		
		-- PMOD SPI Interface
		o_SPI_Clk  : out std_logic;
		i_SPI_MISO : in std_logic;
		o_SPI_MOSI : out std_logic;
		o_SPI_CS_n : out std_logic;
		-- selection
		selection : in std_logic_vector(7 downto 0);		
		--trigger for writing ram into eeprom
		w_trigger : STD_LOGIC_VECTOR (3 DOWNTO 0);		
		-- 0 if Dip is set -> no EEprom read or write at start
		i_init_Flag : in std_logic
		);
    end EEprom;
	 
   architecture Behavioral of EEprom is
		type STATE_T is ( Check_dip, send_read_request, wait_for_read, wait_for_Master,
								Delay, Delay2, Delay3, Idle, Write_enable, wait_for_Cmd_done, wait_for_Master_I, 
								send_write_request, wait_for_Write_done,  wait_for_Master_II, 
								get_status_reg, wait_for_get_status_reg, wait_for_Master_III, 
								check_WP_bit, next_write, Hold,
								st_offset_correction_init_1, st_offset_correction_init_2, st_offset_correction_init_3, st_offset_correction_init_4,
								st_offset_correction_init_5, st_offset_correction_init_6, st_offset_correction_init_7,
								st_store_correction_1, st_store_correction_2, st_store_correction_3, st_store_correction_4,
								st_store_correction_5, st_store_correction_6, st_store_correction_7);								
				
		signal state : STATE_T;       
		
								
		-- SPI stuff				
		signal TX_Data_W : std_LOGIC_VECTOR ( 31 downto 0); -- 4 Bytes ( 3 cmd plus 1 Data) 32bits
		signal RX_Data_W : std_LOGIC_VECTOR ( 31 downto 0);
		signal TX_Start_W : std_LOGIC;
		signal TX_Done_W : std_LOGIC;
		signal MOSI_W : std_LOGIC;
		signal SS_W :  std_LOGIC;
		signal SPI_Clk_W :  std_LOGIC;

		signal TX_Data_R : std_LOGIC_VECTOR ( 31 downto 0); -- 4 Bytes ( 3 cmd plus 1 Data) 32bits
		signal RX_Data_R : std_LOGIC_VECTOR ( 31 downto 0);
		signal TX_Start_R : std_LOGIC;
		signal TX_Done_R : std_LOGIC;
		signal MOSI_R : std_LOGIC;
		signal SS_R :  std_LOGIC;
		signal SPI_Clk_R :  std_LOGIC;
		
		signal TX_Data_Stat : std_LOGIC_VECTOR ( 15 downto 0); -- 2 Bytes ( 1 cmd plus 1 status)
		signal RX_Data_Stat : std_LOGIC_VECTOR ( 15 downto 0);
		signal TX_Start_Stat : std_LOGIC;
		signal TX_Done_Stat : std_LOGIC;
		signal MOSI_Stat : std_LOGIC;
		signal SS_Stat :  std_LOGIC;
		signal SPI_Clk_Stat :  std_LOGIC;

		signal TX_Data_Cmd : std_LOGIC_VECTOR ( 7 downto 0); -- 1 Byte data
		signal RX_Data_Cmd : std_LOGIC_VECTOR ( 7 downto 0);
		signal TX_Start_Cmd : std_LOGIC;
		signal TX_Done_Cmd : std_LOGIC;
		signal MOSI_Cmd : std_LOGIC;
		signal SS_Cmd :  std_LOGIC;
		signal SPI_Clk_Cmd :  std_LOGIC;
					
		signal WIP_bit :  std_LOGIC; -- write in progress
		-- we react to edges of triggers, so we need to remember
		signal old_w_trigger : std_LOGIC_VECTOR ( 3 downto 0);
		
		--offset correction helper
		signal org_cmos_addr : std_LOGIC_VECTOR ( 7 downto 0);
		signal willfa_cmos_addr : std_LOGIC_VECTOR ( 7 downto 0);
		signal cmos_data : std_LOGIC_VECTOR ( 7 downto 0);
		
		signal c_count : integer range 0 to 500000000;
		
	begin		
	
		
	-- signals for the four SPI Master
	o_SPI_MOSI <=	
	MOSI_R when TX_Start_R = '1' else
	MOSI_W when TX_Start_W = '1' else
	MOSI_Stat when TX_Start_Stat = '1' else
	MOSI_Cmd when TX_Start_Cmd = '1' else
	'0';

	o_SPI_Clk <=
	SPI_Clk_R when TX_Start_R = '1' else
	SPI_Clk_W when TX_Start_W = '1' else
	SPI_Clk_Stat when TX_Start_Stat = '1' else
	SPI_Clk_Cmd when TX_Start_Cmd = '1' else
	'0';

	o_SPI_CS_n <=
	SS_R when TX_Start_R = '1' else
	SS_W when TX_Start_W = '1' else
	SS_Stat when TX_Start_Stat = '1' else
	SS_Cmd when TX_Start_Cmd = '1' else
	'1';


EEPROM_WRITE: entity work.SPI_Master
    generic map (      
      Laenge => 32)
    port map (
			  TX_Data  => TX_Data_W,
           RX_Data  => RX_Data_W,
           MOSI     => MOSI_W,
           MISO     => i_SPI_MISO,
           SCLK     => SPI_Clk_W,
           SS       => SS_W,
           TX_Start => TX_Start_W,
           TX_Done  => TX_Done_W,
           clk      => i_Clk,
			  do_not_disable_SS => '0',
			  do_not_enable_SS => '0'
      );
		
EEPROM_READ: entity work.SPI_Master
    generic map (      
      Laenge => 32)
    port map (
			  TX_Data  => TX_Data_R,
           RX_Data  => RX_Data_R,
           MOSI     => MOSI_R,
           MISO     => i_SPI_MISO,
           SCLK     => SPI_Clk_R,
           SS       => SS_R,
           TX_Start => TX_Start_R,
           TX_Done  => TX_Done_R,
           clk      => i_Clk,
			  do_not_disable_SS => '0',
			  do_not_enable_SS => '0'
      );

EEPROM_STAT: entity work.SPI_Master
    generic map (      
      Laenge => 16)
    port map (
			  TX_Data  => TX_Data_Stat,
           RX_Data  => RX_Data_Stat,
           MOSI     => MOSI_Stat,
           MISO     => i_SPI_MISO,
           SCLK     => SPI_Clk_Stat,
           SS       => SS_Stat,
           TX_Start => TX_Start_Stat,
           TX_Done  => TX_Done_Stat,
           clk      => i_Clk,
			  do_not_disable_SS => '0',
			  do_not_enable_SS => '0'
      );

EEPROM_CMD: entity work.SPI_Master
    generic map (      
      Laenge => 8)
    port map (
			  TX_Data  => TX_Data_Cmd,
           RX_Data  => RX_Data_Cmd,
           MOSI     => MOSI_Cmd,
           MISO     => i_SPI_MISO,
           SCLK     => SPI_Clk_Cmd,
           SS       => SS_Cmd,
           TX_Start => TX_Start_Cmd,
           TX_Done  => TX_Done_Cmd,
           clk      => i_Clk,
			  do_not_disable_SS => '0',
			  do_not_enable_SS => '0'
      );
		
EEPROM: process (i_Clk, w_trigger, i_Rst_L)
			begin
			if i_Rst_L = '0' then --Reset condidition (reset_l)    
				TX_Start_R <= '0';				
				TX_Start_W <= '0';				
				TX_Start_Cmd <= '0';				
				TX_Start_Stat <= '0';				
				address_eeprom <= "00000000";
				wr_ram <= '0';				
				c_count <= 0;
				done <= '0';
				state <= Check_dip;    				
			elsif rising_edge(i_Clk) then
				case state is
				-- STATE MASCHINE ----------------
				when Check_dip => -- check dip switch if we need to read eeprom				
				   if i_init_Flag = '1' then
						state <= send_read_request; -- DIP not set, read eeprom and write to cmos
					else					
						state <= Delay; -- DIP set, after delay go to Idle ( $0F in preloaded ram, Williams will write defaults )
					end if;
																		
				when send_read_request =>					
					TX_Data_R(31 downto 24) <= "00000011"; -- cmd read from memory array
					-- construct the address, we have 32KByte available -> 15 bit address
					-- high byte is selection
					TX_Data_R(23 downto 16)  <= std_logic_vector (unsigned(selection));											 
					-- last 8 bits is address
				   TX_Data_R(15 downto 8) <= address_eeprom;
					TX_Start_R <= '1'; -- set flag for sending byte		
					state <= wait_for_read;					
										
				when wait_for_read =>											
						if (TX_Done_R = '1') then -- Master sets TX_Done when TX is done ;-)
							TX_Start_R <= '0'; -- reset flag 		
							--put red data into ram or init to '0'
							data_eeprom <= RX_Data_R(7 downto 0);							
							wr_ram <= '1';
							state <= Hold;							
						end if;

				 when Hold => -- wait a bit with wr_ram=1
					if c_count < 1000 then
						c_count <= c_count +1;
					else							
						c_count <= 0;												
						state <= wait_for_Master;
					end if;
						
				when wait_for_Master =>							
						if (TX_Done_R = '0') then -- Master sets back TX_Done when ready again
						   -- increment address
						   address_eeprom <= std_logic_vector( unsigned(address_eeprom) + 1 );							
							-- set back write flag for ram
							wr_ram <= '0';
							if address_eeprom = "11111111" then 
							  state <= Delay; -- read done, goto (possible) write
							else
							  state <= send_read_request; -- next round 
							end if;
						end if;							

				 when Delay => -- wait 2 seconds before react to first trigger				   
					if c_count < 100000000 then
						c_count <= c_count +1;
					else	
						done <= '1'; --signal that we are ready 
						c_count <= 0;						
						old_w_trigger <= w_trigger;
						state <= Idle;
					end if;
					
				 when Idle => 							 
					if w_trigger /= old_w_trigger then					
							old_w_trigger <= w_trigger;
							address_eeprom <= "00000000";									
							state <= Delay2;				
					end if;	

				when Delay2 => -- wait 10us then check status of trigger again (glitch?)
					if c_count < 500 then
						c_count <= c_count +1;
					else	
						c_count <= 0;
						if w_trigger = old_w_trigger then -- trigger stable
							if i_init_Flag = '0' then -- DIP set, we do an init with data correction
								state <= st_offset_correction_init_1;
							else
								state <= st_store_correction_1; -- correct settings and write cmos to eeprom
							end if;
						else
							old_w_trigger <= w_trigger; -- trigger NOT stable
							state <= Idle;
						end if;
					end if;															

				when Delay3 => -- wait another 2 seconds before write eeprom
					if c_count < 100000000 then
						c_count <= c_count +1;
					else	
						c_count <= 0;												
						state <= Write_enable;
					end if;
					
				when Write_enable => -- enable writing					
					TX_Data_Cmd <= "00000110"; -- write enable					
					TX_Start_Cmd <= '1'; -- set flag for sending byte											
					state <= wait_for_Cmd_done;					
					
				when wait_for_Cmd_done =>													
					if (TX_Done_Cmd = '1') then				
						TX_Start_Cmd <= '0'; -- reset flag 
						state <= wait_for_Master_I;														
					end if;											 
					
				when wait_for_Master_I =>													
					if (TX_Done_Cmd = '0') then										
						state <= send_write_request;														
					end if;											 
										
				when send_write_request =>
				   --header is write command plus address to write
					TX_Data_W(31 downto 24) <= "00000010"; -- cmd write memory array address 
					-- construct the address, we have 32KByte available -> 15 bit address
					-- high byte is selection
					TX_Data_W(23 downto 16)  <= std_logic_vector (unsigned(selection));											 					
					-- last 8 bits is address
				   TX_Data_W(15 downto 8) <= address_eeprom;
					-- data from ram or init wih zero					
					TX_Data_W ( 7 downto 0 ) <= q_ram;					
					TX_Start_W <= '1'; -- set flag for sending byte				
					state <= wait_for_Write_done;					
		
				when wait_for_Write_done =>							
						if (TX_Done_W = '1') then							
							TX_Start_W <= '0'; -- reset flag 														
							state <= wait_for_Master_II;														
						end if;							
						
				when wait_for_Master_II =>													
					if (TX_Done_W = '0') then										
						state <= get_status_reg;														
					end if;											 
						
				when get_status_reg =>		
						-- write should now be in now in progress, check when done ( appr. 5ms according to datasheet)				
						TX_Data_Stat <= "0000010100000000"; -- read status reg (second 8 bit to ignore)
						TX_Start_Stat <= '1'; -- set flag for sending byte						
						state <= wait_for_get_status_reg;					
					
				when wait_for_get_status_reg =>
						if (TX_Done_Stat = '1') then
							TX_Start_Stat <= '0'; -- reset flag 
							state <= wait_for_Master_III;								
						end if;
						
				when wait_for_Master_III =>													
					if (TX_Done_Stat = '0') then			
							-- bit0 of status reg is WIP (write in progress) 
							WIP_bit <= RX_Data_Stat(0);
							state <= check_WP_bit;					
				   end if;
		
				when check_WP_bit =>													
							if WIP_bit = '0' then 
							   -- 0 means write is complete. lets see if we need another round
								state <= next_write;	
							else
								-- not finished yet, get status register again
								state <= get_status_reg;	
							end if;						
				
				when next_write =>			
							-- increment address
						   address_eeprom <= std_logic_vector( unsigned(address_eeprom) + 1 );							
							if address_eeprom = "11111111" then 
							   state <= Idle; -- all done, goto Idle again
							  else
								state <= Write_enable; -- next round 
							 end if;	

				-- offset is always $44 (68)
				-- first entry is 13-BACKUP_HS_TO_DATE at $81 (129)
				-- which will be stored at $C5 (197)
				-- so we assume that is the start of the 'wrong' table
				-- at init we copy the original table from $81..$BB to $C5..$FF
				when st_offset_correction_init_1 => --init counters
								org_cmos_addr <= x"81";
								willfa_cmos_addr <= x"C5";
								state <= st_offset_correction_init_2;
				
				when st_offset_correction_init_2 =>	--read prep
								address_eeprom <= org_cmos_addr;
								state <= st_offset_correction_init_3;

				when st_offset_correction_init_3 =>	--wait before read
					if c_count < 100 then
						c_count <= c_count +1;
					else							
						c_count <= 0;												
						state <= st_offset_correction_init_4;
					end if;
					
				when st_offset_correction_init_4 =>	--read and inc addr
								org_cmos_addr <= std_logic_vector( unsigned(org_cmos_addr) +1);
								data_eeprom <= q_ram;
								state <= st_offset_correction_init_5;														
								
				when st_offset_correction_init_5 =>	--write 
								address_eeprom <= willfa_cmos_addr;
								wr_ram <= '1';
								state <= st_offset_correction_init_6;

				when st_offset_correction_init_6 =>	--wait a bit while write
					if c_count < 100 then
						c_count <= c_count +1;
					else							
						c_count <= 0;												
						state <= st_offset_correction_init_7;
					end if;
				
				when st_offset_correction_init_7 =>	--prep next write and give time for write
								wr_ram <= '0';
								if willfa_cmos_addr = "11111111" then -- $FF all done, write mod data to eeprom
									address_eeprom <= "00000000";
									state <= Write_enable;		
								else
									willfa_cmos_addr <= std_logic_vector( unsigned(willfa_cmos_addr) +1);
									state <= st_offset_correction_init_2;		-- next round						
								end if;

				-- as the settings menu stores at $C5..$FF ( org stores at $81..$BB) 
				-- before each write the settings need to stored at org locations
				-- what a nasty hack
				when st_store_correction_1 => --init counters
								org_cmos_addr <= x"81";
								willfa_cmos_addr <= x"C5";
								state <= st_store_correction_2;
				
				when st_store_correction_2 =>	--read prep
								address_eeprom <= willfa_cmos_addr;
								state <= st_store_correction_3;

				when st_store_correction_3 =>	--wait before read
					if c_count < 100 then
						c_count <= c_count +1;
					else							
						c_count <= 0;												
						state <= st_store_correction_4;
					end if;
					
				when st_store_correction_4 =>	--read and inc addr
								willfa_cmos_addr <= std_logic_vector( unsigned(willfa_cmos_addr) +1);
								data_eeprom <= q_ram;
								state <= st_store_correction_5;														
								
				when st_store_correction_5 =>	--write 
								address_eeprom <= org_cmos_addr;
								wr_ram <= '1';
								state <= st_store_correction_6;

				when st_store_correction_6 =>	--wait a bit while write
					if c_count < 100 then
						c_count <= c_count +1;
					else							
						c_count <= 0;												
						state <= st_store_correction_7;
					end if;
				
				when st_store_correction_7 =>	--prep next write and give time for write
								wr_ram <= '0';
								if org_cmos_addr = x"BB" then -- $BB all done, read mod data to eeprom
									address_eeprom <= "00000000";
									state <= Delay3;		-- this is like a trigger
								else
									org_cmos_addr <= std_logic_vector( unsigned(org_cmos_addr) +1);
									state <= st_store_correction_2;		-- next round						
								end if;
				
								
				end case;	
			end if; --rising edge				
		end process;
						
    end Behavioral;				