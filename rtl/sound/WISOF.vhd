-- Williams compatible Soundboard core
-- Type1 and Type2 used in Williams System3 .. System7
-- by bontango www.lisy.dev
--
--
-- Version for WILLFA7S based on WISOF 0.9
--
-- This is the sound board of the standalone project
--   N:\Projekte\Soundboards\FPGA Soundboard Williams\WISOF
-- reduced to what the WillFA7S needs: no SD card, no PLL, no LEDs and no board pins.
-- The five ROM blocks live in the MPU top level because they are filled from the same
-- SD card as the game ROMs, and clk_50 / cpu_clk come from the MPU as well.
--
-- Lifted from 0.8 to 0.9 with the findings of that project's docs/vhdl_review.md.
-- Which of them apply here and which do not is written down in
-- docs/soundcard_variant.md - read that before changing anything in this file.
--   F2  RAM write enable qualified by ram_cs
--   F4/F5 sound and speech are summed and share one 10 bit DAC at clk_50 (48.8 kHz),
--         like the analog mixer R8 on the original speech module. On the WillFA7S only
--         SB_Sound reaches the amplifier, so this is also the only way speech is heard
--         at all. The two old DACs are gone, and with them the clk_14 port.
--   F10 ca1 tied high, the original pulls it up through R33
--   F8/F9 kept as they are, with the reasoning written down at the code
--   F1/F3 in hc55564.vhd
-- Not applicable here: F6 (there is no sixth sound select line to connect - the
-- Williams sound/comma latch carries five), F7 (the .sdc of the MPU already declares
-- clk_50 and cpu_clk asynchronous), F11 (rtl/common/one_pulse_only.vhd), F12 and F13.


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity WISOF is
port(

		clk_50	: in std_logic;
		cpu_clk	: in std_logic;
		reset_l	: in std_logic;
		test		: in std_logic := '1';
		-- sound and speech mixed, delta sigma ( F4/F5 )
		sound_o  : out std_logic;

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
signal speech55516		: std_logic_vector(15 downto 0); -- signed, from hc55564

-- audio mixer ( F4/F5 )
signal audio_stable	: std_logic_vector(7 downto 0); -- DAC value, synchronised to clk_50
signal sound_s		: signed(10 downto 0);
signal speech_s	: signed(10 downto 0);
signal mix_s		: signed(10 downto 0);
signal mix_sat		: signed(9 downto 0);
signal mix_u		: std_logic_vector(9 downto 0);



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
	wren => ram_we,
	q => ram_dout
	);

-- F2: without ram_cs every CPU write landed in the RAM, so writing the PIA registers
-- at 0x0400..0x0403 also overwrote RAM 0x00..0x03 - RAM 0x00 with the current DAC
-- sample on every single sound sample. ram_cs already includes cpu_vma.
ram_we <= ram_cs and (not cpu_rw);

-- PIA IRQ outputs both assert CPU IRQ input
cpu_irq <= pia_irq_a or pia_irq_b;

------------------
-- address decoding (no addr15)
------------------
sb_address <= cpu_addr(11 downto 0);
ram_cs <= '1' when cpu_addr(14 downto 7) = "00000000" and cpu_vma='1' else '0'; --0x0 - 0x7F

-- F9: the original decodes CS0 <- VMA, CS1 <- A10, CS2 <- page 0x0000 or 0x8000, so
-- A2..A9 and A11 are don't care and the PIA answers over 0x0400-0x07FF and
-- 0x0C00-0x0FFF with the four registers repeating every 4 bytes. PinMAME models the
-- same four bytes as WISOF does and no known game relies on the mirrors, so this stays.
pia_cs <= '1' when cpu_addr(14 downto 2) = "0000100000000" and cpu_vma='1' else '0'; --0x0400 - 0x0403

