-- Top level file for a Williams compatible Soundboard
-- Type1 and Type2 used in Williams System3 .. System7
-- by bontango www.lisy.dev
-- 
--
-- Version for WILLFA7S based on WISOF 0.8


library ieee;
use ieee.std_logic_1164.all;


entity WISOF is
port(

		clk_50	: in std_logic;
		clk_14	: in std_logic;
		cpu_clk	: in std_logic;
		reset_l	: in std_logic;		
		test		: in std_logic := '1';
		sound_o  : out std_logic;
		speech_o  : out std_logic;
		
		-- Sound input only 5bit out of 8bit are used
		-- initial low due to 2803A on input of WISOF
		Sound :	in 	std_logic_vector(4 downto 0);
		
		--Soundboard Options DIPs 1..4
		SB_Opt :	in 	std_logic_vector(4 downto 1);
						
		rom1_dout :	in std_logic_vector(7 downto 0);
		rom2_dout :	in std_logic_vector(7 downto 0);
		rom3_dout :	in std_logic_vector(7 downto 0);
		rom4_dout :	in std_logic_vector(7 downto 0);
		rom5_dout :	in std_logic_vector(7 downto 0);
		
		sb_address	:	out std_logic_vector(11 downto 0)
);
end WISOF;


architecture rtl of WISOF is

--signal cpu_clk		:  std_logic;  --894KHz for Williams
--signal clk_14		:  std_logic; -- 14,28MHz from PLL

signal reset_h		: std_logic;

signal snd_ctl_i	: std_logic_vector(7 downto 0);
signal audio		: std_logic_vector(7 downto 0);

signal cpu_addr	: std_logic_vector(15 downto 0);
signal cpu_din		: std_logic_vector(7 downto 0);
signal cpu_dout	: std_logic_vector(7 downto 0);
signal cpu_rw		: std_logic;
signal cpu_vma		: std_logic;
signal cpu_irq		: std_logic;
signal cpu_nmi		: std_logic;

signal rom1_cs		: 	std_logic;
signal rom2_cs		: 	std_logic;
signal rom3_cs		: 	std_logic;
signal rom4_cs		: 	std_logic;
signal rom5_cs		: 	std_logic;

signal ram_dout	: std_logic_vector(7 downto 0);
signal ram_cs		: std_logic;
signal ram_we		: std_logic;

signal pia_dout	: std_logic_vector(7 downto 0);
signal pia_cs		: std_logic;
signal pia_irq_a	: std_logic := '1';
signal pia_irq_b	: std_logic := '1';
signal pia_cb1		: std_logic;
	
	-- nmi
signal diag				:	std_logic; 
signal diag_stable	:	std_logic; 

-- speech
signal clk55516		: std_logic;
signal dig55516		: std_logic;
signal speech55516		: std_logic_vector(15 downto 0);



begin
reset_h <= (not reset_l);
diag <= not test; -- NMI

	
-- Real hardware uses a 6802 which is a 6800 with internal oscillator and 128 byte RAM
CPU: entity work.cpu68
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

-- 6802 contains internal 128 byte RAM, using 6800 softcore so RAM is separate
RAM: entity work.mpu_ram
port map(
	address => cpu_addr(6 downto 0),
	clock => cpu_clk, 
	data => cpu_dout,
	wren => not cpu_rw,
	q => ram_dout
	);

-- PIA IRQ outputs both assert CPU IRQ input
cpu_irq <= pia_irq_a or pia_irq_b;

------------------
-- address decoding (no addr15)
------------------
sb_address <= cpu_addr(11 downto 0);
ram_cs <= '1' when cpu_addr(14 downto 7) = "00000000" and cpu_vma='1' else '0'; --0x0 - 0x7F
pia_cs <= '1' when cpu_addr(14 downto 2) = "0000100000000" and cpu_vma='1' else '0'; --0x0400 - 0x0403
	
-- roms 4K each
--rom_cs <= cpu_addr(11) and cpu_vma;
rom1_cs <= '1' when cpu_addr(14 downto 12) = "011" and cpu_vma='1' else '0'; --0x3000 - 0x3FFF 4K IC7
rom2_cs <= '1' when cpu_addr(14 downto 12) = "100" and cpu_vma='1' else '0'; --0x4000 - 0x4FFF 4K IC5
rom3_cs <= '1' when cpu_addr(14 downto 12) = "101" and cpu_vma='1' else '0'; --0x5000 - 0x5FFF 4K IC6
rom4_cs <= '1' when cpu_addr(14 downto 12) = "110" and cpu_vma='1' else '0'; --0x6000 - 0x6FFF 4K IC4
rom5_cs <= '1' when cpu_addr(14 downto 12) = "111" and cpu_vma='1' else '0'; --0x7000 - 0x7FFF 4K IC12 ( double!)
------------------

