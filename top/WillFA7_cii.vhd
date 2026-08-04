-- WillFA7_cii - board shell for the Cyclone II variant
-- Ralf Thelen 'bontango' - www.lisy.dev
--
-- WHY THIS FILE EXISTS
--
-- top/WillFA7.vhd declares the optional ports (LED_debug, USB_Tx, USB_Rx, debug,
-- SB_Sound, SB_Speech, SB_Test, Dip_Ret_4) on every board so that all variants can
-- share one top level. Boards without those pins are supposed to mark them
-- VIRTUAL_PIN in their generated .qsf.
--
-- That works on Quartus 22.1std, but NOT on the Quartus II 13.0sp1 Web Edition that
-- the Cyclone II variant has to be built with:
--
--   Warning (292013): Feature Virtual IO is only available with a valid
--   subscription license.
--
-- The assignment is accepted and then silently ignored - 'Total virtual pins: 0' in
-- the fitter report. In the released 1.21 the four optional ports of that time were
-- therefore placed on real pins of the EP2C5, picked by the fitter, three of them
-- driven outputs at 24 mA: LED_debug on PIN_26, debug on PIN_27, USB_Rx on PIN_73,
-- USB_Tx on PIN_80. With the four sound ports on top the design does not fit at all
-- any more - 90 pins wanted, 89 available.
--
-- This shell solves both: it declares only the 82 ports the board really has, so the
-- optional ones become plain internal signals of the instance below and disappear.
-- Cyclone II goes from 86 back to 82 pins.
--
-- KEEP IN SYNC. This entity is part of every variant's file list, not only of the
-- Cyclone II one, so that a port added to WillFA7 and forgotten here breaks every
-- build loudly instead of breaking Cyclone II silently. Nothing is synthesised from
-- it where it is not the top level entity.
--
-- Which entity is the top level is set per variant in variants/<name>/variant.psd1
-- (key TopEntity, default WillFA7) and lands in the generated .qsf.
--
-- CAREFUL: this extra level of hierarchy renames every node below it. The Cyclone II
-- WillFA7.sdc therefore addresses cpu_clk_gen and the PLL as 'WillFA7:CORE|...'.
-- A constraint that no longer matches is dropped silently - the check is that the
-- worst case slack stays where scripts/baseline.csv says it is.
--
-- Must stay VHDL-93, same as the top level.
library ieee;
use ieee.std_logic_1164.all;

entity WillFA7_cii is
	port(
		-- Exactly the ports that exist on the Cyclone II board. Pin locations live in
		-- variants/cyclone_ii/pins.tcl.
		clk_50	: in std_logic;
		reset_sw  : in std_logic; 	--goes Low on reset(push)
		LED_SD_Error 	: out STD_LOGIC;

		-- CAREFUL: LED and control line on the same pin. LED_active also is the driver
		-- board blanking, LED_status also the display blanking - never repurpose them,
		-- see docs/blanking_led_active.md.
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
		lamp_strobe_sel: buffer std_logic;
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
		DIP_Str_4: out std_logic
		);
end;

architecture rtl of WillFA7_cii is
begin

-- The instance label CORE is part of the node names the .sdc addresses. Do not
-- rename it without editing variants/cyclone_ii/WillFA7.sdc in the same commit.
CORE: entity work.WillFA7
port map(
	clk_50			=> clk_50,
	reset_sw		=> reset_sw,
	LED_SD_Error	=> LED_SD_Error,
	LED_active		=> LED_active,
	LED_status		=> LED_status,

	CS_SDcard		=> CS_SDcard,
	CS_EEprom		=> CS_EEprom,
	MOSI			=> MOSI,
	MISO			=> MISO,
	SPI_CLK			=> SPI_CLK,

	disp_strobe		=> disp_strobe,
	disp_bcd		=> disp_bcd,

	sw_strobe		=> sw_strobe,
	sw_return		=> sw_return,

	lamps			=> lamps,
	lamp_strobe_sel	=> lamp_strobe_sel,
	lamp_row_sel	=> lamp_row_sel,
	sound_com_sel	=> sound_com_sel,

	solenoids		=> solenoids,
	sol_1_8_sel		=> sol_1_8_sel,
	sol_9_16_sel	=> sol_9_16_sel,
	sol_spec_sel	=> sol_spec_sel,

	SPC_Sol_Trig	=> SPC_Sol_Trig,

	Mem_prot		=> Mem_prot,
	Advance			=> Advance,
	up_down			=> up_down,
	Enter_SW		=> Enter_SW,
	Diag_SW			=> Diag_SW,

	W_PA_DIP		=> W_PA_DIP,

	Dip_Ret_1		=> Dip_Ret_1,
	Dip_Ret_2		=> Dip_Ret_2,
	Dip_Ret_3		=> Dip_Ret_3,

	DIP_Str_1		=> DIP_Str_1,
	DIP_Str_2		=> DIP_Str_2,
	DIP_Str_3		=> DIP_Str_3,
	DIP_Str_4		=> DIP_Str_4,

	-- The optional ports this board does not have. Outputs stay open, inputs get
	-- their inactive level: USB_Tx is UART idle high, SB_Test is a push button that
	-- reads high when not pressed, and Dip_Ret_4 is an active low DIP return, so '1'
	-- means 'switch off'. Never tie an input to '0' here - that would look like a
	-- pressed button or a set DIP.
	LED_debug		=> open,
	USB_Tx			=> '1',
	USB_Rx			=> open,
	debug			=> open,

	SB_Sound		=> open,
	SB_Speech		=> open,
	SB_Test			=> '1',
	Dip_Ret_4		=> '1'
);

end rtl;
