-- 'WillFA7' - a Williams System 3 to System 7 pinball MPU on a low cost FPGA
-- Ralf Thelen 'bontango' - www.lisy.dev
--
-- ONE top level for all board variants. What differs per board lives in
-- variants/<name>/: variant_pkg.vhd (BOARD_ID, ROM_COUNT, HAS_MONITOR, HAS_SOUND,
-- SD_CHECK_CRC),
-- pins.tcl, device.tcl and WillFA7.sdc. This file must not contain anything board
-- specific.
--
-- The displayed version is BOARD_ID.SW_SUB1 SW_SUB2 - first digit from variant_pkg,
-- the other two from rtl/common/version_pkg.vhd. Version history: bin/changelog.txt.
--
-- Must stay VHDL-93: the Cyclone II variant builds with Quartus 13.0sp1. In
-- particular there is no 'else generate' (VHDL-2008), and numeric_std must not be
-- added next to std_logic_unsigned - their operators would become ambiguous.
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
-- BOARD_ID: which board this build is for (variants/<name>/variant_pkg.vhd)
-- SW_SUB1/SW_SUB2: common function level of all variants (rtl/common/version_pkg.vhd)
use work.variant_pkg.all;
use work.version_pkg.all;
-- DISPLAY_T / DISPLAY_TS for the boot message data, which HAS_SOUND fills differently
use work.instruction_buffer_type.all;
-- what depends on the selected game: display type and system generation. The package
-- exports functions over std_logic_vector only, so no numeric_std comes in with it.
use work.game_pkg.all;
	
entity WillFA7 is
	port(
	   -- The FPGA board.
	   -- Pin numbers are deliberately NOT in here: they differ per board and live in
	   -- variants/<name>/pins.tcl, which is the only place they are true.
		clk_50	: in std_logic;
		reset_sw  : in std_logic; 	--goes Low on reset(push)
		LED_SD_Error 	: out STD_LOGIC;

		-- CAREFUL: these two drive an LED AND a control line. LED_active is the 'active'
		-- LED and the driver board blanking (IC13 74HCT240 /OE plus /RESET of the five
		-- 74HCT273 latches), LED_status is the 'status' LED and the display blanking.
		-- So they look like free indicators and are not: whatever you show on them, you
		-- switch on the machine at the same time. Never repurpose them for status or
		-- error indication - see docs/blanking_led_active.md.
		LED_active 	: out STD_LOGIC;
		LED_status 	: out STD_LOGIC;

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
		sw_strobe: buffer 	std_logic_vector(7 downto 0);
		sw_return: in 	std_logic_vector(7 downto 0);

		--lamps & sound/comma display SYS7 plus 'extra LED'
		lamps: buffer 	std_logic_vector(7 downto 0);
		lamp_strobe_sel: buffer std_logic; --RTH debug only, switch back to out
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

		DIP_Str_1: out std_logic;
		DIP_Str_2: out std_logic;
		DIP_Str_3: out std_logic;
		DIP_Str_4: out std_logic;

		-- Optional. Not every board has these pins, but they are declared everywhere so
		-- that all variants can share one top level. A board without the pin gets
		-- VIRTUAL_PIN in its generated .qsf, listed in variants/<name>/variant.psd1.
		-- Simply leaving an output unassigned is not an option: to Quartus it is a used
		-- pin, RESERVE_ALL_UNUSED_PINS does not cover it, and it would be placed and
		-- driven on some pin of the board.
		LED_debug	: out STD_LOGIC;	-- dev boards only, follows reset_sw
		USB_Tx: in std_logic;		-- serial monitor API, data into the FPGA
		USB_Rx: out std_logic;		-- serial monitor API, data out of the FPGA
		debug: out std_logic;		-- scope probe, driven by the serial monitor

		-- Optional as well: the integrated sound board (HAS_SOUND). Only the WillFA7S
		-- boards bring these out, and they take the pins away from the DIP strobes -
		-- which is why those boards read a fourth DIP return line instead and multiplex
		-- the strobes onto sw_strobe. See docs/soundcard_variant.md.
		SB_Sound: out std_logic;	-- audio out, delta sigma
		SB_Speech: out std_logic;	-- was the second delta sigma output, idle since .22
		SB_Test: in std_logic;		-- sound test push button, pulled up in device.tcl
		Dip_Ret_4: in std_logic		-- fourth DIP return, turns the 4x3 matrix into 4x4

		);
end;

architecture rtl of WillFA7 is

-- SD card layout. ONE format for every board since .22 - what used to be the WillFA7S
-- card is now the card. A slot is 128 sectors = 64 KByte, of which the first 12 KByte
-- are the MPU ROMs, 12..32 KByte the sound board ROMs (read by the S board only, read
-- and dropped by everyone else) and the last two bytes the expected CRC16-CCITT over
-- the first 32 KByte. Layout: docs/soundcard_variant.md section 4.
--
-- Before .22 there were three formats: 10 KByte from 5800h on Cyclone II, 12 KByte from
-- 5000h on the others, 64 KByte on WillFA7S. The first two are gone - a .21 card does
-- not boot on .22 and reports itself as a CRC error, which is the point.
constant SD_SLOT_SECTORS : integer := 128;   -- 64 KByte per game
constant SD_MPU_BYTES    : integer := 12288; -- MPU ROM payload, 6 x 2K
constant SD_CRC_BYTES    : integer := 32768; -- what the CRC on the card covers

signal cpu_clk		:  std_logic;  --894KHz for Williams
signal mem_clk		:  std_logic;  --894KHz shifted for mem access without glitches
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
signal pia1_ca2	:	std_logic;
signal pia1_cb1	:	std_logic;

