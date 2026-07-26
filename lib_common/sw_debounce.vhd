-- sw_debounce
-- Matrix-aware hardware debouncer for the Williams SYS7 switch matrix
-- bontango 07.2026 - part of WillFA7
--
-- Purpose:
--   The raw switch return lines (sw_return) come straight from the physical
--   pins and are read combinationally by PIA2 (pa_i). The FPGA input has no
--   analog integration, so mechanical contact bounce produces clean, fast
--   open/close edges. The Williams ROM does have a software debounce, but it
--   is a very weak 2-read filter (see docs/switch_debounce_analysis.md): a
--   switch counts as closed after just TWO consecutive scans of its column.
--   The real 6821 / driver-board analog front-end smears contact chatter
--   enough that the ROM sees one clean close; the sharp FPGA input does not,
--   so hard hits get re-registered inside the ROM's ~2 ms re-arm window.
--
--   This module sits INLINE between the sw_return pins and PIA2. It snoops the
--   one-hot column strobe (sw_strobe), debounces every one of the 8x8 = 64
--   switches individually (per strobe-column x return-row) and presents a
--   stabilized sw_return to PIA2. Polarity is preserved (active high: an active
--   strobe column is high, a closed switch reads its return line high - see
--   board inverter note in WillFA7.vhd).
--
-- Why per-switch (not per return line):
--   sw_return is a SCANNED matrix bus - each return line legitimately changes
--   value with every strobe column (fast). A time low-pass on the raw return
--   lines would corrupt the scan. Debounce must therefore be keyed by the
--   active column and applied per switch.
--
-- Algorithm (per-switch charge integrator with hysteresis - digital RC):
--   - 2-FF synchronizer removes metastability of the async return pins.
--   - The active column is decoded from the one-hot strobe. On every strobe
--     change we wait SETTLE_CYCLES (async settle + sync-FF latency) and then
--     take exactly ONE sample of that column's 8 returns.
--   - Per switch a saturating counter 0..INTEG_MAX: a closed sample adds +1,
--     an open sample subtracts -1. The confirmed state flips to closed only
--     when the counter REACHES INTEG_MAX and back to open only when it
--     REACHES 0 (full-swing hysteresis).
--   - Properties: detection from a settled state takes INTEG_MAX samples
--     (4 -> ~4.6 ms). A re-trigger needs NET predominance over the full
--     span (~2 x INTEG_MAX samples net) - single opposite samples during
--     mechanical ringing only delay by one step instead of resetting all
--     progress. Decaying rattle never wins the net race, so hard-hit ringing
--     of 50-150 ms produces exactly one event. Every emitted event is
--     >= INTEG_MAX samples stable by construction.
--
-- Per-switch DEBOUNCE MASK (this is the key structural fix):
--   The integrator adds open-side latency (~INTEG_MAX scans). That is FATAL
--   for "level" switches - the ones where the ROM fires a coil and then reads
--   the switch back to confirm the state changed: drop-target banks (reset
--   coil -> read that targets came up), eject-hole saucers / outhole (kicker
--   coil -> read the ball is gone). The added open latency makes the ROM read
--   "still down / ball still there", so it re-fires (bank raised 2x, ball
--   ejected 2x) and its per-target sequence model desyncs. The raw v3.17 path
--   has zero open latency there and works perfectly.
--   Because the FPGA can sample each switch only ONCE per ~2 ms scan (the ROM
--   owns the strobe), no purely global filter can both debounce momentary
--   switches AND keep the level switches' zero-latency confirm-reads. Williams
--   itself distinguishes switches by TYPE in software; we do the same in HW.
--   The mask selects, per switch (column x row), whether the debounced value
--   or the raw pin is presented. Level switches are masked OFF (raw); only
--   momentary switches are debounced. A mask miss is fail-safe in ONE
--   direction only: a momentary switch left raw merely keeps v3.17 behaviour,
--   but a level switch wrongly debounced breaks its confirm-read.
--   When 'enable'=0 (DIP5 OFF) the whole module is bypassed to raw v3.17.
--
-- GAME-DEPENDENT MASK (v3.20):
--   The mask is no longer hard-coded for one game. MASK_ROM holds one 8-byte
--   mask per game number (0..31, the same numbering as the SD card ROM slots
--   and the EEPROM page - see WillFA7.vhd 'selection'). The 'game' port carries
--   that number; a free-running refresh loop copies the active game's 8 column
--   bytes into cur_mask, so the read path stays combinational.
--   Derivation of the table (see docs/switch_masks.md):
--     - switch names from the Pinitech switch-matrix database, classified by
--       type (outhole/trough/drop target/eject/kicker/spinner/jet/lock/ramp ->
--       raw; standup/rollover/lane/cabinet -> debounced),
--     - cross-checked against the per-switch handler groups in each game ROM
--       (dispatch table $60F1, 4 bytes/switch, for the System-6 code base),
--     - the Alien Poker row is byte-identical to the v3.18/v3.19 mask that
--       passed on real hardware; it is the regression anchor for the whole
--       table.
--
--   History of rejected designs (see git / memory / docs): N-of-N agreement,
--   refractory lockout and a global integrator all failed on real hardware -
--   every one of them added open latency that broke the drop-target banks and
--   the outhole. Per-switch masking is what avoids that class of failure.
--
--   The output is muxed immediately by the current strobe. The read path has
--   NO added latency; only a CHANGE of a debounced switch needs INTEG_MAX
--   scans to propagate.
--   - Runtime enable (DIP): when 'enable' = '0' the output is the raw async
--     return pins directly, bit-for-bit identical to the pre-debounce v3.17
--     wiring. When '1' the masked/debounced result is presented. The internal
--     integrators keep tracking regardless, so toggling is glitch-free. In
--     WillFA7 enable is driven from option DIP5 (game_option(5), active low:
--     ON -> debounce).
--
-- Tuning:
--   One column visit ~= one ROM matrix scan ~= 2 ms (matrix scanned every 2nd
--   IRQ, IRQ ~1 kHz).
--   INTEG_MAX: samples for a state change from a settled state (4 -> ~8 ms
--     latency at 2 ms/scan). Raise to 5 if hard hits still double-trigger;
--     lower to 3 if fast stand-up hits are missed.
--   Keep SETTLE_CYCLES >= 2 so the 2-FF synchronizer has settled before
--     sampling.
--   MASK_ROM: per game (0..31) eight bytes, one per column (index = strobe bit
--     = matrix column - 1). A '1' bit (index = return bit = matrix row - 1)
--     means "debounce this switch", '0' means "pass the raw pin through".

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sw_debounce is
    generic (
        INTEG_MAX     : natural := 4;   -- integrator span: samples for a state change from settled (~8 ms)
        SETTLE_CYCLES : natural := 4    -- wait cycles after a strobe change before sampling
    );
    port (
        clk           : in  std_logic;                     -- cpu_clk (~894 kHz)
        i_Rst_L       : in  std_logic;                     -- reset_l (active low)
        enable        : in  std_logic;                     -- '1' = debounce (masked), '0' = raw passthrough (v3.17)
        game          : in  std_logic_vector(5 downto 0);  -- game number 0..31 (= 'selection', not game_select)
        sw_strobe     : in  std_logic_vector(7 downto 0);  -- one-hot column select (active high)
        sw_return_raw : in  std_logic_vector(7 downto 0);  -- raw returns from the pins (active high)
        sw_return_deb : out std_logic_vector(7 downto 0)   -- debounced/masked returns -> PIA2 pa_i
    );
