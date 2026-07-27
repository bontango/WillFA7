-- 'WillFA7' a Williams SYS7 MPU on a low cost FPGA
-- Ralf Thelen 'bontango' 02.2023
-- www.lisy.dev
--
-- v1.00 for HW v1.0 based on v024 for HW v0.5
-- v1.01 with org cpu68 & flip flop v1.01
-- v1.02 SYS3 setting support (together with ro SD v2 )
-- v1.03 cpu68.vhd v081 ( daa did not set Zero-Flag which causd the offset bug), back to eeprom v091
-- v1.04 eeprom 0.93, better saving in menue
-- v1.05 first working sys7 version :-) together with cpu68.vhd v083
-- v1.06 secured handling of special solenoids with flipflops v1.1
-- v1.07 more secured handling of special solenoids with spec_sol_trig v0.3
-- v1.08 added slow to fast clock for special solenoid switches, added debouncer for spec_sol_trigger(v0.4)
-- v1.09 pulsetime for spcial solenoids adjustable spec_sol_trigger(v0.5)
-- TODo
-- V2.09 11.05.2023 adapted to Cyclone IV and late Williams SYS7 games
-- v2.10 23.12.2023 deactivate sp_solenoid_mpu(1), as it pulses during game on, selftest on spec sol1 will not work
-- v2.11 different sdc
-- v2.12 with memory protect and flipflop version 1.3 ( solves soundbug)
--
-- version 3.12 	 -- converted Cyclone IV v4.x board ( EP4CE6E22C8N ) 
-- v3.13 with eeprom v094 which has reduced clock to 100KHz (old 1MHz)
-- v3.14 solenoid 17 with peak filter as we have 9uS peaks each 2mS on sp_solenoid_mpu(1);
--
-- added soundcard -> Willfa7S
-- v5.01 for EP4C1E10E22C8
-- v5.02 added own soundtest
-- v5.03 CRC check added


library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
	
entity WillFA7 is
	port(		
	   -- the FPGA board
		clk_50	: in std_logic; 	-- PIN17
		reset_sw  : in std_logic; 	-- PIN144 --goes Low on reset(push)
		LED_SD_Error 	: out STD_LOGIC;	-- PIN3	LED0				
		LED_active 	: out STD_LOGIC;  -- PIN7 LED1
		LED_status 	: out STD_LOGIC;	-- PIN9 LED2
				
		-- SPI SD card & EEprom
		CS_SDcard	: 	buffer 	std_logic;
		CS_EEprom	: 	buffer 	std_logic;
		MOSI			: 	out 	std_logic;
		MISO			: 	in 	std_logic;
		SPI_CLK			: 	out 	std_logic;
						
		--displays
		disp_strobe: out 	std_logic_vector(3 downto 0);
		disp_bcd: out 	std_logic_vector(7 downto 0);
		
		--switches
		sw_strobe: out 	std_logic_vector(7 downto 0);
		sw_return: in 	std_logic_vector(7 downto 0);

		--lamps & sound/comma display SYS7 plus 'extra LED'
		lamps: out 	std_logic_vector(7 downto 0);
		lamp_strobe_sel: out std_logic; 
		lamp_row_sel: out std_logic;
		sound_com_sel: out std_logic;
		
		--solenoids (shared)
		solenoids: out		std_logic_vector(7 downto 0); 
		sol_1_8_sel: buffer std_logic;
		sol_9_16_sel: out std_logic;
		sol_spec_sel: out std_logic;
		
		-- spec solenoid triggers
		SPC_Sol_Trig: in 	std_logic_vector(6 downto 1);
		
		--diag
		Mem_prot: in std_logic;
		Advance: in std_logic;
		up_down: in std_logic;
		Enter_SW: in std_logic;
		Diag_SW: in std_logic;
				
		--dips Williams
		W_PA_DIP: in std_logic_vector(3 downto 0); 
		
		--dips WillFA7
		Dip_Ret_1: in std_logic;
		Dip_Ret_2: in std_logic;
		Dip_Ret_3: in std_logic;
		Dip_Ret_4: in std_logic;
				
		-- sound & speech
		SB_Sound: out std_logic;
		SB_Speech: out std_logic;
		SB_Test: in std_logic
				
		);
end;

architecture rtl of WillFA7 is 

signal cpu_clk		:  std_logic;  --894KHz for Williams
signal pll_locked	:  std_logic;  
signal clk_14		:  std_logic; -- 14,28MHz from PLL
signal reset_h		: 	std_logic;
signal reset_l	 	: std_logic := '0';
signal boot_phase	: 	std_logic_vector(3 downto 0) := "0000";
signal boot_phase_dig	: 	std_logic_vector(3 downto 0);

signal cpu_addr	: 	std_logic_vector(15 downto 0);
signal cpu_din		: 	std_logic_vector(7 downto 0) := x"FF";
signal cpu_dout	: 	std_logic_vector(7 downto 0);
signal cpu_rw		: 	std_logic;
signal cpu_vma		: 	std_logic;  --valid memory address
signal cpu_irq		: 	std_logic;
signal cpu_nmi		:	std_logic;

-- Roms 2K area each
signal rom_address			:	std_logic_vector(10 downto 0);

signal rom0_dout	:	std_logic_vector(7 downto 0);
signal rom0_cs		: 	std_logic;
signal rom1_dout	:	std_logic_vector(7 downto 0);
signal rom1_cs		: 	std_logic;
signal rom2_dout	:	std_logic_vector(7 downto 0);
signal rom2_cs		: 	std_logic;
signal rom3_dout	:	std_logic_vector(7 downto 0);
signal rom3_cs		: 	std_logic;
signal rom4_dout	:	std_logic_vector(7 downto 0);
signal rom4_cs		: 	std_logic;
signal rom5_dout	:	std_logic_vector(7 downto 0);
signal rom5_cs		: 	std_logic;

signal wr_rom0		: 	std_logic;
signal wr_rom1		: 	std_logic;
signal wr_rom2		: 	std_logic;
signal wr_rom3		: 	std_logic;
signal wr_rom4		: 	std_logic;
signal wr_rom5		: 	std_logic;

-- pia1
signal pia1_dout	:	std_logic_vector(7 downto 0);
signal pia1_irq_a	:	std_logic;
signal pia1_irq_b	:	std_logic;
signal pia1_cs		:	std_logic;
signal pia1_pa_o	:	std_logic_vector(7 downto 0);
signal pia1_pa_i	:	std_logic_vector(7 downto 0);
signal pia1_ca1	:	std_logic;
--signal pia1_ca2	:	std_logic;
signal pia1_cb1	:	std_logic;