-- pia2
signal pia2_dout	:	std_logic_vector(7 downto 0);
signal pia2_irq_a	:	std_logic;
signal pia2_irq_b	:	std_logic;
signal pia2_cs		:	std_logic;
signal sw_return_deb	:	std_logic_vector(7 downto 0); --debounced switch returns -> PIA2 pa_i
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
signal sp_solenoid_trig_6		:	std_logic; --option for game CONTACT
signal sp_solenoid_mpu	:	std_logic_vector(6 downto 1); --6 special solenoids from MPU (selftest)

-- diff
signal GameOn		:	std_logic;
signal gen_irq		:	std_logic;
signal blanking	:	std_logic:='1';
signal eeprom_trigger	:	std_logic:='0';
signal eeprom_wr_in_progress	:	std_logic:='1';

-- SD card
-- 16 bit since .22: the WillFA7S slot is 64 KByte. With ROM_COUNT*2048 bytes the
-- counter never leaves the lower 14 bits, so the decodes below stay unambiguous.
signal address_sd_card	:  std_logic_vector(15 downto 0);
signal data_sd_card	:  std_logic_vector(7 downto 0);
signal wr_rom			:  std_logic;
signal wr_game_rom			:  std_logic;
signal wr_system_rom			:  std_logic;
signal SDcard_MOSI	:	std_logic;
signal SDcard_CLK		:	std_logic;
signal SDcard_error	:	std_logic:='1'; --active low
-- CRC of the game data on the card. Every card carries one since .22, so unless a board
-- turns SD_CHECK_CRC off these are live signals and go on the boot display.
signal crc16			:  std_logic_vector(15 downto 0); -- computed while reading
signal crc16_r			:  std_logic_vector(15 downto 0); -- read from the end of the slot
signal crc_error		:  std_logic;

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

-- dip games select and options
signal game_select 		:  std_logic_vector(5 downto 0);				
signal game_option		: 	std_logic_vector(6 downto 1);

--displays
signal game_disp_strobe :	std_logic_vector(3 downto 0);
signal bm_disp_strobe :	std_logic_vector(3 downto 0);
signal game_disp_bcd 	:	std_logic_vector(7 downto 0);
signal bm_disp_bcd 	:	std_logic_vector(7 downto 0);
-- What actually goes out on the display pins. The ports stay 'out' in every
-- variant; readers (today only the serial monitor) take these signals instead.
signal disp_strobe_i :	std_logic_vector(3 downto 0);
signal disp_bcd_i 	:	std_logic_vector(7 downto 0);

-- boot message (bm_) helper
signal dig0					:  std_logic_vector(3 downto 0);
signal dig1					:  std_logic_vector(3 downto 0);
signal dig2					:  std_logic_vector(3 downto 0);

-- nmi
signal diag				:	std_logic; 
signal diag_stable	:	std_logic; 
signal enter_stable	:	std_logic;

-- comma & sound system7
signal comma12 	: std_logic;
signal comma34		: std_logic;
signal sound		: std_logic_vector(4 downto 0);
signal diag_LED	: std_logic;

--div
signal opt_nvram_init_n	: std_logic;
signal R_out : std_logic_vector(3 downto 0); -- receiver outputs AT28
-- trigger
--signal credit_sw			: std_logic;

signal sp_solenoid1_mpu_filtered	: std_logic;

-- the selected game, and what depends on it
-- game_no is THE game number 0..31; the DIPs are active low, so it is 'not game_select'.
-- Same number the SD card slot, the EEprom page and the debounce mask use.
signal game_no : std_logic_vector(5 downto 0);
signal is_sys3 : std_logic; -- '1' for System3/4 (game 0-8)
signal disp_7digit : std_logic; -- '1' for seven digit player displays (game 16-31)

----------------------------------------------------------------------------
-- integrated sound board (HAS_SOUND) - see docs/soundcard_variant.md
-- All of this generates away where HAS_SOUND is false; that the five boards without
-- a sound board keep their exact resource numbers is what proves it.
----------------------------------------------------------------------------
-- Only what actually has to cross a generate boundary is declared here. Everything
-- that lives entirely inside GEN_SOUND is declared inside it, so it does not exist
-- at all on a board without a sound card - which keeps the expected warning list in
-- CLAUDE.md short enough to still be worth reading.

-- what PIA2 puts out; on a sound board the DIP strobes borrow four of these lines
-- during boot phase 1, everywhere else it goes straight to the sw_strobe pins
signal game_sw_strobe	: std_logic_vector(7 downto 0);

-- the four extra DIP bits the 4x4 matrix delivers: driven in GEN_DIPS_SOUND,
-- read in GEN_SOUND
signal sb_option		: std_logic_vector(1 to 4);

-- sound test takes over the display and blocks the diagnostic NMI while it runs
signal soundtest_active	: std_logic;
signal sbtest_disp_strobe	: std_logic_vector(3 downto 0);
signal sbtest_disp_bcd		: std_logic_vector(7 downto 0);

-- The sound commands as they leave the MPU. Without a sound board this is just 'sound';
-- with one it is the selected source (SYS3/SYS7/sound test), and it goes to BOTH the
-- internal sound board and the sound/comma latch, i.e. the connector for an external
-- one. That is how 6.03 had it and it is kept on purpose.
signal sound_com		: std_logic_vector(4 downto 0);

-- driven in GEN_SOUND, read by the boot message data in GEN_DIPS_SOUND
signal sbo_dig0			: std_logic_vector(3 downto 0);
signal sbo_dig1			: std_logic_vector(3 downto 0);
-- driven for every board, read by the boot message data in GEN_CRC_DISP
signal crc_dig			: std_logic_vector(3 downto 0); -- 7 on the error display when the CRC is wrong

