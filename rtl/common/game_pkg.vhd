-- game_pkg - properties that depend on the selected game
-- part of WillFA7, bontango 08.2026
--
-- Everything the design has to know about a game that is neither in its ROM image nor
-- big enough for a table of its own. The switch debounce mask is the one exception: it
-- is 8 bytes per game and lives in its own M9K block, see rtl/common/sw_debounce.vhd.
--
-- The argument is always the GAME NUMBER 0..63, that is 'not game_select' - the DIPs
-- are active low. Same numbering as the SD card slot, the EEprom page and the debounce
-- mask (see 'game_no' in WillFA7.vhd). Numbers 32..63 cannot be reached: S1-Dip6 is
-- unused, the game select tables in both user manuals stop at 31. Their entries are
-- there so an unexpected value falls back to the harmless case.
--
-- The game list itself is in docs/display_layout.md (display type) and in appendix A of
-- the two user manuals (names and DIP settings).

LIBRARY ieee;
USE ieee.std_logic_1164.all;

package game_pkg is

    -- '1' when the game runs on SEVEN digit player displays.
    function has_7digit (game_no : std_logic_vector(5 downto 0)) return std_logic;

    -- '1' for a System 3 or System 4 game. Those have no coin door memory protection,
    -- and on a sound board they drive the sound lines from solenoids 9..13.
    function is_system3 (game_no : std_logic_vector(5 downto 0)) return std_logic;

end package game_pkg;

LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

package body game_pkg is

    -- Seven digit player displays. Williams switched with the last two System 6 games:
    -- 16 Algar and 17 Alien Poker (the 'SYS6A' rows in appendix A) already have them,
    -- and so does every System 7 game, 18 Black Knight to 31 Star Light. Games 0..15,
    -- Hot Tip to Scorpion, are six digit.
    -- Source: PinMAME s6games.c (algar and alpok use s6_7digit_disp), s7games.c
    -- (s7_dispS7 is the default for System 7). What that means for the digit strobes is
    -- in docs/display_layout.md - and 16/17 is the one row still to be checked on real
    -- hardware.
    constant DISP_7DIGIT : std_logic_vector(0 to 63) :=
        "0000000000000000" &   --  0..15  Hot Tip .. Scorpion
        "1111111111111111" &   -- 16..31  Algar, Alien Poker, all System 7
        "0000000000000000" &   -- 32..47  no game
        "0000000000000000";    -- 48..63  no game

    -- System 3 and System 4: 0 Hot Tip .. 8 Stellar Wars. From 9 Tri Zone on it is
    -- System 6 or 7. Same boundary docs/CHANGES_v3.16.md uses.
    constant GAME_SYS34 : std_logic_vector(0 to 63) :=
        "1111111110000000" &   --  0..15  Hot Tip .. Stellar Wars are SYS3/4, from Tri Zone not
        "0000000000000000" &   -- 16..31
        "0000000000000000" &   -- 32..47  no game
        "0000000000000000";    -- 48..63  no game

    function has_7digit (game_no : std_logic_vector(5 downto 0)) return std_logic is
    begin
        return DISP_7DIGIT(to_integer(unsigned(game_no)));
    end function;

    function is_system3 (game_no : std_logic_vector(5 downto 0)) return std_logic is
    begin
        return GAME_SYS34(to_integer(unsigned(game_no)));
    end function;

end package body game_pkg;