-- pia2
signal pia2_dout	:	std_logic_vector(7 downto 0);
signal pia2_irq_a	:	std_logic;
signal pia2_irq_b	:	std_logic;
signal pia2_cs		:	std_logic;
-- pia3
signal pia3_dout	:	std_logic_vector(7 downto 0);
signal pia3_irq_a	:	std_logic;
signal pia3_irq_b	:	std_logic;
signal pia3_cs		:	std_logic;
signal pia3_pa_o	:	std_logic_vector(7 downto 0);
signal pia3_pb_o	:	std_logic_vector(7 downto 0);
-- pia4
signal pia4_dout	:	std_logic_vector(7 downto 0);
signal pia4_irq_a	:	std_logic;
signal pia4_irq_b	:	std_logic;
signal pia4_cs		:	std_logic;
signal pia4_pa_o	:	std_logic_vector(7 downto 0);
signal pia4_pb_o	:	std_logic_vector(7 downto 0);
-- pia5
signal pia5_dout	:	std_logic_vector(7 downto 0);
signal pia5_irq_a	:	std_logic;
signal pia5_irq_b	:	std_logic;
signal pia5_cs		:	std_logic;
signal pia5_pa_o	:	std_logic_vector(7 downto 0);
signal pia5_pb_o	:	std_logic_vector(7 downto 0);

--IC19 5101 cmos ram
signal cmos_dout_a	: 	std_logic_vector(7 downto 0);
signal cmos_dout_b	: 	std_logic_vector(7 downto 0);
signal cmos_cs			:	std_logic;
signal cmos_wren			:	std_logic;

--ram
signal ram_S4_cs		:	std_logic;
signal ram_S7_cs		:	std_logic;
signal ram_dout	: 	std_logic_vector(7 downto 0);
signal ram_cs		:	std_logic;
signal ram_wren		:	std_logic;
signal mem_prot_ram_cs		:	std_logic;
signal mem_prot_active		:	std_logic;


--solenoids
signal sp_solenoid	:	std_logic_vector(7 downto 0); --6 special solenoids 
																		--plus two solenoids for flippers
signal SPC_Sol_Trig_stable	:	std_logic_vector(6 downto 1); --stable switches spec sol trigger
signal sp_solenoid_trig	:	std_logic_vector(6 downto 1); --6 special solenoids from trigger 
signal sp_solenoid_mpu	:	std_logic_vector(6 downto 1); --6 special solenoids from MPU (selftest)

-- diff
signal GameOn		:	std_logic;
signal gen_irq		:	std_logic;
signal blanking	:	std_logic:='1';
signal eeprom_trigger	:	std_logic:='0';
signal eeprom_wr_in_progress	:	std_logic:='1';

-- SD card
signal address_sd_card	:  std_logic_vector(15 downto 0);
signal data_sd_card	:  std_logic_vector(7 downto 0);
signal wr_rom			:  std_logic;
signal wr_game_rom			:  std_logic;
signal wr_system_rom			:  std_logic;
signal SDcard_MOSI	:	std_logic; 
signal SDcard_CLK		:	std_logic; 
signal SDcard_error	:	std_logic:='1'; --active low

-- EEprom 
signal address_eeprom	:  std_logic_vector(7 downto 0);
signal data_eeprom	:  std_logic_vector(7 downto 0);
signal wr_ram			:  std_logic;
signal EEprom_MOSI	:	std_logic; 
signal EEprom_CLK		:	std_logic; 
signal eeprom_read_done_l		:	std_logic:='1'; 

-- init & boot message helper
signal g_dig0					:  std_logic_vector(3 downto 0);
signal g_dig1					:  std_logic_vector(3 downto 0);
signal o_dig0					:  std_logic_vector(3 downto 0);
signal o_dig1					:  std_logic_vector(3 downto 0);
signal b_dig0					:  std_logic_vector(3 downto 0);
signal b_dig1					:  std_logic_vector(3 downto 0);
signal sbo_dig0					:  std_logic_vector(3 downto 0);
signal sbo_dig1					:  std_logic_vector(3 downto 0);

-- dip games select and options
signal game_select 		:  std_logic_vector(5 downto 0);				
signal game_option		: 	std_logic_vector(6 downto 1);
signal sb_option		: 	std_logic_vector(4 downto 1);
signal game_sw_strobe : 	std_logic_vector(7 downto 0);
signal dipstrobe : 	std_logic_vector(3 downto 0);

--displays
signal game_disp_strobe :	std_logic_vector(3 downto 0);
signal bm_disp_strobe :	std_logic_vector(3 downto 0);
signal sbtest_disp_strobe :	std_logic_vector(3 downto 0);
signal game_disp_bcd 	:	std_logic_vector(7 downto 0);
signal bm_disp_bcd 	:	std_logic_vector(7 downto 0);
signal sbtest_disp_bcd 	:	std_logic_vector(7 downto 0);

-- switches Williams CPU
signal diag_stable	:	std_logic; --NMI
signal Diag_NMI	:	std_logic;
signal enter_stable	:	std_logic;

-- comma & sound system7
signal comma12 	: std_logic;
signal comma34		: std_logic;
signal diag_LED	: std_logic;
signal sound_sys7		: std_logic_vector(4 downto 0);

--div
signal sound_sys3		: std_logic_vector(4 downto 0);
signal sound_com		: std_logic_vector(4 downto 0);
signal sound_test		: std_logic_vector(4 downto 0);

signal opt_nvram_init_n	: std_logic;
-- trigger
--signal credit_sw			: std_logic;

signal sp_solenoid1_mpu_filtered	: std_logic;

-- soundboard

-- Roms 4K area each
signal sb_address			:	std_logic_vector(11 downto 0);
signal sbrom_address			:	std_logic_vector(11 downto 0);

signal sbrom1_dout	: 	std_logic_vector(7 downto 0);	
signal sbrom2_dout	: 	std_logic_vector(7 downto 0);		
signal sbrom3_dout	: 	std_logic_vector(7 downto 0);	
signal sbrom4_dout	: 	std_logic_vector(7 downto 0);	
signal sbrom5_dout	: 	std_logic_vector(7 downto 0);	
	
-- address decoding helper
signal sbrom1_cs		: std_logic;
signal sbrom2_cs		: std_logic;
signal sbrom3_cs		: std_logic;
signal sbrom4_cs		: std_logic;
signal sbrom5_cs		: std_logic;

signal wr_sbrom1		: std_logic;
signal wr_sbrom2		: std_logic;
signal wr_sbrom3		: std_logic;
signal wr_sbrom4		: std_logic;
signal wr_sbrom5		: std_logic;

-- soundtest
signal soundtest_active		: std_logic := '0';

-- CRC
signal crc16 : std_logic_vector (15 downto 0);
signal crc16_r : std_logic_vector (15 downto 0);
signal crc_dig	:  std_logic_vector(3 downto 0);
signal crc_error	: std_logic;

