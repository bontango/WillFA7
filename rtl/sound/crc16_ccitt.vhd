-------------------------------------------------------------------------------
-- Copyright (C) 2009 OutputLogic.com
-- This source file may be used and distributed without restriction
-- provided that this copyright statement is not removed from the file
-- and that any derivative work contains the original copyright notice
-- and the associated disclaimer.
--
-- THIS SOURCE FILE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS
-- OR IMPLIED WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED
-- WARRANTIES OF MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.
-------------------------------------------------------------------------------
-- CRC module for data(7:0)
--   lfsr(15:0)=1+x^2+x^15+x^16;
-------------------------------------------------------------------------------
-- adapted to crc16_citt by bontango
-- with the help of 'CRC generator' https://bues.ch/cms/hacking/crcgen.html
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity crc16_ccitt is
  port ( data_in : in std_logic_vector (7 downto 0);
    crc_en , rst, clk : in std_logic;
    crc_out : out std_logic_vector (15 downto 0));
end crc16_ccitt;

architecture imp_crc of crc16_ccitt is
  signal lfsr_q: std_logic_vector (15 downto 0);
  signal lfsr_c: std_logic_vector (15 downto 0);
begin
    crc_out <= lfsr_q;

    lfsr_c(0) <= data_in(0) xor data_in(4) xor lfsr_q(8) xor lfsr_q(12);
    lfsr_c(1) <= data_in(1) xor data_in(5) xor lfsr_q(9) xor lfsr_q(13);
    lfsr_c(2) <= data_in(2) xor data_in(6) xor lfsr_q(10) xor lfsr_q(14);
    lfsr_c(3) <= data_in(3) xor data_in(7) xor lfsr_q(11) xor lfsr_q(15);
    lfsr_c(4) <= data_in(4) xor lfsr_q(12);
    lfsr_c(5) <= data_in(0) xor data_in(4) xor data_in(5) xor lfsr_q(8) xor lfsr_q(12) xor lfsr_q(13);
    lfsr_c(6) <= data_in(1) xor data_in(5) xor data_in(6) xor lfsr_q(9) xor lfsr_q(13) xor lfsr_q(14);
    lfsr_c(7) <= data_in(2) xor data_in(6) xor data_in(7) xor lfsr_q(10) xor lfsr_q(14) xor lfsr_q(15);
    lfsr_c(8) <= data_in(3) xor data_in(7) xor lfsr_q(0) xor lfsr_q(11) xor lfsr_q(15);
    lfsr_c(9) <= data_in(4) xor lfsr_q(1) xor lfsr_q(12);
    lfsr_c(10) <= data_in(5) xor lfsr_q(2) xor lfsr_q(13);
    lfsr_c(11) <= data_in(6) xor lfsr_q(3) xor lfsr_q(14);
    lfsr_c(12) <= data_in(0) xor data_in(4) xor data_in(7) xor lfsr_q(4) xor lfsr_q(8) xor lfsr_q(12) xor lfsr_q(15);
    lfsr_c(13) <= data_in(1) xor data_in(5) xor lfsr_q(5) xor lfsr_q(9) xor lfsr_q(13);
    lfsr_c(14) <= data_in(2) xor data_in(6) xor lfsr_q(6) xor lfsr_q(10) xor lfsr_q(14);
    lfsr_c(15) <= data_in(3) xor data_in(7) xor lfsr_q(7) xor lfsr_q(11) xor lfsr_q(15);
	 
    process (clk,rst) begin
      if (rst = '0') then
        lfsr_q <= b"1111111111111111";
      elsif (clk'EVENT and clk = '1') then
        if (crc_en = '1') then
          lfsr_q <= lfsr_c;
        end if;
      end if;
    end process;
end architecture imp_crc;