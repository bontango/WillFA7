# Shared source files - part of every WillFA7 variant.
# Paths are relative to the Quartus project directory, which is variants/<name>/.
# The packages come first so the analyser never has to guess the order.
set_global_assignment -name VHDL_FILE variant_pkg.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/version_pkg.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/game_pkg.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/AM8T28.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/boot_message.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/byte_to_decimal.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/count_to_zero.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/cpu68.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/cpu_clk_gen.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/detect_sw.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/EEprom.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/flipflops.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/irq_generator.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/one_pulse_only.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/peak_filter.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/pia6821.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/read_the_dips.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/SD_Card.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/slow_to_fast_clock.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/spec_sol_trigger.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/SPI_Master.vhd
set_global_assignment -name VHDL_FILE ../../rtl/common/sw_debounce.vhd
# The serial monitor is instantiated inside 'if HAS_MONITOR generate' and only exists
# on the v3 board. The files are nevertheless part of EVERY variant: Quartus resolves
# entity references in a NOT taken generate branch as well and errors with 10481
# otherwise. Nothing is synthesised from them where HAS_MONITOR is false.
set_global_assignment -name VHDL_FILE ../../rtl/serial_api/WillFA7_Monitor.vhd
set_global_assignment -name VHDL_FILE ../../rtl/serial_api/uart_tx.vhd
set_global_assignment -name VHDL_FILE ../../rtl/serial_api/uart_rx.vhd
# Same story for the sound board sources: they sit inside 'if HAS_SOUND generate' in
# the top level and inside 'if Check_CRC generate' in SD_Card, and Quartus resolves
# entity references in a not taken branch as well. Nothing is synthesised from them
# where HAS_SOUND is false - which is what the baseline check proves.
#
# The two sound board memories are inferred VHDL rather than megafunctions for
# exactly this reason: they would otherwise have to be Cyclone IV E megafunctions in
# the Cyclone II and Cyclone 10 projects as well. See rtl/sound/MPU_RAM.vhd.
set_global_assignment -name VHDL_FILE ../../rtl/sound/crc16_ccitt.vhd
set_global_assignment -name VHDL_FILE ../../rtl/sound/dac.vhd
set_global_assignment -name VHDL_FILE ../../rtl/sound/hc55564.vhd
set_global_assignment -name VHDL_FILE ../../rtl/sound/MPU_RAM.vhd
set_global_assignment -name VHDL_FILE ../../rtl/sound/read_the_dips_s.vhd
set_global_assignment -name VHDL_FILE ../../rtl/sound/SB_ROM.vhd
set_global_assignment -name VHDL_FILE ../../rtl/sound/slow_to_fast_clock_bus.vhd
set_global_assignment -name VHDL_FILE ../../rtl/sound/soundtest.vhd
set_global_assignment -name VHDL_FILE ../../rtl/sound/WISOF.vhd
set_global_assignment -name VHDL_FILE ../../top/WillFA7.vhd
# Board shell for cyclone_ii, where VIRTUAL_PIN does not work (Quartus 13.0sp1 Web
# Edition). It is the top level entity only there, but it is analysed in EVERY
# variant on purpose: a port added to WillFA7 and forgotten in the shell then breaks
# every build loudly instead of breaking Cyclone II silently. Costs 0 logic elements
# where it is not the top level.
set_global_assignment -name VHDL_FILE ../../top/WillFA7_cii.vhd
set_global_assignment -name SDC_FILE WillFA7.sdc