-- SW version
-- Board-ID 6 seit 07.2026: die 5 ging an 'WillFA7 - CycloneIV_dev_open', das vorher
-- mit 4.17 gegen die Cyclone-10-Variante kollidierte. Der Funktionsstand (.03) bleibt
-- unveraendert - diese Variante ruht, siehe VARIANTEN.md.
constant SW_MAIN : std_logic_vector(3 downto 0) := x"6";
constant SW_SUB1 : std_logic_vector(3 downto 0) := x"0";
constant SW_SUB2 : std_logic_vector(3 downto 0) := x"3";

begin

LED_status <= not boot_phase(0); -- for display blanking
LED_sd_Error <=  SDcard_error;
LED_active <= blanking;

opt_nvram_init_n <= game_option(1); -- 0 if option Dip1 is set
----------------
-- boot phases
----------------
-----------------------------------------------
-- phase 0: activated by switch on FPGA board	
-- show (own) boot message
-- read first time dip settings which sets boot phase 1
-----------------------------------------------
META1: entity work.Cross_Slow_To_Fast_Clock
port map(
   i_D => reset_sw and pll_locked,
	o_Q => boot_phase(0),
   i_Fast_Clk => clk_50
	); 

-- display bm switch, switch to game in boot phase 3 or to soundtest
disp_bcd <= 
	   sbtest_disp_bcd when soundtest_active = '1' else
		bm_disp_bcd when boot_phase(3) = '0'
		else game_disp_bcd;
disp_strobe <= 
	   sbtest_disp_strobe when soundtest_active = '1' else
		bm_disp_strobe when boot_phase(3) = '0'
		else game_disp_strobe;

crc_dig <= x"7" when crc_error = '1' else x"F";
BM: entity work.boot_message
port map(
	clk		=> clk_50, 	
	-- Control/Data Signals,
   show  => boot_phase(0),    
	--show error
	is_error => SDcard_error, --active low
	-- output
	strobe	=> bm_disp_strobe,
	bcd	=> bm_disp_bcd,
	-- input (display data)
	display1	=> ( x"F",x"5",x"F",SW_MAIN,SW_SUB1,SW_SUB2 ),
	display2	=> ( x"F",x"F",x"F", x"0", g_dig1, g_dig0),
	--display3	=> ( x"0",x"5",x"0",x"9",x"6",x"3" ),
	display3	=> ( x"F",x"F", crc16( 15 downto 12),crc16( 11 downto 8), crc16( 7 downto 4), crc16( 3 downto 0)),
	--display4	=> ( x"F",x"F",x"F",x"F",b_dig1, b_dig0),
	display4	=> ( x"F",x"F", crc16_r( 15 downto 12),crc16_r( 11 downto 8), crc16_r( 7 downto 4), crc16_r( 3 downto 0)),
	error_disp4 => ( crc_dig,x"5",x"6",x"F",b_dig1, b_dig0),
	status_d	=> ( sbo_dig0, sbo_dig1, o_dig0, o_dig1 )
	);
	
-- switch strobes controlled by game in boot phase 1
sw_strobe(7) <= game_sw_strobe(7) when boot_phase(1) = '1' else dipstrobe(0);
sw_strobe(6) <= game_sw_strobe(6);
sw_strobe(5) <= game_sw_strobe(5) when boot_phase(1) = '1' else dipstrobe(1);
sw_strobe(4) <= game_sw_strobe(4);
sw_strobe(3) <= game_sw_strobe(3) when boot_phase(1) = '1' else dipstrobe(2);
sw_strobe(2) <= game_sw_strobe(2);
sw_strobe(1) <= game_sw_strobe(1) when boot_phase(1) = '1' else dipstrobe(3);
sw_strobe(0) <= game_sw_strobe(0);

RDIPS: entity work.read_the_dips
port map(
	clk_in		=> cpu_clk,
	i_Rst_L  => boot_phase(0),   
	--output 
	game_select	=> game_select,
	game_option	=> game_option,
	sb_option => sb_option,
	-- strobes
	dipstrobe1 => dipstrobe(0),
	dipstrobe2 => dipstrobe(1),
	dipstrobe3 => dipstrobe(2),
	dipstrobe4 => dipstrobe(3),
	-- input
	return1 => Dip_Ret_1,
	return2 => Dip_Ret_2,
	return3 => Dip_Ret_3,
	return4 => Dip_Ret_4,
	-- signal when finished
	done	=> boot_phase(1) -- set to '1' when reading dips is done
	);	

-----------------------------------------------
-- phase 1: activated by 'read_the_dips' after first read
-- read rom data of current game from SD
------------------------------------------------

--shared SPI bus; SD card only at start of game
MOSI <= SDcard_MOSI when boot_phase(2) = '0' else EEprom_MOSI;
SPI_CLK <= SDcard_CLK when boot_phase(2) = '0' else EEprom_CLK;

---------------------
-- SD card stuff
----------------------
SD_CARD: entity work.SD_Card
port map(
	i_clk		=> clk_50,	
	-- Control/Data Signals,
   i_Rst_L  => boot_phase(1), -- first dip read finished
	-- PMOD SPI Interface
   o_SPI_Clk  => SDcard_CLK,
   i_SPI_MISO => MISO,
   o_SPI_MOSI => SDcard_MOSI,
   o_SPI_CS_n => CS_SDcard,	
	-- selection
	selection => "00" & not game_select,
	--selection => not game_select,
	-- data
	address_sd_card => address_sd_card,
	data_sd_card => data_sd_card,
	wr_rom => wr_rom,
	-- feedback
	calc_checksum => crc16,
	read_checksum => crc16_r,
	crc_error => crc_error,
	SDcard_error => SDcard_error,
	-- control boot phases
	cpu_reset_l => boot_phase(2)
	);	
	
-----------------------------------------------
-- phase 2: activated by SD card read
-- read eeprom, read/write to ram
----------------------
EEprom: entity work.EEprom
port map(
	i_clk => clk_50,
	address_eeprom	=> address_eeprom,
	data_eeprom	=> data_eeprom,
	wr_ram => wr_ram,
	q_ram => cmos_dout_b,
	-- Control/Data Signals,   
	i_Rst_L  => boot_phase(2),
	-- PMOD SPI Interface
   o_SPI_Clk  => EEprom_CLK,
   i_SPI_MISO => MISO,
   o_SPI_MOSI => EEprom_MOSI,
   o_SPI_CS_n => CS_EEprom,
	-- selection
	selection => "00" & not game_select,
	-- write trigger
	w_trigger(4) => Enter_stable, -- for save within setup sys3
	w_trigger(3) => GameOn, --game_over_relay,
	w_trigger(2) => eeprom_trigger, -- intial write via ctrl_blanking 5sec after start RTH
	w_trigger(1) => advance,-- for save within setup menue
	w_trigger(0) => game_option(5), -- as trigger for testing
	-- init trigger (no read, RAM will be zero)
	i_init_Flag => opt_nvram_init_n, -- 0 if option Dip1 is set 
	-- signal when finished
		-- signal when finished
	done	=> boot_phase(3), -- set to '1' when first read of eeprom and write to cmos is done
	o_wr_in_progress => eeprom_wr_in_progress
	);	