-- gated versions, so the sound test does not fight the diagnostics
signal diag_nmi_in		: std_logic;
signal cfg_enable		: std_logic;

-- boot message data that HAS_SOUND fills differently (CRC instead of the date)
signal bm_display3		: DISPLAY_T;
signal bm_display4		: DISPLAY_T;
signal bm_error_disp4	: DISPLAY_T;
signal bm_status_d		: DISPLAY_TS;

-- SW version comes from the two packages, see the use clauses at the top.

begin

--debug port pin64 on board -> pin_84 in config for cyclone IV
-- nmi address ( vector fff8 & fff9 )
--debug <= '1' when cpu_addr = x"7053" and rom4_cs = '1' else '0';
--debug <= '1' when cpu_addr = x"FFFC" else '0'; --NMI

LED_status <= not boot_phase(0); -- 'status' LED and the display blanking, same line
LED_sd_Error <=  SDcard_error;
-- CAREFUL: LED_active drives the 'active' LED, but not only that - the same pin is the
-- driver board blanking line:
--   -> IC13 74HCT240 /OE (switch strobes)
--   -> T9 -> blanking_n -> /RESET of IC3,4,5 (solenoid latches) and IC6,7 (lamp latches)
-- A '1' clears every solenoid and lamp latch and blocks the switch strobes. The LED is
-- what makes this pin look free; it is not. It must carry 'blanking' and nothing else -
-- never repurpose it for status or error indication. That was the .17 to .19 regression,
-- see docs/blanking_led_active.md.
LED_active <= blanking;

-- dev boards only; on every other board this is a virtual pin
LED_debug <= reset_sw;

opt_nvram_init_n <= game_option(1); -- 0 if option Dip1 is set

-- The game number and the two properties derived from it, see rtl/common/game_pkg.vhd.
-- CAREFUL with the polarity: until .22 this read
--     is_sys3 <= '1' when game_select <= "001000" else '0';
-- which compares the RAW DIP value instead of the game number. Game 0..8 have
-- game_select 63..55, so that was never true for any game that exists - is_sys3 was
-- stuck at '0' and 'Fix 3' of docs/CHANGES_v3.16.md never took effect. The comment
-- there asked for exactly this check.
game_no <= not game_select;
is_sys3 <= is_system3(game_no);
disp_7digit <= has_7digit(game_no);
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
   i_D => reset_sw,
	o_Q => boot_phase(0),
   i_Fast_Clk => clk_50
	); 

-- display bm switch, switch to game in boot phase 3.
-- soundtest_active is a hard constant '0' without a sound board, so this collapses
-- back to the two way switch there.
disp_bcd_i <= sbtest_disp_bcd when soundtest_active = '1' else
              bm_disp_bcd when boot_phase(3) = '0' else game_disp_bcd;
disp_strobe_i <= sbtest_disp_strobe when soundtest_active = '1' else
                 bm_disp_strobe when boot_phase(3) = '0' else game_disp_strobe;
disp_bcd <= disp_bcd_i;
disp_strobe <= disp_strobe_i;

BM: entity work.boot_message
port map(
	clk		=> clk_50, 	
	-- Control/Data Signals,
   show  => boot_phase(0),    
	--show error
	is_error => SDcard_error, --active low
	-- six or seven digit player displays, decided by the game number
	seven_digit => disp_7digit,
	-- output
	strobe	=> bm_disp_strobe,
	bcd	=> bm_disp_bcd,
	-- input (display data)
	display1	=> ( x"F",x"F",x"F",BOARD_ID,SW_SUB1,SW_SUB2 ),
	display2	=> ( x"F",x"F",x"F", x"0", g_dig1, g_dig0),
	-- displays 3 and 4 differ with a sound board: they show the two CRCs of the game
	-- data instead of the build date. Driven by the generates further down - the
	-- instance itself must stay outside any generate, its label is a node name.
	display3	=> bm_display3,
	display4	=> bm_display4,
	error_disp4 => bm_error_disp4,
	status_d	=> bm_status_d
	);

----------------------------------------------------------------------------
-- reading the DIPs, and what the boot message shows
--
-- Without a sound board this is a 4x3 matrix on four dedicated strobe pins, read
-- continuously. With one, those pins carry SB_Sound/SB_Speech/SB_Test instead, so
-- the strobes borrow sw_strobe(7,5,3,1) during boot phase 1 and a fourth return line
-- is read - a 4x4 matrix, and it is read exactly once because continuing would
-- disturb the switch matrix once the game runs. Details and bit map:
-- docs/soundcard_variant.md.
--
-- Two complementary if-generate, not if/else generate: else generate is VHDL-2008
-- and Cyclone II builds with Quartus 13.0sp1, which does not know it.
----------------------------------------------------------------------------
GEN_DIPS_PLAIN: if not HAS_SOUND generate
	RDIPS: entity work.read_the_dips
	port map(
		clk_in		=> cpu_clk,
		i_Rst_L  => boot_phase(0),
		--output
		game_select	=> game_select,
		game_option	=> game_option,
		-- strobes
		dipstrobe1 => DIP_Str_1,
		dipstrobe2 => DIP_Str_2,
		dipstrobe3 => DIP_Str_3,
		dipstrobe4 => DIP_Str_4,
		-- input
		return1 => Dip_Ret_1,
		return2 => Dip_Ret_2,
		return3 => Dip_Ret_3,
		-- signal when finished
		done	=> boot_phase(1) -- set to '1' when reading dips is done
		);

	-- the switch strobes are PIA2's alone here
	sw_strobe <= game_sw_strobe;

	bm_status_d <= ( x"F",x"F",o_dig0, o_dig1 );
end generate;

GEN_DIPS_SOUND: if HAS_SOUND generate
	signal dipstrobe : std_logic_vector(3 downto 0);