-- roms 4K each
-- F8: sb_address leaves this core in the cpu_clk domain and the ROM blocks in the top
-- level are clocked from clk_50, an unsynchronised crossing. It is harmless because the
-- CPU samples the data one cpu_clk period (1118 ns) later, by which time the ROM has
-- long settled - and the MPU .sdc declares the two domains asynchronous anyway.
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
	ca1 => '1',    -- F10: the original pulls CA1 up through R33 and uses it for nothing else
	ca2_i => '0',
	ca2_o => dig55516, -- speech data
	pb_i => snd_ctl_i,
	pb_o => open,
	cb1 => pia_cb1,
	cb2_i => '0',
	cb2_o => clk55516, --speech clock
	default_pb_level => '0'  -- output level when configured as input
);


-- No synchroniser on the sound select lines ( unlike WISOF 0.9 ): on the WillFA7S they
-- do not come from the outside world but from PIA5 resp. the solenoid outputs of the
-- MPU, in the same cpu_clk domain as this CPU. They are already active low here too -
-- the top level inverts the System3/4 source, see docs/soundcard_variant.md.
snd_ctl_i(0) <= sound(0); -- sound input J3-3
snd_ctl_i(1) <= sound(1); -- sound input J3-2
snd_ctl_i(2) <= sound(2); -- sound input J3-5
snd_ctl_i(3) <= sound(3); -- sound input J3-4
snd_ctl_i(4) <= sound(4); -- sound input J3-7
snd_ctl_i(5) <= SB_Opt(2); -- Switch2 ON selects Speech, OFF selects no speech ( type2 SB only! )
snd_ctl_i(6) <= SB_Opt(1); -- Switch1 ON selects Chime notes, OFF selects synthesized sounds
snd_ctl_i(7) <= '1'; -- not used, see F6 in docs/soundcard_variant.md

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
   clk_in => cpu_clk,
	rst => reset_l
	);

-- HC55516/HC55564 Continuously Variable Slope Delta decoder
HC55564_1: entity work.hc55564
port map(
   clk   	=> clk_50,
   cen 	=> clk55516,
	rst		=> reset_l,
   bit_in   	=> dig55516,
   sample_out   	=> speech55516
	);

------------------------------------------------------------------
-- audio path ( F4, F5 )
--
-- The original sums the two signals in the analog domain on the speech module: the
-- 1408 output leaves the sound board on 10J5-3, is mixed with the CVSD output through
-- the 5K pot R8 and comes back on 10J5-4. A game can play a sound effect and speech at
-- the same time, so this sums them too instead of switching between them. R8 in its
-- middle position is a 1:1 mix, which is what is built here.
--
-- On the WillFA7S there is a second reason: only SB_Sound goes to the amplifier, so
-- without this mixer the speech channel would never be audible at all.
--
-- The old speech DAC ran 16 bit at 50MHz. dac.vhd is a first order delta sigma
-- modulator and needs 2**(n+1) clocks per sample, so that was 50MHz/65536 = 763Hz
-- effective rate. The mixed signal is 10 bit and gives 50MHz/1024 = 48.8kHz.
------------------------------------------------------------------

-- the DAC value comes from the PIA in the cpu_clk domain
AUDIOSTABLE: entity work.Cross_Slow_To_Fast_Clock_Bus
port map(
   i_D => audio,
	o_Q => audio_stable,
   i_Fast_Clk => clk_50
	);

-- sound: 8 bit unsigned, silence sits at mid scale, scaled up by 2 to use the full range
sound_s  <= shift_left(resize(signed('0' & audio_stable) - 128, 11), 1);
-- speech: signed 16 bit from the CVSD integrator, scaled down to the same magnitude
speech_s <= resize(shift_right(signed(speech55516), 7), 11);

mix_s <= sound_s + speech_s;

mix_sat <= to_signed(511, 10)  when mix_s > 511  else
           to_signed(-512, 10) when mix_s < -512 else
           resize(mix_s, 10);

-- two's complement to offset binary for the DAC: invert the sign bit
mix_u <= (not mix_sat(9)) & std_logic_vector(mix_sat(8 downto 0));

-- Delta Sigma DAC, sound and speech mixed
MIX_DAC: entity work.dac
generic map (
	msbi_g	=> 9
)
port map(
   clk_i   	=> clk_50,
   res_n_i 	=> reset_l,
   dac_i   	=> mix_u,
   dac_o   	=> sound_o
	);


end rtl;