-----------------------------------------------
-- phase 3: activated by eeprom after first read/write
-- now williams rom take control
-- game starts here
---------------------------------------------------

reset_l <= boot_phase(3);
reset_h <= (not reset_l);

----------------------
-- Diag
----------------------
--sys3..4
--pia1_ca1 <= advance; -- Advance
--pia1_cb1 <= up_down; -- up/down
--sys6..7 use IRQ with OR
pia1_ca1 <= not ( not advance or not cpu_irq); 
pia1_cb1 <= not ( not up_down or not cpu_irq); 

-- BT28 IC Bus Driver Receiver
pia1_pa_i <= W_PA_DIP & x"F" when ( Enter_stable = '0' and soundtest_active = '0' ) else x"FF"; -- enter SW activates input
Diag_LED <= not pia1_pa_o(5) when opt_nvram_init_n = '1' else eeprom_wr_in_progress; -- to show when eeprom has saved
Diag_NMI <= not diag_stable when soundtest_active = '0' else '0';

DIAGSTABLE: entity work.Cross_Slow_To_Fast_Clock
port map(
   i_D => DIAG_SW,
	o_Q => diag_stable,
   i_Fast_Clk => cpu_clk
	);
	
ENTERSTABLE: entity work.Cross_Slow_To_Fast_Clock
port map(
   i_D => ENTER_SW,
	o_Q => enter_stable,
   i_Fast_Clk => cpu_clk
	);

--NMI	
DIAGSW: entity work.one_pulse_only
port map(
   sig_in => Diag_NMI,
	sig_out => cpu_nmi,
   clk_in => cpu_clk,
	rst => reset_l
	);


----------------------
-- Flipper activation
----------------------
sp_solenoid(6) <= GameOn; --Flipper
sp_solenoid(7) <= GameOn; --Flipper



----------------------
-- displays
----------------------
game_disp_strobe <= pia1_pa_o(3 downto 0);
comma34 <= pia5_pb_o(6);
comma12 <= pia5_pb_o(7);

-- IRQ signals ( should be '0')
cpu_irq <= pia1_irq_a or pia1_irq_b 
			  or pia2_irq_a or pia2_irq_b
			  or pia3_irq_a or pia3_irq_b
			  or pia4_irq_a or pia4_irq_b
			  or pia5_irq_a or pia5_irq_b
			  or gen_irq;			  

------------------
-- address decoding 
------------------
--
--roms 2K each
rom0_cs   <= '1' when cpu_addr(14 downto 11) = "1010" and cpu_vma='1' else '0'; --5000-57FF
rom1_cs   <= '1' when cpu_addr(14 downto 11) = "1011" and cpu_vma='1' else '0'; --5800-5FFF
rom2_cs   <= '1' when cpu_addr(14 downto 11) = "1100" and cpu_vma='1' else '0'; --6000-67FF
rom3_cs   <= '1' when cpu_addr(14 downto 11) = "1101" and cpu_vma='1' else '0'; --6800-6FFF
rom4_cs   <= '1' when cpu_addr(14 downto 11) = "1110" and cpu_vma='1' else '0'; --7000-77FF
rom5_cs   <= '1' when cpu_addr(14 downto 11) = "1111" and cpu_vma='1' else '0'; --7800-7FFF

------------------
-- ROMs ----------
------------------
-- moved to RAM, initial read from SD
-- one file of 12Kbyte for all Williams variants 
-- mapping is done within 12KByte file
-- address selection: read from SD when wr_rom == 1
-- else map to address room
wr_rom0 <= '1' when address_sd_card(15 downto 11) = "00000" and wr_rom='1' else '0'; --0..2 K
wr_rom1 <= '1' when address_sd_card(15 downto 11) = "00001" and wr_rom='1' else '0'; --2..4 K
wr_rom2 <= '1' when address_sd_card(15 downto 11) = "00010" and wr_rom='1' else '0'; --4..6 K
wr_rom3 <= '1' when address_sd_card(15 downto 11) = "00011" and wr_rom='1' else '0'; --6..8 K
wr_rom4 <= '1' when address_sd_card(15 downto 11) = "00100" and wr_rom='1' else '0'; --8..10 K
wr_rom5 <= '1' when address_sd_card(15 downto 11) = "00101" and wr_rom='1' else '0'; --10..12 K
----------------
-- Soundboard
----------------
wr_sbrom1 <= '1' when address_sd_card(15 downto 12) = "0011" and wr_rom='1' else '0'; --12..16 k
wr_sbrom2 <= '1' when address_sd_card(15 downto 12) = "0100" and wr_rom='1' else '0'; --16..20 k
wr_sbrom3 <= '1' when address_sd_card(15 downto 12) = "0101" and wr_rom='1' else '0'; --20..24 k
wr_sbrom4 <= '1' when address_sd_card(15 downto 12) = "0110" and wr_rom='1' else '0'; --24..28 k
wr_sbrom5 <= '1' when address_sd_card(15 downto 12) = "0111" and wr_rom='1' else '0'; --28..32 k

rom_address <= 
  address_sd_card(10 downto 0) when wr_rom = '1' else
  cpu_addr(10 downto 0);	

sbrom_address <=
  address_sd_card(11 downto 0) when wr_rom = '1' else
  sb_address;
  
--pias
pia1_cs   <= not cpu_addr(14) and cpu_addr(13) and cpu_addr(11) and cpu_vma; --2800 Display&Diag
pia2_cs   <= not cpu_addr(14) and cpu_addr(13) and cpu_addr(12) and cpu_vma; --3000 Switches
pia3_cs   <= not cpu_addr(14) and cpu_addr(13) and cpu_addr(10) and cpu_vma; --2400 Lamps
pia4_cs <= not cpu_addr(14) and cpu_addr(13) and cpu_addr(9) and cpu_vma; --2200 Solenoids
pia5_cs <= not cpu_addr(14) and cpu_addr(13) and cpu_addr(8) and cpu_vma; --2100 Sound & comma (SYS7 only)
--pia1_cs   <= '1' when cpu_addr(14 downto 2) = "00101000000000" and cpu_vma='1' else '0'; --2800 Display&Diag
--pia2_cs   <= '1' when cpu_addr(14 downto 2) = "00110000000000" and cpu_vma='1' else '0'; --3000 Switches
--pia3_cs   <= '1' when cpu_addr(14 downto 2) = "00100100000000" and cpu_vma='1' else '0'; --2400 Lamps
--pia4_cs   <= '1' when cpu_addr(14 downto 2) = "00100010000000" and cpu_vma='1' else '0'; --2200 Solenoids
--pia5_cs   <= '1' when cpu_addr(14 downto 2) = "00100001000000" and cpu_vma='1' else '0'; --2100 Sound & comma (SYS7 only)
-- pia at 0x4000??? -> Hyperball only not implemented