begin
	RDIPS_S: entity work.read_the_dips_s
	port map(
		clk_in		=> cpu_clk,
		i_Rst_L  => boot_phase(0),
		--output
		game_select	=> game_select,
		game_option	=> game_option,
		sb_option	=> sb_option,
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

	-- switch strobes controlled by the game from boot phase 1 on; before that the
	-- odd ones carry the DIP strobes
	sw_strobe(7) <= game_sw_strobe(7) when boot_phase(1) = '1' else dipstrobe(0);
	sw_strobe(6) <= game_sw_strobe(6);
	sw_strobe(5) <= game_sw_strobe(5) when boot_phase(1) = '1' else dipstrobe(1);
	sw_strobe(4) <= game_sw_strobe(4);
	sw_strobe(3) <= game_sw_strobe(3) when boot_phase(1) = '1' else dipstrobe(2);
	sw_strobe(2) <= game_sw_strobe(2);
	sw_strobe(1) <= game_sw_strobe(1) when boot_phase(1) = '1' else dipstrobe(3);
	sw_strobe(0) <= game_sw_strobe(0);

	-- The dedicated strobe pins do not exist on this board (VIRTUAL_PIN), but an
	-- output port still needs a driver.
	DIP_Str_1 <= dipstrobe(0);
	DIP_Str_2 <= dipstrobe(1);
	DIP_Str_3 <= dipstrobe(2);
	DIP_Str_4 <= dipstrobe(3);

	-- The sound board DIPs join the status display. On the board the sound board options
	-- end up on the LEFT pair of digits, the game options on the right - boot_message
	-- puts status_d(0)/(1) on the strobes 15/14 and status_d(2)/(3) on 7/6, and 14/15 is
	-- the left pair. Tens before ones within each pair.
	bm_status_d    <= ( sbo_dig0, sbo_dig1, o_dig0, o_dig1 );
end generate;

----------------------------------------------------------------------------
-- displays 3 and 4 of the boot message
--
-- With the CRC check on they carry the two checksums of the game data, which is
-- what makes a bad card readable off the display instead of only blinkable on the
-- LED. Without it they keep the build date - showing 0000/0000 would pretend a
-- comparison that never happened.
--
-- Two complementary if-generate, not if/else generate: else generate is VHDL-2008
-- and Cyclone II builds with Quartus 13.0sp1, which does not know it.
----------------------------------------------------------------------------
GEN_CRC_DISP: if SD_CHECK_CRC generate
	bm_display3    <= ( x"F",x"F", crc16(15 downto 12), crc16(11 downto 8), crc16(7 downto 4), crc16(3 downto 0));
	bm_display4    <= ( x"F",x"F", crc16_r(15 downto 12), crc16_r(11 downto 8), crc16_r(7 downto 4), crc16_r(3 downto 0));
	bm_error_disp4 <= ( crc_dig, x"5",x"6",x"F", b_dig1, b_dig0);
end generate;

GEN_CRC_DISP_OFF: if not SD_CHECK_CRC generate
	-- build date and boot phase, the boot message as it was before .22
	bm_display3    <= ( x"0",x"5",x"0",x"9",x"6",x"3" );
	bm_display4    <= ( x"F",x"F",x"F",x"F",b_dig1, b_dig0);
	bm_error_disp4 <= ( x"F",x"5",x"6",x"F",b_dig1, b_dig0);
end generate;

-- 7 in the leading digit of the error display means the game data on the card did not
-- match its CRC, see rtl/common/SD_Card.vhd (blink code 7 on LED_SD_Error). Without
-- Check_CRC crc_error is a constant '0' and this costs nothing.
crc_dig <= x"7" when crc_error = '1' else x"F";

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
generic map(
	-- Read_Bytes only decides where the read stops WITHOUT a CRC check - with one the
	-- read runs to the end of the slot anyway, because that is where the expected
	-- checksum sits. So this is the MPU payload, not ROM_COUNT*2048: a five ROM board
	-- still has to read past its own blocks, it just drops the first 2K window.
	Read_Bytes   => SD_MPU_BYTES,
	Slot_Sectors => SD_SLOT_SECTORS,
	Check_CRC    => SD_CHECK_CRC,   -- per board, see variant_pkg.vhd
	CRC_Bytes    => SD_CRC_BYTES
)
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
	selection => "00" & game_no,
	--selection => not game_select,
	-- data
	address_sd_card => address_sd_card,
	data_sd_card => data_sd_card,
	wr_rom => wr_rom,
	-- feedback
	SDcard_error => SDcard_error,
	-- CRC of the game data; both sums go on the boot display, see below
	calc_checksum => crc16,
	read_checksum => crc16_r,
	crc_error => crc_error,
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
	selection => "00" & game_no,
	-- write trigger
	w_trigger(4) => enter_stable, -- for save within setup sys3
	w_trigger(3) => GameOn, --game_over_relay,
	w_trigger(2) => eeprom_trigger, -- intial write via ctrl_blanking 5sec after start RTH
	w_trigger(1) => advance,-- for save within setup menue
	w_trigger(0) => game_option(5), -- as trigger for testing
	-- init trigger (no read, RAM will be zero)
	i_init_Flag => opt_nvram_init_n, -- 0 if option Dip1 is set 
	-- signal when finished
		-- signal when finished
	done	=> boot_phase(3), -- set to '1' when first read of eeprom and write to cmos is done
	o_wr_in_progress => eeprom_wr_in_progress,
	-- left open on purpose: the 1 Hz blink used to be routed to LED_active, but that
	-- pin is the blanking line (see docs/blanking_led_active.md)
	EEprom_error => open
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
-- sys3..4: direct connection
-- sys6..7: use IRQ with OR
--pia1_ca1 <= advance when is_sys3 = '1'
--            else not ( not advance or not cpu_irq);
--pia1_cb1 <= up_down when is_sys3 = '1'
--            else not ( not up_down or not cpu_irq);

pia1_ca1 <= not ( not advance or not cpu_irq);
pia1_cb1 <= not ( not up_down or not cpu_irq);				

--NMI
DIAGSTABLE: entity work.Cross_Slow_To_Fast_Clock
port map(
   i_D => not Diag_SW,
	o_Q => diag_stable,
   i_Fast_Clk => cpu_clk
	);

ENTERSTABLE: entity work.Cross_Slow_To_Fast_Clock
port map(
   i_D => ENTER_SW,
	o_Q => enter_stable,
   i_Fast_Clk => cpu_clk
	);
	
-- While the sound test runs, Diag_SW steps through the sound numbers - it must not
-- fire the diagnostic NMI at the same time. soundtest_active is a hard constant '0'
-- without a sound board, so this is a plain wire there.
diag_nmi_in <= diag_stable and not soundtest_active;

DIAGSW: entity work.one_pulse_only
port map(
   sig_in => diag_nmi_in,
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

----------------------
-- sound
----------------------
-- the SYS6/7 source. What actually leaves the board is sound_com, which equals this
-- unless a sound card is fitted - see the generates at the end of the file.
sound <= pia5_pa_o(4 downto 0);

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
-- One card format for every board since .22, so the six 2K windows of the image are
-- the same everywhere: window 0 -> rom0 (5000h) ... window 5 -> rom5 (7800h). A five
-- ROM board simply has no rom0 and lets window 0 go past unwritten - it does NOT
-- shift the others down, which is exactly what the old 10 KByte image did.
-- Slot layout: docs/soundcard_variant.md section 4.
rom1_cs   <= '1' when cpu_addr(14 downto 11) = "1011" and cpu_vma='1' else '0'; --5800-5FFF
rom2_cs   <= '1' when cpu_addr(14 downto 11) = "1100" and cpu_vma='1' else '0'; --6000-67FF
rom3_cs   <= '1' when cpu_addr(14 downto 11) = "1101" and cpu_vma='1' else '0'; --6800-6FFF
rom4_cs   <= '1' when cpu_addr(14 downto 11) = "1110" and cpu_vma='1' else '0'; --7000-77FF
rom5_cs   <= '1' when cpu_addr(14 downto 11) = "1111" and cpu_vma='1' else '0'; --7800-7FFF

------------------
-- ROMs ----------
-- moved to RAM, initial read from SD
-- one file per game for all Williams variants, mapping is done inside that file
-- address selection: read from SD when wr_rom == 1, else map to address room
--
-- The five windows every board has. Check these line by line against the slot layout,
-- not from memory - a window off by one loads the game one 2K block skewed and the
-- symptom is a game that boots into nonsense, not a build error.
wr_rom1 <= '1' when address_sd_card(15 downto 11) = "00001" and wr_rom='1' else '0'; --sec 2K   5800h
wr_rom2 <= '1' when address_sd_card(15 downto 11) = "00010" and wr_rom='1' else '0'; --third 2K 6000h
wr_rom3 <= '1' when address_sd_card(15 downto 11) = "00011" and wr_rom='1' else '0'; --fourth 2K 6800h
wr_rom4 <= '1' when address_sd_card(15 downto 11) = "00100" and wr_rom='1' else '0'; --fift 2K  7000h
wr_rom5 <= '1' when address_sd_card(15 downto 11) = "00101" and wr_rom='1' else '0'; --sixt 2K  7800h

-- Only rom0 is board dependent. Two complementary if-generate, not if/else generate:
-- else generate is VHDL-2008 and Cyclone II builds with Quartus 13.0sp1.
GEN_ROM0: if ROM_COUNT = 6 generate
	rom0_cs <= '1' when cpu_addr(14 downto 11) = "1010" and cpu_vma='1' else '0'; --5000-57FF
	wr_rom0 <= '1' when address_sd_card(15 downto 11) = "00000" and wr_rom='1' else '0'; --first 2K 5000h
end generate;

GEN_ROM0_OFF: if ROM_COUNT /= 6 generate
	-- No rom0 block on this board: window 0 of the image is read and dropped, and
	-- 5000-57FF reads FF through the cpu_din mux below. Games that need the full
	-- 12 KByte (Defender, Star Light) therefore do not run here - that is a property
	-- of the board, not of the card.
	rom0_cs   <= '0';
	wr_rom0   <= '0';
	rom0_dout <= x"FF";	-- must be driven: with ROM_0 gone it would have no source at all
end generate;

rom_address <=
  address_sd_card(10 downto 0) when wr_rom = '1' else
  cpu_addr(10 downto 0);	

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
mem_prot_active <= mem_prot_ram_cs and mem_prot and opt_nvram_init_n and not is_sys3;
--mem_prot active high due to inverter on WillFA7; disabled for System3/4 (no coin door protection)


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
	ca2_o => pia1_ca2,
	pb_i => x"FF",
	pb_o => game_disp_bcd,
	cb1 => pia1_cb1,
	cb2_i => '1',
	cb2_o => sp_solenoid_mpu(6),
	default_pb_level => '0'  -- output level when configured as input
);

-- Hardware debouncer for the switch matrix (sw_return)
-- matrix-aware, per-switch charge integrator with hysteresis (digital RC), incl. 2-FF sync
-- The per-switch mask inside the module leaves level/confirm-read switches (drop-target
-- banks, outhole/trough, eject holes, kickers, locks, ramps), spinners and jets RAW;
-- only momentary switches (stand-ups, rollovers, lanes, cabinet) are debounced.
-- Since .20 the mask is selected by game number, so every supported game gets its own
-- table. See docs/switch_debounce_analysis.md and docs/switch_masks.md.
-- inline between the sw_return pins and PIA2 pa_i
SWDEB: entity work.sw_debounce
generic map(
	INTEG_MAX     => 4,   -- state change ~8ms (2ms/scan); raise to 5 if hard hits double, lower to 3 if fast hits missed
	SETTLE_CYCLES => 4
)
port map(
	clk           => cpu_clk,
	i_Rst_L       => reset_l,
	enable        => not game_option(5),  -- option DIP5 ON (game_option(5)='0') -> debounce; OFF -> raw .17 passthrough
	game          => game_no,  -- game number 0..31, same as 'selection' at SD_Card/EEprom
	sw_strobe     => sw_strobe,        -- one-hot column select (buffer port, readable)
	sw_return_raw => sw_return,        -- raw returns from the pins
	sw_return_deb => sw_return_deb
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
	pa_i => sw_return_deb,
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
-- NOT straight to the sw_strobe pins: on a sound board the DIP strobes borrow four
-- of these lines during boot phase 1. See GEN_DIPS_PLAIN / GEN_DIPS_SOUND above.
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
	c0 => clk_14
	);
	
clock_gen: entity work.cpu_clk_gen
port map(   
	clk_in => clk_14,
	clk_out	=> cpu_clk,
	shift_clk_out	=> mem_clk
);


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
		--clock			=> clk_50,
		clock_a   => mem_clk,   -- CPU-seitig: glitch-sicher
      clock_b   => clk_50,    -- EEPROM-seitig: schneller Takt		
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
	clock => mem_clk, --without glitches
	data		=>  cpu_dout (7 DOWNTO 0),
	wren 		=> ram_wren,
	q			=> ram_dout
);	

