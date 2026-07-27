-- version_pkg - the common function level of all WillFA7 board variants
-- Ralf Thelen 'bontango' - www.lisy.dev
--
-- The displayed version is BOARD_ID.SW_SUB1 SW_SUB2, for example 3.20:
--   BOARD_ID  first digit  - identifies the board, see variants/<name>/variant_pkg.vhd
--   SW_SUB1   second digit - common function level, set here
--   SW_SUB2   third digit  - common function level, set here
--
-- A release changes exactly one number in this file and every variant follows.
--
-- Function level history (see bin/changelog.txt for the full text):
--   .17  EEprom write robustness            .18  switch matrix debouncer
--   .19  special solenoid debounce via DIP4  .20  per game switch debounce masks
--   .21  monorepo: one shared top level, generated .qsf, no functional change
--
library ieee;
use ieee.std_logic_1164.all;

package version_pkg is
	constant SW_SUB1 : std_logic_vector(3 downto 0) := x"2";
	constant SW_SUB2 : std_logic_vector(3 downto 0) := x"0";
end package;