--ram
cmos_cs <= not cpu_addr(14) and not cpu_addr(13) and not cpu_addr(12) and not cpu_addr(9) and cpu_addr(8) and cpu_vma;
--ram_S7_cs <= not cpu_addr(14) and not cpu_addr(13);
--ram_cs <= ram_S7_cs and not cmos_cs;

ram_S4_cs <= '1' when cpu_addr(14 downto 8) = "0000000" and cpu_vma='1' else '0'; --0x0000 0x00ff (SYS3-6 compatibility)
--cmos_cs <= '1' when cpu_addr(14 downto 8) = "0000001" and cpu_vma='1' else '0'; --0x0100 0x01ff
ram_S7_cs <= '1' when cpu_addr(14 downto 10) = "00100" and cpu_vma='1' else '0';  -- 0x1000 0x13ff
ram_cs <= ram_S4_cs or ram_S7_cs; 

--write enable - RTH do we need mem_prot?
--cmos_wren <= cmos_cs and not cpu_rw;
cmos_wren <= cmos_cs and not cpu_rw and not mem_prot_active; 
ram_wren <= ram_cs and not cpu_rw;
 
-- memory protect area, with SYS6&7 cmos is only writable if coindoor open
mem_prot_ram_cs <= '1' when cpu_addr(14 downto 7) = "00000011" and cpu_vma='1' else '0'; --0x0180 0x01ff
mem_prot_active <= mem_prot_ram_cs and mem_prot and opt_nvram_init_n; --mem_prot active high due to inverter on WillFA7


-- Bus control
 cpu_din <=    	
	pia1_dout when pia1_cs = '1' else
	pia2_dout when pia2_cs = '1' else
	pia3_dout when pia3_cs = '1' else
	pia4_dout when pia4_cs = '1' else	
	pia5_dout when pia5_cs = '1' else
	rom0_dout when rom0_cs = '1' else
	rom1_dout when rom1_cs = '1' else
	rom2_dout when rom2_cs = '1' else
	rom3_dout when rom3_cs = '1' else	
	rom4_dout when rom4_cs = '1' else	
	rom5_dout when rom5_cs = '1' else	
	ram_dout when ram_cs = '1' else
	cmos_dout_a when cmos_cs = '1' else
	x"FF";

-- detect credit and test_switch for trigger
--credit_sw <= sw_strobe(0) and sw_return(2);
-- due to iverters on the borad switch is active when both strobe and return are HIGH
-- credit switch is strobe 0 and return 2
--credit switch trigger with timer
--detect_credit_sw_trigger: entity work.detect_sw
--port map(
--	sw_strobe => sw_strobe(0),
--	sw_return => sw_return(2),
--	is_closed => credit_sw
--);



---------------------
-- count ints
-- indicate game running or not
-- set blanking and (first) eeprom trigger
---------------------
COUNT_STROBES: entity work.count_to_zero
port map(   
   Clock => clk_50,
	clear => reset_l,
	d_in => game_disp_strobe(2),
	count_a =>"00001111", -- blanking
	count_b =>"111111111", -- eeprom trigger	
	d_out_a => blanking,
	d_out_b => eeprom_trigger
);	
	
	
-- for game select to visiualize
CONVG: entity work.byte_to_decimal
port map(
	clk_in	=> clk_50, 	
	mybyte	=> "11" & game_select,
	dig0 => g_dig0,
	dig1 => g_dig1,
	dig2 => open
	);
-- for willfa option to visiualize
CONVO: entity work.byte_to_decimal
port map(
	clk_in	=> clk_50, 	
	mybyte	=> "11" & game_option,
	dig0 => o_dig0,
	dig1 => o_dig1,
	dig2 => open
	);
-- for boot phase to visiualize
boot_phase_dig <= "0000" when boot_phase="0000" else -- phase 0
						"0001" when boot_phase="0001" else -- phase 1
						"0010" when boot_phase="0011" else -- phase 2
						"0011" when boot_phase="0111" else -- phase 3
						"0100"; -- pghase 4 , never reached
						
CONVB: entity work.byte_to_decimal
port map(
	clk_in	=> clk_50, 	
	mybyte	=> "1111" & not boot_phase_dig,
	dig0 => b_dig0,
	dig1 => b_dig1,
	dig2 => open
	);
	

CONVSBO: entity work.byte_to_decimal
port map(
	clk_in	=> clk_50, 	
	mybyte	=> "1111" & sb_option,
	dig0 => sbo_dig0,
	dig1 => sbo_dig1,
	dig2 => open
	);
	
----------------------
-- clock for read the dips
----------------------
--CLK_RDIPS: entity work.clk_900Hz_gen
--port map(
--	clk_in		=> cpu_clk, 	
--	clk_out		=> dip_clk	
--	);
	
--------------------
-- Flip Flop Solenoids
------------------
FF_SOLS: entity work.flipflops
port map(
	clk_in => cpu_clk, 
	rst => blanking,
	sel1 => sol_1_8_sel,
	sel2 => sol_9_16_sel,
	sel3 => sol_spec_sel,		
	ff_data_out	=> solenoids,
   ff1_data_in(0) => pia4_pa_o(3), -- Sol_4
	ff1_data_in(1) => pia4_pa_o(1),-- Sol_2
	ff1_data_in(2) => pia4_pa_o(5),-- Sol_6
	ff1_data_in(3) => pia4_pa_o(7),-- Sol_8
	ff1_data_in(4) => pia4_pa_o(6),-- Sol_7
	ff1_data_in(5) => pia4_pa_o(0),-- Sol_1
	ff1_data_in(6) => pia4_pa_o(2),-- Sol_3
	ff1_data_in(7) => pia4_pa_o(4),	-- Sol_5
	ff2_data_in(0) => pia4_pb_o(1), -- Sol_10
	ff2_data_in(1) => pia4_pb_o(5), -- Sol_14	
	ff2_data_in(2) => pia4_pb_o(4), -- Sol_13
	ff2_data_in(3) => pia4_pb_o(2), -- Sol_11
	ff2_data_in(4) => pia4_pb_o(3), -- Sol_12
	ff2_data_in(5) => pia4_pb_o(6), -- Sol_15
	ff2_data_in(6) => pia4_pb_o(7), -- Sol_16
	ff2_data_in(7) => pia4_pb_o(0), -- Sol_9
	ff3_data_in(0) => sp_solenoid(4), -- Spec_Sol_5
	ff3_data_in(1) => sp_solenoid(3),-- Spec_Sol_4
	ff3_data_in(2) => sp_solenoid(2),-- Spec_Sol_3
	ff3_data_in(3) => sp_solenoid(6),-- Flipper_GND_1
	ff3_data_in(4) => sp_solenoid(7),-- Flipper_GND_1
	ff3_data_in(5) => sp_solenoid(1),-- Spec_Sol_2
	ff3_data_in(6) => sp_solenoid(0),-- Spec_Sol_1
	ff3_data_in(7) => sp_solenoid(5) -- Spec_Sol_6
);