----------------------
-- SYS3 & 4 config switches
----------------------
-- Enter_SW reads the SYS3/4 configuration DIPs into PIA1 - except while the sound
-- test runs, where the same button plays the selected sound. Constant '0' for
-- soundtest_active without a sound board, so this stays 'not enter_stable' there.
cfg_enable <= (not enter_stable) and (not soundtest_active);

CFG: entity work.AM8T28
port map (

       D_in => W_PA_DIP, -- Driver inputs
		  
       B_out => pia1_pa_i(7 downto 4),-- receiver outputs		  
       B_in => pia1_pa_o(7 downto 4),-- receiver inputs 

       R_out => R_out, -- receiver outputs 

       B_E  => cfg_enable, --active high (on WillFA7 signal is '0' wenn pushed -> switch with internal pullup)
       R_E  => not pia1_ca2  -- active low, accent inverter in Williams SYS3 schematic
    );
	 
-- BT28 IC Bus Driver Receiver
pia1_pa_i(3 downto 0) <= "1111";
--pia1_pa_i(7 downto 4) <= W_PA_DIP when Enter_stable = '0' else x"F"; -- enter SW activates input
--Diag_LED <= not pia1_pa_o(5) when opt_nvram_init_n = '1' else eeprom_wr_in_progress; -- to show when eeprom has saved
Diag_LED <= not R_out(0); -- when opt_nvram_init_n = '1' else eeprom_wr_in_progress; -- to show when eeprom has saved

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
--debug <= sp_solenoid1_mpu_filtered; --not sp_solenoid_mpu(1); --RTH test
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
   i_Fast_Clk => cpu_clk
	); 
