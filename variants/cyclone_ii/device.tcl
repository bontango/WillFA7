# device.tcl - what is specific to THIS board, apart from the pin locations.
# Merged into WillFA7.qsf by scripts\gen_qsf.ps1. Hand maintained.
set_global_assignment -name FAMILY "Cyclone II"
set_global_assignment -name DEVICE EP2C5T144C8
set_global_assignment -name LAST_QUARTUS_VERSION "13.0 SP1"
set_global_assignment -name EDA_SIMULATION_TOOL "ModelSim-Altera (VHDL)"
set_global_assignment -name EDA_OUTPUT_DATA_FORMAT VHDL -section_id eda_simulation
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to reset_sw
