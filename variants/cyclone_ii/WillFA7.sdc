## Generated SDC file "WillFA7.out.sdc"

## Copyright (C) 1991-2013 Altera Corporation
## Your use of Altera Corporation's design tools, logic functions 
## and other software and tools, and its AMPP partner logic 
## functions, and any output files from any of the foregoing 
## (including device programming or simulation files), and any 
## associated documentation or information are expressly subject 
## to the terms and conditions of the Altera Program License 
## Subscription Agreement, Altera MegaCore Function License 
## Agreement, or other applicable license agreement, including, 
## without limitation, that your use is for the sole purpose of 
## programming logic devices manufactured by Altera and sold by 
## Altera or its authorized distributors.  Please refer to the 
## applicable agreement for further details.


## VENDOR  "Altera"
## PROGRAM "Quartus II"
## VERSION "Version 13.0.1 Build 232 06/12/2013 Service Pack 1 SJ Web Edition"

## DATE    "Sat Dec 23 16:45:11 2023"

##
## DEVICE  "EP2C5T144C8"
##

## HAND EDITED since .22: this variant builds through the board shell
## WillFA7_cii (see top/WillFA7_cii.vhd), which adds one level of hierarchy.
## Every node below it is therefore addressed as 'WillFA7:CORE|...'.
## A constraint that no longer matches is dropped SILENTLY - the check is that
## the worst case slack stays where scripts/baseline.csv says it is.
##
## Note the asymmetry, it is not a typo: get_registers wants the entity:label
## form 'WillFA7:CORE|...', while the PLL is addressed by its SDC pin name,
## which is instance labels only - 'CORE|PLL|altpll_component|pll'. The fitter
## report prints that name under 'SDC pin name'.


#**************************************************************
# Time Information
#**************************************************************

set_time_format -unit ns -decimal_places 3



#**************************************************************
# Create Clock
#**************************************************************

create_clock -name {clk_50} -period 20.000 -waveform { 0.000 10.000 } [get_ports {clk_50}]
#create_clock -name {cpu_clk_gen:clock_gen|clk_out} -period 1.000 -waveform { 0.000 0.500 } [get_registers {WillFA7:CORE|cpu_clk_gen:clock_gen|clk_out}]
#create_clock -name {cpu_clk_gen:clock_gen|shift_clk_out} -period 1.000 -waveform { 0.000 0.500 } [get_registers {WillFA7:CORE|cpu_clk_gen:clock_gen|shift_clk_out}]
create_clock -name {cpu_clk_gen:clock_gen|clk_out} -period 1000.000 -waveform { 0.000 500.00 } [get_registers {WillFA7:CORE|cpu_clk_gen:clock_gen|clk_out}]
create_clock -name {cpu_clk_gen:clock_gen|shift_clk_out} -period 1000.000 -waveform { 0.000 500.000 } [get_registers {WillFA7:CORE|cpu_clk_gen:clock_gen|shift_clk_out}]


#**************************************************************
# Create Generated Clock
#**************************************************************

create_generated_clock -name {PLL|altpll_component|pll|clk[0]} -source [get_pins {CORE|PLL|altpll_component|pll|inclk[0]}] -duty_cycle 50.000 -multiply_by 2 -divide_by 7 -master_clock {clk_50} [get_pins {CORE|PLL|altpll_component|pll|clk[0]}] 

#**************************************************************
# Set Clock Latency
#**************************************************************



#**************************************************************
# Set Clock Uncertainty
#**************************************************************



#**************************************************************
# Set Input Delay
#**************************************************************



#**************************************************************
# Set Output Delay
#**************************************************************



#**************************************************************
# Set Clock Groups
#**************************************************************



#**************************************************************
# Set False Path
#**************************************************************



#**************************************************************
# Set Multicycle Path
#**************************************************************



#**************************************************************
# Set Maximum Delay
#**************************************************************



#**************************************************************
# Set Minimum Delay
#**************************************************************



#**************************************************************
# Set Input Transition
#**************************************************************