SPECIAL1: entity work.spec_sol_trigger
port map(
   clk_in => cpu_clk,
	i_Rst_L => reset_l,
   trigger => SPC_Sol_Trig_stable(1),
	pulse_cfg => game_option(3 downto 2),
	long_debounce => not game_option(4), -- DIP4 ON -> long debounce, OFF -> .18 behaviour
	solenoid => sp_solenoid_trig(1)
	); 
META_SPECIAL2: entity work.Cross_Slow_To_Fast_Clock
port map(
   i_D => SPC_Sol_Trig(2),
	o_Q => SPC_Sol_Trig_stable(2),
   i_Fast_Clk => cpu_clk
	); 	
SPECIAL2: entity work.spec_sol_trigger
port map(
   clk_in => cpu_clk,
	i_Rst_L => reset_l,
   trigger => SPC_Sol_Trig_stable(2),
	pulse_cfg => game_option(3 downto 2),
	long_debounce => not game_option(4), -- DIP4 ON -> long debounce, OFF -> .18 behaviour
	solenoid => sp_solenoid_trig(2)
	); 
META_SPECIAL3: entity work.Cross_Slow_To_Fast_Clock
port map(
   i_D => SPC_Sol_Trig(3),
	o_Q => SPC_Sol_Trig_stable(3),
   i_Fast_Clk => cpu_clk
	); 	
SPECIAL3: entity work.spec_sol_trigger
port map(
   clk_in => cpu_clk,
	i_Rst_L => reset_l,
   trigger => SPC_Sol_Trig_stable(3),
	pulse_cfg => game_option(3 downto 2),
	long_debounce => not game_option(4), -- DIP4 ON -> long debounce, OFF -> .18 behaviour
	solenoid => sp_solenoid_trig(3)
	); 
META_SPECIAL4: entity work.Cross_Slow_To_Fast_Clock
port map(
   i_D => SPC_Sol_Trig(4),
	o_Q => SPC_Sol_Trig_stable(4),
   i_Fast_Clk => cpu_clk
	); 	
SPECIAL4: entity work.spec_sol_trigger
port map(
   clk_in => cpu_clk,
	i_Rst_L => reset_l,
   trigger => SPC_Sol_Trig_stable(4),
	pulse_cfg => game_option(3 downto 2),
	long_debounce => not game_option(4), -- DIP4 ON -> long debounce, OFF -> .18 behaviour
	solenoid => sp_solenoid_trig(4)
	); 