--------------------
-- Flip Flop Lamps
------------------
FF_LAMPSS: entity work.flipflops
port map(
	clk_in => cpu_clk,
	rst => blanking,
	sel1 => lamp_strobe_sel,
	sel2 => lamp_row_sel,
	sel3 => sound_com_sel,		
	ff_data_out	=> lamps,
   ff1_data_in(0) => pia3_pb_o(6), --lamp strobe 7
	ff1_data_in(1) => pia3_pb_o(4), --lamp strobe 5
	ff1_data_in(2) => pia3_pb_o(3), --lamp strobe 4
	ff1_data_in(3) => pia3_pb_o(0), --lamp strobe 1
	ff1_data_in(4) => pia3_pb_o(1), --lamp strobe 2
	ff1_data_in(5) => pia3_pb_o(2), --lamp strobe 3
	ff1_data_in(6) => pia3_pb_o(5), --lamp strobe 6
	ff1_data_in(7) => pia3_pb_o(7), --lamp strobe 8
	ff2_data_in(0) => not pia3_pa_o(7), --lamp row 8
	ff2_data_in(1) => not pia3_pa_o(4), --lamp row 5
	ff2_data_in(2) => not pia3_pa_o(3), --lamp row 4
	ff2_data_in(3) => not pia3_pa_o(1), --lamp row 2
	ff2_data_in(4) => not pia3_pa_o(0), --lamp row 1
	ff2_data_in(5) => not pia3_pa_o(2), --lamp row 3
	ff2_data_in(6) => not pia3_pa_o(5), --lamp row 6
	ff2_data_in(7) => not pia3_pa_o(6), --lamp row 7
	ff3_data_in(0) => comma34,
	ff3_data_in(1) => Diag_LED,
	ff3_data_in(2) => sound_com(3),
	ff3_data_in(3) => sound_com(0),
	ff3_data_in(4) => sound_com(1),
	ff3_data_in(5) => sound_com(2),
	ff3_data_in(6) => sound_com(4),
	ff3_data_in(7) => comma12
);



U9: entity work.cpu68
port map(
	clk => cpu_clk,
	rst => reset_h,
	rw => cpu_rw,
	vma => cpu_vma,
	address => cpu_addr,
	data_in => cpu_din,
	data_out => cpu_dout,
	hold => '0',
	halt => '0',
	irq => cpu_irq,
	nmi => cpu_nmi
);


-- PIA I CPU board (2800) Displays & Diag
--	 IRQA IRQ/'
--	 IRQB IRQ/'
--	 PA0-3 Digit Select
--	 PA4-7 Diagnostic LED 
--	 PB0-8 BCD output
--	 CA1	 Diag in
--  CA2   Diag LED control?
--	 CB1	 Diag in
--  CB2   SS6    
PIA1: entity work.PIA6821
port map(
	clk => cpu_clk,   
   rst => reset_h,     
   cs => pia1_cs,     
   rw => cpu_rw,    
   addr => cpu_addr(1 downto 0),     
   data_in => cpu_dout,  
	data_out => pia1_dout, 
	irqa => pia1_irq_a,   
	irqb => pia1_irq_b,    
	pa_i => pia1_pa_i,
	pa_o => pia1_pa_o,
	ca1 => pia1_ca1,
	ca2_i => '1',
	--ca2_o => pia1_ca2,
	pb_i => x"FF",
	pb_o => game_disp_bcd,
	cb1 => pia1_cb1,
	cb2_i => '1',
	cb2_o => sp_solenoid_mpu(6),
	default_pb_level => '0'  -- output level when configured as input
);

-- PIA II driver board (3000) Switches
--	 IRQA IRQ/'
--	 IRQB IRQ/'
--	 PA0-7 Switch return
--	 PB0-7 Switch drive
--	 CA1	pull down(0)
--  CA2  SS4
--	 CB1	pull down(0)
--  CB2  SS3
PIA2: entity work.PIA6821
port map(
	clk => cpu_clk,
   rst => reset_h,     
   cs => pia2_cs,     
   rw => cpu_rw,    
   addr => cpu_addr(1 downto 0),     
   data_in => cpu_dout,  
	data_out => pia2_dout, 
	irqa => pia2_irq_a,   
	irqb => pia2_irq_b,    
	pa_i => sw_return,
	pa_o => open,
	ca1 => '0',
	ca2_i => '1',
	ca2_o => sp_solenoid_mpu(4),
	pb_i => x"FF",
	pb_o => game_sw_strobe,
	cb1 => '0',
	cb2_i => '1',
	cb2_o => sp_solenoid_mpu(3),
	default_pb_level => '0'  -- output level when configured as input
);
-- PIA III driver board (2400) Lamps
--	 IRQA IRQ/'
--	 IRQB IRQ/'
--	 PA0-7 Lamp Return
--	 PB0-7 Lamp Strobe
--	 CA1	pull down(0)
--  CA2  SS2
--	 CB1	pull down(0)
--  CB2  SS1
PIA3: entity work.PIA6821
port map(
	clk => cpu_clk,   
   rst => reset_h,     
   cs => pia3_cs,     
   rw => cpu_rw,    
   addr => cpu_addr(1 downto 0),     
   data_in => cpu_dout,  
	data_out => pia3_dout, 
	irqa => pia3_irq_a,   
	irqb => pia3_irq_b,    
	pa_i => x"FF",
	pa_o => pia3_pa_o,
	ca1 => '0',
	ca2_i => '1',
	ca2_o => sp_solenoid_mpu(2),
	pb_i => x"FF",
	pb_o => pia3_pb_o,
	cb1 => '0', --PIA_UNUSED_VAL(0)
	cb2_i => '1',
	cb2_o => sp_solenoid_mpu(1),
	default_pb_level => '0'  -- output level when configured as input
);
-- PIA IV driver board (2200) Solenoids
--	 IRQA IRQ/'
--	 IRQB IRQ/'
--	 PA0-7 Sol 1-8
--	 PB0-7 Sol 9-16
--	 CA1	pull down(0)
--  CA2  SS5
--	 CB1	pull down(0)
--  CB2  GameOn (0)
PIA4: entity work.PIA6821
port map(
	clk => cpu_clk,   
   rst => reset_h,     
   cs => pia4_cs,     
   rw => cpu_rw,    
   addr => cpu_addr(1 downto 0),     
   data_in => cpu_dout,  
	data_out => pia4_dout, 
	irqa => pia4_irq_a,   
	irqb => pia4_irq_b,    
	pa_i => x"FF",
	pa_o => pia4_pa_o,
	ca1 => '0',
	ca2_i => '1',
	ca2_o => sp_solenoid_mpu(5),
	pb_i => x"FF",
	pb_o => pia4_pb_o,
	cb1 => '0', --PIA_UNUSED_VAL(0)
	cb2_i => '1',
	cb2_o => GameOn,
	default_pb_level => '0'  -- output level when configured as input
);

