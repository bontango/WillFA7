# device.tcl - what is specific to THIS board, apart from the pin locations.
# Merged into WillFA7.qsf by scripts\gen_qsf.ps1. Hand maintained.
set_global_assignment -name FAMILY "Cyclone IV E"
set_global_assignment -name DEVICE EP4CE6E22C8
set_global_assignment -name LAST_QUARTUS_VERSION "22.1std.2 Lite Edition"
set_global_assignment -name NUM_PARALLEL_PROCESSORS ALL
set_global_assignment -name EDA_SIMULATION_TOOL "<None>"
set_global_assignment -name EDA_OUTPUT_DATA_FORMAT NONE -section_id eda_simulation
set_instance_assignment -name WEAK_PULL_UP_RESISTOR OFF -to reset_sw
set_global_assignment -name EDA_GENERATE_FUNCTIONAL_NETLIST OFF -section_id eda_board_design_timing
set_global_assignment -name EDA_GENERATE_FUNCTIONAL_NETLIST OFF -section_id eda_board_design_symbol
set_global_assignment -name EDA_GENERATE_FUNCTIONAL_NETLIST OFF -section_id eda_board_design_signal_integrity
set_global_assignment -name EDA_GENERATE_FUNCTIONAL_NETLIST OFF -section_id eda_board_design_boundary_scan

# The configuration flash is the second source of the game ROMs (HAS_FLASH_ROM, see
# rtl/common/Flash_ROM.vhd), so its pins have to become ordinary I/O once the FPGA is
# configured. ASDO is already released for every board in scripts/common_header.tcl.
set_global_assignment -name RESERVE_DATA0_AFTER_CONFIGURATION "USE AS REGULAR IO"
set_global_assignment -name RESERVE_DATA1_AFTER_CONFIGURATION "USE AS REGULAR IO"
set_global_assignment -name RESERVE_FLASH_NCE_AFTER_CONFIGURATION "USE AS REGULAR IO"
set_global_assignment -name RESERVE_DCLK_AFTER_CONFIGURATION "USE AS REGULAR IO"