META_SPECIAL5: entity work.Cross_Slow_To_Fast_Clock
port map(
   i_D => SPC_Sol_Trig(5),
	o_Q => SPC_Sol_Trig_stable(5),
   i_Fast_Clk => cpu_clk
	); 	
SPECIAL5: entity work.spec_sol_trigger
port map(
   clk_in => cpu_clk,
	i_Rst_L => reset_l,
   trigger => SPC_Sol_Trig_stable(5),
	pulse_cfg => game_option(3 downto 2),
	long_debounce => not game_option(4), -- DIP4 ON -> long debounce, OFF -> .18 behaviour
	solenoid => sp_solenoid_trig(5)
	); 	
META_SPECIAL6: entity work.Cross_Slow_To_Fast_Clock
port map(
   i_D => SPC_Sol_Trig(6),
	o_Q => SPC_Sol_Trig_stable(6),
   i_Fast_Clk => cpu_clk
	); 	
-- For Game CONTACT no protection on spec. sol 6 as permanent
-- special solenoïd is SOL22 (moving target relay) pin 9 on 2P12	
-- active with option dip 6 to ON
sp_solenoid_trig(6) <= SPC_Sol_Trig_stable(6) when game_option(6) = '0' else sp_solenoid_trig_6;
SPECIAL6: entity work.spec_sol_trigger
port map(
   clk_in => cpu_clk,
	i_Rst_L => reset_l,
   trigger => SPC_Sol_Trig_stable(6),
	pulse_cfg => game_option(3 downto 2),
	long_debounce => not game_option(4), -- DIP4 ON -> long debounce, OFF -> .18 behaviour
	solenoid => sp_solenoid_trig_6
	); 
	
----------------
--roms
----------------
GEN_ROM0_INST: if ROM_COUNT = 6 generate
	-- 2K area 5000h-57ffh
	ROM_0: entity work.rom_2K
	port map(
		address => rom_address,	
		clock => clk_50,
		data => data_sd_card,
		wren => wr_rom0,
		q	=> rom0_dout
		);
end generate;

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

----------------------------------------------------------------------------
-- serial monitor API (option 'serial_api')
-- Only the v3 board brings the USB pins out. The module is worth about 550 logic
-- elements, which is more than the EP2C5 of the Cyclone II board has left, so it
-- has to generate away rather than be optimised away.
--
-- Two complementary if-generate, not if/else generate: else generate is VHDL-2008
-- and Cyclone II builds with Quartus 13.0sp1, which does not know it.
----------------------------------------------------------------------------
GEN_MONITOR: if HAS_MONITOR generate
	monitor: entity work.willfa7_monitor
	port map(
		clk => clk_50,
		rst => reset_l,
		txd => USB_Rx,
		rxd => USB_Tx,
		disp_bcd => disp_bcd_i,
		disp_strobe => disp_strobe_i,
		debug => debug
	);
end generate;

GEN_NO_MONITOR: if not HAS_MONITOR generate
	-- Both are virtual pins on these boards, but an output port still needs a
	-- driver - otherwise Quartus ties it to GND without saying so.
	USB_Rx <= '1';	-- UART idle level
	debug  <= '0';
end generate;

----------------------------------------------------------------------------
-- integrated sound board (option 'sound')
-- Only the WillFA7S boards have one. Everything about it is collected in
-- docs/soundcard_variant.md - read that before touching anything in here.
--
-- Two complementary if-generate, not if/else generate: else generate is VHDL-2008
-- and Cyclone II builds with Quartus 13.0sp1, which does not know it.
----------------------------------------------------------------------------
GEN_NO_SOUND: if not HAS_SOUND generate
	-- Virtual pins on these boards, but an output port still needs a driver -
	-- same trap as USB_Rx/debug above.
	SB_Sound  <= '0';
	SB_Speech <= '0';

	-- Constants, so everything that reads them collapses: the display switch, the
	-- NMI gate, the config gate. Nothing of the sound board survives here, which the
	-- baseline check confirms - the five boards without one keep their exact numbers.
	-- sb_option and sbo_dig0/1 are deliberately left undriven: nothing reads them here
	-- either, so giving them a value would only add a 'never read' warning. crc_dig is
	-- NOT one of them - it is driven for every board since .22, see GEN_CRC_DISP.
	soundtest_active   <= '0';
	sbtest_disp_strobe <= (others => '0');
	sbtest_disp_bcd    <= (others => '0');
	sound_com          <= sound;	-- nothing to select from, so a plain wire
end generate;

GEN_SOUND: if HAS_SOUND generate
	-- sound board ROMs, 4K each, filled from SD between 12K and 32K
	signal sb_address		: std_logic_vector(11 downto 0);
	signal sbrom_address	: std_logic_vector(11 downto 0);
	signal sbrom1_dout	: std_logic_vector(7 downto 0);
	signal sbrom2_dout	: std_logic_vector(7 downto 0);
	signal sbrom3_dout	: std_logic_vector(7 downto 0);
	signal sbrom4_dout	: std_logic_vector(7 downto 0);
	signal sbrom5_dout	: std_logic_vector(7 downto 0);
	signal wr_sbrom1		: std_logic;
	signal wr_sbrom2		: std_logic;
	signal wr_sbrom3		: std_logic;
	signal wr_sbrom4		: std_logic;
	signal wr_sbrom5		: std_logic;

	-- what actually reaches the sound board, and where it comes from
	signal sound_sys3		: std_logic_vector(4 downto 0); -- solenoids 9..13, SYS3/4
	signal sound_test		: std_logic_vector(4 downto 0); -- from the sound test
