# common_header.tcl - global assignments that are identical in all WillFA7
# variants. Merged into every generated WillFA7.qsf by scripts\gen_qsf.ps1.
#
# TOP_LEVEL_ENTITY is NOT here: cyclone_ii needs the board shell WillFA7_cii instead
# of WillFA7 (see top/WillFA7_cii.vhd). It comes from the TopEntity key in
# variants/<name>/variant.psd1, default WillFA7.
set_global_assignment -name ORIGINAL_QUARTUS_VERSION "13.0 SP1"
set_global_assignment -name PROJECT_CREATION_TIME_DATE "17:48:15  NOVEMBER 29, 2022"
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name MIN_CORE_JUNCTION_TEMP 0
set_global_assignment -name MAX_CORE_JUNCTION_TEMP 85
set_global_assignment -name ERROR_CHECK_FREQUENCY_DIVISOR 1
set_global_assignment -name POWER_PRESET_COOLING_SOLUTION "23 MM HEAT SINK WITH 200 LFPM AIRFLOW"
set_global_assignment -name POWER_BOARD_THERMAL_MODEL "NONE (CONSERVATIVE)"
set_global_assignment -name PARTITION_NETLIST_TYPE SOURCE -section_id Top
set_global_assignment -name PARTITION_FITTER_PRESERVATION_LEVEL PLACEMENT_AND_ROUTING -section_id Top
set_global_assignment -name PARTITION_COLOR 16764057 -section_id Top
set_global_assignment -name STRATIX_DEVICE_IO_STANDARD "3.3-V LVTTL"
set_global_assignment -name USE_CONFIGURATION_DEVICE ON
set_global_assignment -name RESERVE_ALL_UNUSED_PINS "AS INPUT TRI-STATED WITH WEAK PULL-UP"
set_global_assignment -name CYCLONEII_RESERVE_NCEO_AFTER_CONFIGURATION "USE AS REGULAR IO"
set_global_assignment -name RESERVE_ASDO_AFTER_CONFIGURATION "USE AS REGULAR IO"
set_global_assignment -name SYNTH_TIMING_DRIVEN_SYNTHESIS OFF
set_global_assignment -name AUTO_RAM_RECOGNITION ON
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to Diag_SW
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to Enter_SW
set_instance_assignment -name PARTITION_HIERARCHY root_partition -to | -section_id Top