end sw_debounce;

architecture Behavioral of sw_debounce is

    type deb_array is array (0 to 7) of std_logic_vector(7 downto 0);
    type intg_row   is array (0 to 7) of integer range 0 to INTEG_MAX;
    type intg_array is array (0 to 7) of intg_row;

    -- ---------------------------------------------------------------------
    -- MASK_ROM: 32 games x 8 columns, one byte per column.
    -- Address = game(4 downto 0) & column index. Bit n of a column byte refers
    -- to return line n, i.e. matrix switch  8*column + n + 1  (Williams
    -- numbering, verified against the ROM's own switch-number computation).
    -- '1' = debounce this switch, '0' = pass the raw pin through.
    -- Read is registered so Quartus infers a single M9K block (2048 bits)
    -- instead of ~300 LEs of multiplexer logic.
    -- Confidence tags: [HW ] verified on real hardware, [ROM] switch names plus
    -- ROM handler-group cross-check, [MTX] switch names only, [---] no data.
    -- ---------------------------------------------------------------------
    type mask_rom_t is array (0 to 255) of std_logic_vector(7 downto 0);
    constant MASK_ROM : mask_rom_t := (
        --  0 Hot Tip          SYS3  [HB ]
        x"7F", x"2E", x"D8", x"88", x"03", x"00", x"00", x"00",
        --  1 Lucky Seven      SYS3  [HB ]
        x"7F", x"1F", x"3E", x"7C", x"F4", x"01", x"02", x"00",
        --  2 World Cup        SYS3  [HB ]
        x"7F", x"4E", x"F7", x"FE", x"0F", x"00", x"00", x"00",
        --  3 Contact          SYS3  [HB ]
        x"7F", x"FD", x"F7", x"81", x"F8", x"00", x"00", x"00",
        --  4 Disco Fever      SYS3  [HB ]
        x"7F", x"FB", x"86", x"2F", x"86", x"00", x"00", x"00",
        --  5 Pokerino         SYS4  [MTX]
        x"FF", x"FD", x"E0", x"C4", x"10", x"3D", x"00", x"00",
        --  6 Phoenix          SYS4  [MTX]
        x"FF", x"3F", x"FC", x"C0", x"E0", x"C0", x"00", x"00",
        --  7 Flash            SYS4  [ROM]
        x"FF", x"FF", x"F0", x"03", x"E0", x"7C", x"00", x"00",
        --  8 Stellar Wars     SYS4  [ROM]
        x"FF", x"0E", x"C8", x"3E", x"28", x"87", x"01", x"00",
        --  9 Tri Zone         SYS6  [ROM]
        x"FF", x"0E", x"77", x"9C", x"02", x"00", x"00", x"00",
        -- 10 Time Warp        SYS6  [ROM]
        x"FF", x"BE", x"03", x"C0", x"F0", x"0C", x"00", x"00",
        -- 11 Gorgar           SYS6  [ROM]
        x"FF", x"B6", x"A1", x"DF", x"87", x"00", x"00", x"00",
        -- 12 Laser Ball       SYS6  [ROM]
        x"FF", x"AC", x"02", x"7F", x"41", x"86", x"FF", x"07",
        -- 13 Firepower        SYS6  [ROM]
        x"FF", x"A6", x"00", x"D0", x"37", x"DC", x"03", x"00",
        -- 14 Blackout         SYS6  [ROM]
        x"FF", x"02", x"0C", x"F0", x"20", x"33", x"00", x"00",
        -- 15 Scorpion         SYS6  [ROM]
        x"FF", x"70", x"1F", x"00", x"00", x"FF", x"FF", x"01",
        -- 16 Algar            SYS6A [ROM]
        x"FF", x"1C", x"DA", x"ED", x"13", x"34", x"1E", x"00",
        -- 17 Alien Poker      SYS6A [HW ]
        x"FF", x"AC", x"DC", x"ED", x"C1", x"05", x"00", x"00",
        -- 18 Black Knight     SYS7  [MTX]
        x"FF", x"CC", x"40", x"00", x"00", x"20", x"00", x"00",
        -- 19 Jungle Lord      SYS7  [MTX]
        x"FF", x"F0", x"FF", x"80", x"00", x"79", x"00", x"00",
        -- 20 Pharaoh          SYS7  [MTX]
        x"FF", x"F0", x"00", x"88", x"00", x"02", x"00", x"00",
        -- 21 Solar Fire       SYS7  [MTX]
        x"FF", x"F0", x"00", x"01", x"80", x"06", x"00", x"00",
        -- 22 Barracora        SYS7  [MTX]
        x"FF", x"01", x"C7", x"CE", x"FF", x"00", x"00", x"00",
        -- 23 Cosmic Gunfight  SYS7  [MTX]
        x"FF", x"FF", x"0E", x"E0", x"67", x"00", x"0B", x"00",
        -- 24 Varkon           SYS7  [MTX]
        x"FD", x"F1", x"FF", x"7F", x"F8", x"00", x"00", x"00",
        -- 25 Warlok           SYS7  [MTX]
        x"FF", x"80", x"C7", x"03", x"78", x"00", x"00", x"00",
        -- 26 Time Fantasy     SYS7  [MTX]
        x"FF", x"FF", x"FF", x"FF", x"88", x"03", x"00", x"00",
        -- 27 Joust            SYS7  [MTX]
        x"FD", x"00", x"38", x"40", x"00", x"38", x"40", x"01",
        -- 28 Firepower II     SYS7  [MTX]
        x"FF", x"90", x"AD", x"FF", x"7F", x"30", x"01", x"00",
        -- 29 Laser Cue        SYS7  [MTX]
        x"FF", x"CE", x"78", x"FF", x"FF", x"06", x"00", x"00",
        -- 30 Defender         SYS7  [MTX]
        x"FF", x"0F", x"1C", x"70", x"38", x"01", x"3C", x"5C",
        -- 31 Star Light       SYS7  [MTX]
        x"FF", x"F0", x"FF", x"FE", x"FF", x"F8", x"31", x"00"
    );

    -- active game's mask, refreshed continuously from MASK_ROM
    signal cur_mask   : deb_array := (others => (others => '0'));
    signal rom_addr   : unsigned(7 downto 0) := (others => '0');
    signal rom_q      : std_logic_vector(7 downto 0) := (others => '0');
    signal rfr_col    : unsigned(2 downto 0) := (others => '0');
    signal rfr_col_d1 : unsigned(2 downto 0) := (others => '0');
    signal rfr_col_d2 : unsigned(2 downto 0) := (others => '0');

    -- confirmed (debounced) switch states, indexed [column](row); '1' = closed
    signal deb : deb_array := (others => (others => '0'));
    -- per switch saturating charge integrator (+1 closed / -1 open sample)
    signal intg : intg_array := (others => (others => 0));

    -- 2-FF synchronizer for the async return pins
    signal sync1 : std_logic_vector(7 downto 0) := (others => '0');
    signal sync2 : std_logic_vector(7 downto 0) := (others => '0');

    signal prev_strobe : std_logic_vector(7 downto 0) := (others => '0');
    signal settle_cnt  : integer range 0 to SETTLE_CYCLES := 0;
    signal sampled     : std_logic := '0';
    signal last_col    : integer range 0 to 7 := 0;

    -- combinational one-hot decode of the current strobe
    signal col_idx_c    : integer range 0 to 7 := 0;
    signal strobe_valid : std_logic := '0';

begin

    ---------------------------------------------------------------
    -- one-hot strobe decode: exactly one active column -> valid
    ---------------------------------------------------------------
    decode : process (sw_strobe)
        variable bits : integer;
        variable idx  : integer range 0 to 7;
    begin
        bits := 0;
        idx  := 0;
        for i in 0 to 7 loop
            if sw_strobe(i) = '1' then
                bits := bits + 1;
                idx  := i;
            end if;
        end loop;
        if bits = 1 then
            strobe_valid <= '1';
            col_idx_c    <= idx;
        else
            strobe_valid <= '0';
            col_idx_c    <= 0;
        end if;
    end process;

    ---------------------------------------------------------------
    -- mask refresh: free-running walk over the active game's 8 column
    -- bytes. No boot trigger and no reset dependency - the loop simply
    -- keeps cur_mask in sync, so a change of the game DIPs is picked up
    -- automatically within 8 clocks (~9 us at 894 kHz).
    -- Three stages: address -> registered ROM read -> store. The column
    -- index is delayed alongside so each byte lands in the right slot.
    ---------------------------------------------------------------
    refresh : process (clk)
    begin
        if rising_edge(clk) then
            rom_addr   <= unsigned(game(4 downto 0)) & rfr_col;
            rom_q      <= MASK_ROM(to_integer(rom_addr));   -- registered -> M9K
            cur_mask(to_integer(rfr_col_d2)) <= rom_q;
            rfr_col_d2 <= rfr_col_d1;
            rfr_col_d1 <= rfr_col;
            rfr_col    <= rfr_col + 1;
        end if;
    end process;

    ---------------------------------------------------------------
    -- sample & debounce (charge integrator with hysteresis)
    ---------------------------------------------------------------
    sample : process (clk, i_Rst_L)
    begin
        if i_Rst_L = '0' then
            deb         <= (others => (others => '0'));
            intg        <= (others => (others => 0));
            sync1       <= (others => '0');
            sync2       <= (others => '0');
            prev_strobe <= (others => '0');
            settle_cnt  <= 0;
            sampled     <= '0';
            last_col    <= 0;
        elsif rising_edge(clk) then
            -- metastability synchronizer
            sync1 <= sw_return_raw;
            sync2 <= sync1;

            if sw_strobe /= prev_strobe then
                -- new column activation: restart settle window, allow one sample
                settle_cnt <= 0;
                sampled    <= '0';
            elsif strobe_valid = '1' and sampled = '0' then
                if settle_cnt >= SETTLE_CYCLES then
                    -- take exactly one sample of the active column
                    for r in 0 to 7 loop
                        if sync2(r) = '1' then
                            -- closed sample: charge up, flip closed at the top
                            if intg(col_idx_c)(r) /= INTEG_MAX then
                                intg(col_idx_c)(r) <= intg(col_idx_c)(r) + 1;
                                if intg(col_idx_c)(r) = INTEG_MAX - 1 then
                                    deb(col_idx_c)(r) <= '1';
                                end if;
                            end if;
                        else
                            -- open sample: discharge, flip open at the bottom
                            if intg(col_idx_c)(r) /= 0 then
                                intg(col_idx_c)(r) <= intg(col_idx_c)(r) - 1;
                                if intg(col_idx_c)(r) = 1 then
                                    deb(col_idx_c)(r) <= '0';
                                end if;
                            end if;
                        end if;
                    end loop;
                    sampled <= '1';
                else
                    settle_cnt <= settle_cnt + 1;
                end if;
            end if;

            -- remember last valid column for the output hold
            if strobe_valid = '1' then
                last_col <= col_idx_c;
            end if;

            prev_strobe <= sw_strobe;
        end if;
    end process;

    ---------------------------------------------------------------
    -- output: per-bit mux for the currently strobed column.
    --   enable = '0'          -> raw async pins (bit-for-bit v3.17)
    --   mask bit = '0'        -> raw async pin  (level/spinner/jet switch)
    --   mask bit = '1'        -> debounced value
    -- No added latency in the read path; raw bits are always the live pins.
    ---------------------------------------------------------------
    outmux : process (enable, strobe_valid, col_idx_c, last_col, deb, sw_return_raw, cur_mask)
        variable ac : integer range 0 to 7;
    begin
        if strobe_valid = '1' then
            ac := col_idx_c;
        else
            ac := last_col;
        end if;
        for r in 0 to 7 loop
            if enable = '0' then
                sw_return_deb(r) <= sw_return_raw(r);
            elsif cur_mask(ac)(r) = '1' then
                sw_return_deb(r) <= deb(ac)(r);
            else
                sw_return_deb(r) <= sw_return_raw(r);
            end if;
        end loop;
    end process;

end Behavioral;
