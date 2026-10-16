--
-- Flash_ROM.vhd
-- read the game ROMs from the FPGA configuration flash (EPCS16) instead of the SD card
-- fallback for WillFA, started by SD_Card when no card answers (o_no_card)
-- bontango 10.2026
--
-- v01 first version.
--
-- Flash layout (written by scripts/make_flash_hex.ps1 into a local .jic, see
-- willfa7_roms.cof of the variant):
--     0x000000 - 0x07FFFF   bitstream plus reserve
--     Base_Addr + n * Slot_Bytes
--                           game n, the first 32 KByte of its SD card slot 1:1:
--                           0x0000-0x2FFF MPU ROMs, 0x3000-0x7FFF sound board ROMs
--
-- No CRC. The flash has no contacts and no file system, and the data is verified by
-- the programmer when it is written. What is left is a check against an EMPTY flash
-- (the released .jic carries no ROMs, erased = FF): the reset vector of the game,
-- slot offset 2FFEh/2FFFh = 7FFEh/7FFFh for the MPU, must not read FFFF. Otherwise
-- error code 8 and the CPU is not released.
--
-- Same output side as SD_Card (address, data, wr_rom, cpu_reset_l, error LED), so the
-- top level only has to switch between the two.
--
-- SPI mode 0, READ (03h) with a 24 bit address, then one continuous stream. Own small
-- shifter on purpose - SPI_Master.vhd is not touched (see CLAUDE.md).

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

	entity Flash_ROM is
		generic (
			-- payload bytes per game, from the start of the slot
			Read_Bytes : integer := 32768;
			-- where game 0 starts in the flash, and how far apart the games are
			Base_Addr  : integer := 16#080000#;
			Slot_Bytes : integer := 32768;
			-- SPI clock half period in i_Clk cycles. 2 at 50 MHz = 12.5 MHz, the
			-- EPCS16 allows 20 MHz for READ (03h).
			Half_Period : integer := 2
		);
		port(
		i_Clk		: in std_logic;
		i_Rst_L	: in std_logic;     -- '0' holds the loader, '1' starts it
		-- configuration flash, dual purpose pins of the FPGA
		o_Flash_Clk  : out std_logic;   -- DCLK
		o_Flash_CS_n : out std_logic;   -- nCSO
		o_Flash_MOSI : out std_logic;   -- ASDO, data into the flash
		i_Flash_MISO : in std_logic;    -- DATA0, data out of the flash
		-- selection
		selection : in std_logic_vector(7 downto 0);
		-- rom write port, same meaning as at SD_Card
		address_rom	: buffer std_logic_vector(15 downto 0);
		data_rom		: buffer std_logic_vector(7 downto 0);
		wr_rom		: buffer std_logic;
		-- start CPU
		cpu_reset_l : out std_logic;
		-- feedback
		Flash_error : out std_logic;    -- active low, blinks error code 8
		flash_empty : out std_logic     -- '1' = the reset vector read FFFF
		);
    end Flash_ROM;

   architecture Behavioral of Flash_ROM is
		type STATE_T is ( start, bit_low, bit_high, write_byte, inc_addr, check_vector,
								all_done, error );
		signal state : STATE_T;

		-- error code of this loader, continues the SD_Card numbering (1..7)
		constant ERR_CODE : integer := 8;

		-- slot offsets of the MPU reset vector (7FFEh/7FFFh)
		constant VEC_HI : integer := 16#2FFE#;
		constant VEC_LO : integer := 16#2FFF#;

		signal tx_sr    : std_logic_vector(31 downto 0); -- command and address
		signal rx_sr    : std_logic_vector(7 downto 0);
		signal bit_cnt  : integer range 0 to 31;
		signal in_cmd   : std_logic;                     -- '1' while the 32 command bits go out
		signal div      : integer range 0 to 255;
		signal vec_ok   : std_logic;                     -- a reset vector byte was not FF
		signal counter  : integer range 0 to 100000000;
		signal blink_remaining : integer range 0 to 15;
	begin

		Flash: process (i_Clk)
		begin
		if rising_edge(i_Clk) then
			if i_Rst_L = '0' then
				o_Flash_Clk <= '0';
				o_Flash_CS_n <= '1';
				o_Flash_MOSI <= '0';
				cpu_reset_l <= '0';
				wr_rom <= '0';
				address_rom <= (others => '0');
				data_rom <= x"FF";
				Flash_error <= '1'; -- active low
				flash_empty <= '0';
				vec_ok <= '0';
				div <= 0;
				bit_cnt <= 0;
				in_cmd <= '0';
				counter <= 0;
				blink_remaining <= 0;
				state <= start;
			else
				case state is
				when start =>
					-- READ (03h) plus 24 bit address of the slot
					tx_sr <= x"03" & std_logic_vector( to_unsigned(Base_Addr, 24)
							 + unsigned(selection) * to_unsigned(Slot_Bytes, 16) );
					o_Flash_CS_n <= '0';
					bit_cnt <= 31;
					in_cmd <= '1';
					div <= 0;
					state <= bit_low;

				-- one SPI bit: clock low half, then clock high half. The flash takes
				-- MOSI on the rising edge and shifts its data out on the falling one,
				-- so MISO is sampled together with the rising edge.
				when bit_low =>
					o_Flash_MOSI <= tx_sr(31);
					if div = Half_Period - 1 then
						div <= 0;
						o_Flash_Clk <= '1';
						rx_sr <= rx_sr(6 downto 0) & i_Flash_MISO;
						state <= bit_high;
					else
						div <= div + 1;
					end if;

				when bit_high =>
					if div = Half_Period - 1 then
						div <= 0;
						o_Flash_Clk <= '0';
						tx_sr <= tx_sr(30 downto 0) & '0';
						if bit_cnt = 0 then
							if in_cmd = '1' then
								-- command and address are out, data follows
								in_cmd <= '0';
								bit_cnt <= 7;
								state <= bit_low;
							else
								data_rom <= rx_sr;
								state <= write_byte;
							end if;
						else
							bit_cnt <= bit_cnt - 1;
							state <= bit_low;
						end if;
					else
						div <= div + 1;
					end if;

				-- address and data are stable here, one clock of wr_rom like SD_Card.
				-- The SPI clock just pauses meanwhile.
				when write_byte =>
					wr_rom <= '1';
					if ( unsigned(address_rom) = to_unsigned(VEC_HI, address_rom'length)
					  or unsigned(address_rom) = to_unsigned(VEC_LO, address_rom'length) )
					  and data_rom /= x"FF" then
						vec_ok <= '1';
					end if;
					state <= inc_addr;

				when inc_addr =>
					wr_rom <= '0';
					if unsigned(address_rom) = to_unsigned(Read_Bytes - 1, address_rom'length) then
						o_Flash_CS_n <= '1';
						state <= check_vector;
					else
						address_rom <= std_logic_vector(unsigned(address_rom) + 1);
						bit_cnt <= 7;
						state <= bit_low;
					end if;

				when check_vector =>
					counter <= 0;
					if vec_ok = '1' then
						state <= all_done;
					else
						-- empty flash: running FF would be worse than showing the error
						flash_empty <= '1';
						blink_remaining <= ERR_CODE;
						state <= error;
					end if;

				when all_done =>
					-- wait a bit, then start cpu - same 500 ms as SD_Card
					if ( counter < 25000000 ) then
						counter <= counter + 1;
					else
						cpu_reset_l <= '1';
						Flash_error <= '1'; --active low
					end if;

				when error =>
					-- Blink ERR_CODE times (LED active low: '0' = on), then ~2 s gap,
					-- repeat forever. Per blink: 250 ms ON, 250 ms OFF. As in SD_Card.
					counter <= counter + 1;
					if blink_remaining = 0 then
						Flash_error <= '1';
						if counter >= 100000000 then -- 2 s @ 50 MHz
							counter <= 0;
							blink_remaining <= ERR_CODE;
						end if;
					else
						if counter < 12500000 then       -- 0..250 ms: LED on
							Flash_error <= '0';
						elsif counter < 25000000 then    -- 250..500 ms: LED off
							Flash_error <= '1';
						else                              -- end of one blink
							counter <= 0;
							blink_remaining <= blink_remaining - 1;
						end if;
					end if;

				end case;
			end if; --rst
		end if; --rising edge
		end process;

    end Behavioral;