-- PIA V CPU board (2100) Sound
--	 IRQA IRQ/'
--	 IRQB IRQ/'
--	 PA0-4 Sound
--	 PA5-6 not used?
--	 PA7 -> pull up(1)
--	 PB0-5 -> pull up(1) J9-27,29,31,33,35
--  PB5   connected CA1
--  PB6   Comma 3+4
--  PB7   Comma 1+2
--	 CA1	 connected to PB5
--  CA2   SS8
--	 CB1	 pull down(0)
--  CB2   SS7    
PIA5: entity work.PIA6821
port map(
	clk => cpu_clk,   
   rst => reset_h,     
   cs => pia5_cs,     
   rw => cpu_rw,    
   addr => cpu_addr(1 downto 0),     
   data_in => cpu_dout,  
	data_out => pia5_dout, 
	irqa => pia5_irq_a,   
	irqb => pia5_irq_b,    
	pa_i => x"00",
	pa_o => pia5_pa_o,
	ca1 => '1', -- PIA_UNUSED_VAL(1) pia5_pb_o(5)?
	ca2_i => '1',
	ca2_o => open, --SS8 not used
	pb_i => x"3F", --PIA_UNUSED_VAL(0x3f)
	pb_o => pia5_pb_o,
	cb1 => '0', -- PIA_UNUSED_VAL(0)
	cb2_i => '1',
	cb2_o => open,  --SS7 not used
	default_pb_level => '0'  -- output level when configured as input
);
	 

-- PLL takes 50MHz clock on mini board and puts out 14.28MHz	
PLL: entity work.williams_pll
port map(
	inclk0 => clk_50,
	c0 => clk_14,
	c1 => cpu_clk,
	locked => pll_locked
	);
	
--clock_gen: entity work.cpu_clk_gen
--port map(   
--	clk_in => clk_14,
--	clk_out	=> cpu_clk,
--	shift_clk_out	=> mem_clk
--);


irq_gen: entity work.irq_generator
port map(   
	clk => not cpu_clk,	-- phi2	
	cpu_irq => cpu_irq,
	gen_irq => gen_irq
);


----------------------
-- 5101 ram (dual port)
----------------------
IC19: entity work.R5101 -- 5101 RAM 128Byte (256 * 4bit) 
	port map(
		address_a	=> cpu_addr(7 downto 0),
		address_b   => address_eeprom,
		clock			=> clk_50,
		data_a		=> cpu_dout,
		data_b		=> data_eeprom,
		wren_a 		=> cmos_wren,
		wren_b 		=> wr_ram,
		q_a			=> cmos_dout_a,
		q_b			=> cmos_dout_b
);


----------------------
-- IC13&IC16 ram
----------------------
RAM_S7: entity work.ram -- 2*2114 ram 1024byte 
port map(
	address	=> cpu_addr(9 DOWNTO 0),		
	clock => clk_50,
	data		=>  cpu_dout (7 DOWNTO 0),
	wren 		=> ram_wren,
	q			=> ram_dout
);	


------------------
-- special solenoids
------------------

-- peak filter for solenoid17 necessary as we have 9uS peaks each 2mS
P_FILTER_1: entity work.peak_filter
    generic map (   
		max_peak_len   =>  12 ) --times 1,1uS
    port map (
			  i_Rst_L => reset_l,
			  clk_in => cpu_clk,
			  sig_in => not sp_solenoid_mpu(1),
			  sig_out => sp_solenoid1_mpu_filtered
      );
--sp_solenoid(0) <= ( sp_solenoid_trig(1) or not sp_solenoid_mpu(1) ) and GameOn;
sp_solenoid(0) <= ( sp_solenoid_trig(1) or sp_solenoid1_mpu_filtered ) and GameOn;
sp_solenoid(1) <= ( sp_solenoid_trig(2) or not sp_solenoid_mpu(2) ) and GameOn;
sp_solenoid(2) <= ( sp_solenoid_trig(3) or not sp_solenoid_mpu(3) ) and GameOn;
sp_solenoid(3) <= ( sp_solenoid_trig(4) or not sp_solenoid_mpu(4) ) and GameOn;
sp_solenoid(4) <= ( sp_solenoid_trig(5) or not sp_solenoid_mpu(5) ) and GameOn;
sp_solenoid(5) <= ( sp_solenoid_trig(6) or not sp_solenoid_mpu(6) ) and GameOn;
------------------
META_SPECIAL1: entity work.Cross_Slow_To_Fast_Clock
port map(
   i_D => SPC_Sol_Trig(1),
	o_Q => SPC_Sol_Trig_stable(1),
   i_Fast_Clk => clk_50
	); 
SPECIAL1: entity work.spec_sol_trigger
port map(
   clk_in => cpu_clk,
	i_Rst_L => '1', --RTH: gameon
   trigger => SPC_Sol_Trig_stable(1),
	pulse_cfg => game_option(3 downto 2),
	solenoid => sp_solenoid_trig(1)
	); 
META_SPECIAL2: entity work.Cross_Slow_To_Fast_Clock
port map(
   i_D => SPC_Sol_Trig(2),
	o_Q => SPC_Sol_Trig_stable(2),
   i_Fast_Clk => clk_50
	); 	
SPECIAL2: entity work.spec_sol_trigger
port map(
   clk_in => cpu_clk,
	i_Rst_L => '1', --RTH: gameon
   trigger => SPC_Sol_Trig_stable(2),
	pulse_cfg => game_option(3 downto 2),
	solenoid => sp_solenoid_trig(2)
	); 