begin
	----------------------------------------------------------------------------
	-- SD card windows for the sound board ROMs
	-- 0..12K are the MPU ROMs (decoded further up), 12K..32K the five sound board
	-- ROM blocks. Everything above is padding plus the CRC. docs/soundcard_variant.md
	----------------------------------------------------------------------------
	wr_sbrom1 <= '1' when address_sd_card(15 downto 12) = "0011" and wr_rom='1' else '0'; --12..16 k
	wr_sbrom2 <= '1' when address_sd_card(15 downto 12) = "0100" and wr_rom='1' else '0'; --16..20 k
	wr_sbrom3 <= '1' when address_sd_card(15 downto 12) = "0101" and wr_rom='1' else '0'; --20..24 k
	wr_sbrom4 <= '1' when address_sd_card(15 downto 12) = "0110" and wr_rom='1' else '0'; --24..28 k
	wr_sbrom5 <= '1' when address_sd_card(15 downto 12) = "0111" and wr_rom='1' else '0'; --28..32 k

	-- filled from SD while booting, read by the sound board CPU afterwards
	sbrom_address <= address_sd_card(11 downto 0) when wr_rom = '1' else sb_address;

	-- 4K area 3000h-3fffh (IC7 on a real board)
	SB_ROM_1: entity work.SB_ROM
	port map( address => sbrom_address, clock => clk_50, data => data_sd_card,
	          wren => wr_sbrom1, q => sbrom1_dout );
	-- 4K area 4000h-4fffh (IC5)
	SB_ROM_2: entity work.SB_ROM
	port map( address => sbrom_address, clock => clk_50, data => data_sd_card,
	          wren => wr_sbrom2, q => sbrom2_dout );
	-- 4K area 5000h-5fffh (IC6)
	SB_ROM_3: entity work.SB_ROM
	port map( address => sbrom_address, clock => clk_50, data => data_sd_card,
	          wren => wr_sbrom3, q => sbrom3_dout );
	-- 4K area 6000h-6fffh (IC4)
	SB_ROM_4: entity work.SB_ROM
	port map( address => sbrom_address, clock => clk_50, data => data_sd_card,
	          wren => wr_sbrom4, q => sbrom4_dout );
	-- 4K area 7000h-7fffh (IC12, doubled on a real board)
	SB_ROM_5: entity work.SB_ROM
	port map( address => sbrom_address, clock => clk_50, data => data_sd_card,
	          wren => wr_sbrom5, q => sbrom5_dout );

	----------------------------------------------------------------------------
	-- where the five sound command lines come from
	-- SYS6/7 drive them from PIA5 port A, SYS3/4 from solenoids 9..13. Until 6.03
	-- that was the DIP sb_option(3); since 6.21 it follows is_sys3, the same source
	-- of truth the memory protect has used since .20.
	----------------------------------------------------------------------------
	sound_sys3 <= not pia4_pb_o(4 downto 0);
	sound_com  <= sound_test when soundtest_active = '1' else
	              sound_sys3 when is_sys3 = '1' else
	              sound;

	-- Sound and speech are mixed inside the sound board since .22 and leave it together
	-- on SB_Sound - on this board only that pin reaches the amplifier. SB_Speech stays
	-- pinned but idle; an output port always needs a driver. See F4/F5 in
	-- docs/soundcard_variant.md.
	SB_Speech <= '0';

	SOUNDBOARD: entity work.WISOF
	port map(
		clk_50	=> clk_50,
		cpu_clk	=> cpu_clk,
		reset_l	=> reset_l,
		test	=> not(not SB_Test and sb_option(4)),
		sound_o	=> SB_Sound,

		Sound => sound_com,

		-- SB_Opt is declared (4 downto 1) in WISOF, sb_option here is (1 to 4). A whole
		-- array association would match them by position, not by index name, and mirror
		-- the four DIPs - chimes would end up on Dip4. Element by element instead, so the
		-- mapping is the one docs/soundcard_variant.md describes.
		SB_Opt(1) => sb_option(1),
		SB_Opt(2) => sb_option(2),
		SB_Opt(3) => sb_option(3),
		SB_Opt(4) => sb_option(4),

		rom1_dout => sbrom1_dout,
		rom2_dout => sbrom2_dout,
		rom3_dout => sbrom3_dout,
		rom4_dout => sbrom4_dout,
		rom5_dout => sbrom5_dout,

		sb_address	=> sb_address
	);

	----------------------------------------------------------------------------
	-- sound test: SB_Test starts it, Diag_SW steps, Enter_SW plays. Takes over the
	-- display; the NMI and the SYS3 config read are gated off while it runs.
	----------------------------------------------------------------------------
	SOUNDTST: entity work.soundtest
	port map(
		clk_in	=> clk_50,
		i_Rst_L	=> reset_l,
		activate	=> not SB_Test and not sb_option(4),
		step	=> Diag_SW,
		play	=> Enter_SW,
		seven_digit => disp_7digit,
		soundtoplay => sound_test,
		is_active => soundtest_active,
		strobe => sbtest_disp_strobe,
		bcd => sbtest_disp_bcd
	);

	-- sound board DIPs for the status display. Dip1 is the least significant bit, the
	-- same convention S1 (game select) and S2 (game options) use - hence the explicit
	-- order: sb_option is (1 to 4), so plain concatenation would weight Dip1 with 8.
	CONVSBO: entity work.byte_to_decimal
	port map(
		clk_in	=> clk_50,
		mybyte	=> "1111" & sb_option(4) & sb_option(3) & sb_option(2) & sb_option(1),
		dig0 => sbo_dig0,
		dig1 => sbo_dig1,
		dig2 => open
		);
end generate;

end rtl;