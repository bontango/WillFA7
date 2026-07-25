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
--   DEBOUNCE_MASK selects, per switch (column x row), whether the debounced
--   value or the raw pin is presented. Level switches are masked OFF (raw);
--   only momentary switches are debounced. A mask miss is fail-safe: an
--   un-masked momentary switch merely keeps raw behaviour, it cannot break a
--   confirm-read. The mask below is for Williams *Alien Poker* (see the switch
--   matrix in docs/) - it is GAME SPECIFIC. When 'enable'=0 (DIP5 OFF) the
--   whole module is bypassed to raw v3.17, so the mask only matters when the
--   Alien Poker ROM is actually running with DIP5 ON.
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
--   DEBOUNCE_MASK: per column (index = strobe bit = matrix column - 1), a '1'
--     bit (index = return bit = matrix row - 1) means "debounce this switch".
--     Edit per game.

library ieee;
use ieee.std_logic_1164.all;

entity sw_debounce is
    generic (
        INTEG_MAX     : natural := 4;   -- integrator span: samples for a state change from settled (~8 ms)
        SETTLE_CYCLES : natural := 4    -- wait cycles after a strobe change before sampling
    );
    port (
        clk           : in  std_logic;                     -- cpu_clk (~894 kHz)
        i_Rst_L       : in  std_logic;                     -- reset_l (active low)
        enable        : in  std_logic;                     -- '1' = debounce (masked), '0' = raw passthrough (v3.17)
        sw_strobe     : in  std_logic_vector(7 downto 0);  -- one-hot column select (active high)
        sw_return_raw : in  std_logic_vector(7 downto 0);  -- raw returns from the pins (active high)
        sw_return_deb : out std_logic_vector(7 downto 0)   -- debounced/masked returns -> PIA2 pa_i
    );
end sw_debounce;

architecture Behavioral of sw_debounce is

    type deb_array is array (0 to 7) of std_logic_vector(7 downto 0);
    type intg_row   is array (0 to 7) of integer range 0 to INTEG_MAX;
    type intg_array is array (0 to 7) of intg_row;

    -- Per-switch debounce enable, indexed [column](row); '1' = debounce, '0' = raw.
    -- column index = strobe bit = (matrix column - 1); row/bit = (matrix row - 1).
    -- Game: Williams ALIEN POKER. Masked OFF (raw) = level/confirm-read + spinner + jets:
    --   Col2: 9 Outhole, 10 "A"drop, 13 LeftKicker, 15 SpadeAceEject
    --   Col3: 17 Spinner, 18 "K"drop, 22 ClubAceEject
    --   Col4: 26 "Q"drop, 29 HeartAceEject
    --   Col5: 34 "J"drop, 35..38 Jet bumpers
    --   Col6: 42 "10"drop
    -- Everything else (stand-ups, joker targets, rollovers, specials, cabinet,
    -- lane change) is debounced.
    constant DEBOUNCE_MASK : deb_array := (
        0 => x"FF",   -- Col1 sw 1-8   : cabinet (tilts/coin/credit/slam/hi-score reset)
        1 => x"AC",   -- Col2 sw 9-16  : raw bits 0,1,4,6 (9,10,13,15)
        2 => x"DC",   -- Col3 sw 17-24 : raw bits 0,1,5   (17,18,22)
        3 => x"ED",   -- Col4 sw 25-32 : raw bits 1,4     (26,29)
        4 => x"C1",   -- Col5 sw 33-40 : raw bits 1,2,3,4,5 (34,35,36,37,38)
        5 => x"05",   -- Col6 sw 41-48 : raw bit 1 (42); deb 41,43; 44-48 unused
        6 => x"00",   -- Col7 sw 49-56 : unused
        7 => x"00"    -- Col8 sw 57-64 : unused
    );

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
    outmux : process (enable, strobe_valid, col_idx_c, last_col, deb, sw_return_raw)
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
            elsif DEBOUNCE_MASK(ac)(r) = '1' then
                sw_return_deb(r) <= deb(ac)(r);
            else
                sw_return_deb(r) <= sw_return_raw(r);
            end if;
        end loop;
    end process;

end Behavioral;