META_SPECIAL3: entity work.Cross_Slow_To_Fast_Clock
port map(
   i_D => SPC_Sol_Trig(3),
	o_Q => SPC_Sol_Trig_stable(3),
   i_Fast_Clk => clk_50
	); 	
SPECIAL3: entity work.spec_sol_trigger
port map(
   clk_in => cpu_clk,
	i_Rst_L => '1', --RTH: gameon
   trigger => SPC_Sol_Trig_stable(3),
	pulse_cfg => game_option(3 downto 2),
	solenoid => sp_solenoid_trig(3)
	); 
META_SPECIAL4: entity work.Cross_Slow_To_Fast_Clock
port map(
   i_D => SPC_Sol_Trig(4),
	o_Q => SPC_Sol_Trig_stable(4),
   i_Fast_Clk => clk_50
	); 	
SPECIAL4: entity work.spec_sol_trigger
port map(
   clk_in => cpu_clk,
	i_Rst_L => '1', --RTH: gameon
   trigger => SPC_Sol_Trig_stable(4),
	pulse_cfg => game_option(3 downto 2),
	solenoid => sp_solenoid_trig(4)
	); 
META_SPECIAL5: entity work.Cross_Slow_To_Fast_Clock
port map(
   i_D => SPC_Sol_Trig(5),
	o_Q => SPC_Sol_Trig_stable(5),
   i_Fast_Clk => clk_50
	); 	
SPECIAL5: entity work.spec_sol_trigger
port map(
   clk_in => cpu_clk,
	i_Rst_L => '1', --RTH: gameon
   trigger => SPC_Sol_Trig_stable(5),
	pulse_cfg => game_option(3 downto 2),
	solenoid => sp_solenoid_trig(5)
	); 	
META_SPECIAL6: entity work.Cross_Slow_To_Fast_Clock
port map(
   i_D => SPC_Sol_Trig(6),
	o_Q => SPC_Sol_Trig_stable(6),
   i_Fast_Clk => clk_50
	); 	
SPECIAL6: entity work.spec_sol_trigger
port map(
   clk_in => cpu_clk,
	i_Rst_L => '1', --RTH: gameon
   trigger => SPC_Sol_Trig_stable(6),
	pulse_cfg => game_option(3 downto 2),
	solenoid => sp_solenoid_trig(6)
	); 
	
----------------
--roms
----------------
-- 2K area 5000h-57ffh
ROM_0: entity work.rom_2K
port map(
	address => rom_address,	
	clock => clk_50,
	data => data_sd_card,
	wren => wr_rom0,
	q	=> rom0_dout
	);

-- 2K area 5800h-5fffh
ROM_1: entity work.rom_2K
port map(
	address => rom_address,	
	clock => clk_50,
	data => data_sd_card,
	wren => wr_rom1,
	q	=> rom1_dout
	);
	
-- 2K area 6000h-67ffh
ROM_2: entity work.rom_2K
port map(
	address => rom_address,	
	clock => clk_50,
	data => data_sd_card,
	wren => wr_rom2,
	q	=> rom2_dout
	);
	
-- 2K area 6800h-6fffh
ROM_3: entity work.rom_2K
port map(
	address => rom_address,	
	clock => clk_50,
	data => data_sd_card,
	wren => wr_rom3,
	q	=> rom3_dout
	);
	
-- 2K area 7000h-77ffh
ROM_4: entity work.rom_2K
port map(
	address => rom_address,	
	clock => clk_50,
	data => data_sd_card,
	wren => wr_rom4,
	q	=> rom4_dout
	);

-- 2K area 7800h-7fffh
ROM_5: entity work.rom_2K
port map(
	address => rom_address,	
	clock => clk_50,
	data => data_sd_card,
	wren => wr_rom5,
	q	=> rom5_dout
	);

----------------
--SB roms
----------------
-- 4K area 3000h-3fffh
SB_ROM_1: entity work.SB_ROM -- ROM 4KByte 
port map(
	address => sbrom_address,	
	clock => clk_50,
	data => data_sd_card,
	wren => wr_sbrom1,
	q	=> sbrom1_dout
	);
	
-- 4K area 4000h-4fffh
SB_ROM_2: entity work.SB_ROM -- ROM 4KByte 
port map(
	address => sbrom_address,	
	clock => clk_50,
	data => data_sd_card,
	wren => wr_sbrom2,
	q	=> sbrom2_dout
	);
	
-- 4K area 5000h-5fffh
SB_ROM_3: entity work.SB_ROM -- ROM 4KByte 
port map(
	address => sbrom_address,	
	clock => clk_50,
	data => data_sd_card,
	wren => wr_sbrom3,
	q	=> sbrom3_dout
	);
	
-- 4K area 6000h-6fffh
SB_ROM_4: entity work.SB_ROM -- ROM 4KByte 
port map(
	address => sbrom_address,	
	clock => clk_50,
	data => data_sd_card,
	wren => wr_sbrom4,
	q	=> sbrom4_dout
	);

-- 4K area 7000h-7fffh
SB_ROM_5: entity work.SB_ROM -- ROM 4KByte 
port map(
	address => sbrom_address,	
	clock => clk_50,
	data => data_sd_card,
	wren => wr_sbrom5,
	q	=> sbrom5_dout
	);	

----------------
-- integrated sound
----------------
SOUNDBOARD: entity work.WISOF
port map(
		clk_50	=> clk_50,
		clk_14	=> clk_14,
		cpu_clk	=> cpu_clk,
		reset_l	=> reset_l,
		test	=> not(not SB_Test and sb_option(4)),
		sound_o	=> SB_Sound,
		speech_o => SB_Speech,
		
		Sound => sound_com,
		
		SB_Opt => sb_option,			
		
		rom1_dout => sbrom1_dout,
		rom2_dout => sbrom2_dout,
		rom3_dout => sbrom3_dout,
		rom4_dout => sbrom4_dout,
		rom5_dout => sbrom5_dout,
		
		sb_address	=> sb_address
);

----------------------
-- sound
----------------------
sound_sys7 <= pia5_pa_o(4 downto 0);
sound_sys3 <= not pia4_pb_o(4 downto 0); --solenoids #9..#13 sys3..6
sound_com <= sound_test when soundtest_active = '1' else
				 sound_sys7 when sb_option(3) = '0' else -- RTH or automated?
				 sound_sys3;


SOUNDTST: entity work.soundtest
port map(
		clk_in	=> clk_50,
		i_Rst_L	=> reset_l,
		
		activate	=> not SB_Test and not sb_option(4),
		step	=> Diag_SW,
		play	=> Enter_SW,
		soundtoplay => sound_test,
		
		is_active => soundtest_active,
		strobe => sbtest_disp_strobe,
		bcd => sbtest_disp_bcd
);
	
	
end rtl;
		