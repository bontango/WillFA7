-- ARCHIV - NICHT IN EINEM PROJEKT EINGEBUNDEN
-- Dies ist der 'Confirm + Lockout'-Fork von sw_debounce, der bis 07.2026 nur in
-- 'WillFA7 - CycloneIV_dev_open' lag. Er wurde in Etappe 1 durch die Fassung aus
-- 'WillFA7 - CycloneIV_v4' (v3.20, per-switch MASK_ROM je Spiel, hardwareverifiziert)
-- ersetzt. Hier nur aufbewahrt, damit der Lockout-Algorithmus nachvollziehbar bleibt.
--
-- sw_debounce
-- Matrix-aware hardware debouncer for the Williams SYS7 switch matrix
-- bontango 07.2026 - part of WillFA7
--
-- Purpose:
--   The raw switch return lines (sw_return) come straight from the physical
--   pins and are read combinationally by PIA2 (pa_i). The FPGA input has no
--   analog integration, so mechanical contact bounce produces clean, fast
--   open/close edges that the ROM software debounce does not always filter,
--   causing occasional multiple triggers on a single actuation.
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
-- Algorithm (short confirm + per-switch refractory lockout):
--   - 2-FF synchronizer removes metastability of the async return pins.
--   - The active column is decoded from the one-hot strobe. On every strobe
--     change we wait SETTLE_CYCLES (async settle + sync-FF latency) and then
--     take exactly ONE sample of that column's 8 returns.
--   - Per switch: while the sampled value differs from the confirmed state a
--     counter climbs; it must reach CONFIRM_CYCLES consecutive samples before
--     the confirmed state flips. Any sample that matches the confirmed state
--     resets the counter.
--   - LOCKOUT: after a confirmed state CHANGE the switch enters a refractory
--     window of LOCKOUT_PASSES column visits during which further changes are
--     ignored. This decouples latency from bounce suppression: a change is
--     accepted fast (CONFIRM_CYCLES scans, ~2.3 ms at 2), while the mechanical
--     settle bounce that FOLLOWS the change (e.g. drop targets slamming up on
--     a bank reset) falls into the blind window and can neither delay the
--     confirmation nor be laundered into a clean fake event for the ROM.
--     Discriminator is event history (bounce always follows a switch's own
--     recent transition), not duration.
--   - The output is deb(current column), muxed immediately by the current
--     strobe. The read path has NO added latency; only a CHANGE of a switch
--     needs CONFIRM_CYCLES scans to propagate -> exactly the debounce we want,
--     without delaying the ROM's strobe->return scan relationship.
--
-- Tuning:
--   One column visit ~= one ROM matrix scan ~= 1.15 ms (873 Hz IRQ).
--   CONFIRM_CYCLES: change-accept latency (2 -> ~2.3 ms). Lower to 1 if fast
--     stand-up hits are still missed; raising it is rarely needed since the
--     lockout does the bounce suppression.
--   LOCKOUT_PASSES: blind time after an accepted change (17 -> ~19.5 ms).
--     Raise (26 -> ~30 ms) if target banks still get reset twice; lower
--     (9 -> ~10 ms) if spinners / fast repeating switches lose counts.
--   Keep SETTLE_CYCLES >= 2 so the 2-FF synchronizer has settled before
--   sampling.

library ieee;
use ieee.std_logic_1164.all;

entity sw_debounce is
    generic (
        CONFIRM_CYCLES : natural := 2;   -- consecutive per-column samples to accept a change
        SETTLE_CYCLES  : natural := 4;   -- wait cycles after a strobe change before sampling
        LOCKOUT_PASSES : natural := 17   -- refractory column visits after an accepted change (~19.5 ms)
    );
    port (
        clk           : in  std_logic;                     -- cpu_clk (~894 kHz)
        i_Rst_L       : in  std_logic;                     -- reset_l (active low)
        sw_strobe     : in  std_logic_vector(7 downto 0);  -- one-hot column select (active high)
        sw_return_raw : in  std_logic_vector(7 downto 0);  -- raw returns from the pins (active high)
        sw_return_deb : out std_logic_vector(7 downto 0)   -- debounced returns -> PIA2 pa_i
    );
end sw_debounce;

architecture Behavioral of sw_debounce is

    type deb_array is array (0 to 7) of std_logic_vector(7 downto 0);
    type cnt_row   is array (0 to 7) of integer range 0 to CONFIRM_CYCLES;
    type cnt_array is array (0 to 7) of cnt_row;
    type lock_row   is array (0 to 7) of integer range 0 to LOCKOUT_PASSES;
    type lock_array is array (0 to 7) of lock_row;

    -- confirmed (debounced) switch states, indexed [column](row); '1' = closed
    signal deb : deb_array := (others => (others => '0'));
    -- per switch agreement counter
    signal cnt : cnt_array := (others => (others => 0));
    -- per switch refractory (lockout) down-counter, ticks once per column visit
    signal lock : lock_array := (others => (others => 0));

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
    -- sample & debounce
    ---------------------------------------------------------------
    sample : process (clk, i_Rst_L)
    begin
        if i_Rst_L = '0' then
            deb         <= (others => (others => '0'));
            cnt         <= (others => (others => 0));
            lock        <= (others => (others => 0));
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
                        if lock(col_idx_c)(r) > 0 then
                            -- refractory: ignore changes, count the blind window down
                            lock(col_idx_c)(r) <= lock(col_idx_c)(r) - 1;
                            cnt(col_idx_c)(r)  <= 0;
                        elsif sync2(r) /= deb(col_idx_c)(r) then
                            if cnt(col_idx_c)(r) + 1 >= CONFIRM_CYCLES then
                                deb(col_idx_c)(r)  <= sync2(r);
                                cnt(col_idx_c)(r)  <= 0;
                                lock(col_idx_c)(r) <= LOCKOUT_PASSES;  -- start blind window
                            else
                                cnt(col_idx_c)(r) <= cnt(col_idx_c)(r) + 1;
                            end if;
                        else
                            cnt(col_idx_c)(r) <= 0;
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
    -- output: debounced returns of the currently strobed column
    -- (immediate mux, no added latency in the read path)
    ---------------------------------------------------------------
    sw_return_deb <= deb(col_idx_c) when strobe_valid = '1' else deb(last_col);

end Behavioral;