-- Bus control
cpu_din <= 
	pia_dout when pia_cs = '1' else
	rom1_dout when rom1_cs = '1' else
	rom2_dout when rom2_cs = '1' else
	rom3_dout when rom3_cs = '1' else	
	rom4_dout when rom4_cs = '1' else	
	rom5_dout when rom5_cs = '1' else	
	ram_dout when ram_cs = '1' else
	x"FF";

	-- Bus control
--cpu_din <= 
--	pia_dout when pia_cs = '1' else
--	rom_dout when rom_cs = '1' else
--	ram_dout when ram_cs = '1' else
--	x"FF";

-- Real hardware uses 6820 Peripheral Interface Adapter, 6821 is functionally equivalent
PIA: entity work.pia6821
port map(
	clk => cpu_clk,
   rst => reset_h,     
   cs => pia_cs,     
   rw => cpu_rw,    
   addr => cpu_addr(1 downto 0),     
   data_in => cpu_dout,  
	data_out => pia_dout, 
	irqa => pia_irq_a,   
	irqb => pia_irq_b,    
	pa_i => x"FF",    
	pa_o => audio,    
	ca1 => '0',    
	ca2_i => '0',    
	ca2_o => dig55516, -- speech data   
	pb_i => snd_ctl_i,    
	pb_o => open,    
	cb1 => pia_cb1,    
	cb2_i => '0',  
	cb2_o => clk55516, --speech clock
	default_pb_level => '0'  -- output level when configured as input   
);
		
	
snd_ctl_i(0) <= sound(0); -- sound input J3-3
snd_ctl_i(1) <= sound(1); -- sound input J3-2
snd_ctl_i(2) <= sound(2); -- sound input J3-5
snd_ctl_i(3) <= sound(3); -- sound input J3-4
snd_ctl_i(4) <= sound(4); -- sound input J3-7
snd_ctl_i(5) <= SB_Opt(2); -- Switch2 ON selects Speech, OFF selects no speech ( type2 SB only! )
snd_ctl_i(6) <= SB_Opt(1); -- Switch1 ON selects Chime notes, OFF selects synthesized sounds
snd_ctl_i(7) <= '1'; -- not used

-- Sound control inputs all assert cb1 on PIA
-- 2,3,4,5 & 7 wired which go to 
-- PB0 - 3
-- PB1 - 2
-- PB2 - 5
-- PB3 - 4
-- PB4 - 7
pia_cb1 <= not ( sound(4) and sound(3) and sound(2) and sound(1) and sound(0));


DIAGSTABLE: entity work.Cross_Slow_To_Fast_Clock
port map(
   i_D => diag,
	o_Q => diag_stable,
   i_Fast_Clk => cpu_clk
	);
	
DIAGSW: entity work.one_pulse_only
port map(
   sig_in => diag_stable,
	sig_out => cpu_nmi,
	--sig_out => pia_cb1,
   clk_in => cpu_clk,
	rst => reset_l
	);
	
	-- PLL takes 50MHz clock on mini board and puts out 14.28MHz	
--PLL: entity work.williams_pll
--port map(
--	inclk0 => clk_50,
--	c0 => clk_14,
--	c1 => cpu_clk --700KHz for Test (was 892KHz)
--	);
	
--clock_gen: entity work.cpu_clk_gen
--port map(   
--	clk_in => clk_14,
--	clk_out	=> cpu_clk,
--	shift_clk_out	=> open
--);

-- HC55516/HC55564 Continuously Variable Slope Delta decoder
HC55564_1: entity work.hc55564
port map(
   clk   	=> clk_50,
   cen 	=> clk55516,
   bit_in   	=> dig55516,
   sample_out   	=> speech55516
	);


-- Delta Sigma DAC sound
sound_DAC: entity work.dac
port map(
   clk_i   	=> clk_14,
   res_n_i 	=> reset_l,
   dac_i   	=> audio,
   dac_o   	=> sound_o
	);

-- Delta Sigma DAC speech
Speech_DAC: entity work.dac
generic map (
	msbi_g	=> 15
)
port map(
   clk_i   	=> clk_50,
   res_n_i 	=> reset_l,
   dac_i   	=> speech55516,
   dac_o   	=> speech_o
	);

	
end rtl;
		