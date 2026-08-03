# pins.tcl - pin locations for THIS board. Merged into WillFA7.qsf by
# scripts\gen_qsf.ps1. This is the truth about the board, not the comments in
# the VHDL port list. Hand maintained.
#
# 78 of the 82 lines are identical to variants/cyclone_iv_v4/pins.tcl. What the
# integrated sound board changes:
#   PIN_34  DIP_Str_2 -> SB_Sound
#   PIN_39  DIP_Str_4 -> SB_Speech
#   PIN_42  DIP_Str_3 -> SB_Test
#   PIN_38  DIP_Str_1 -> unused on this board
#   PIN_11  (free)    -> Dip_Ret_4
# With the dedicated DIP strobe pins gone the strobes are multiplexed onto
# sw_strobe(7,5,3,1) during boot phase 1 and a fourth return line is read instead,
# which turns the 4x3 DIP matrix into 4x4. See docs/soundcard_variant.md.
set_location_assignment PIN_23 -to clk_50
set_location_assignment PIN_43 -to CS_EEprom
set_location_assignment PIN_7 -to CS_SDcard
set_location_assignment PIN_115 -to disp_bcd[7]
set_location_assignment PIN_119 -to disp_bcd[6]
set_location_assignment PIN_120 -to disp_bcd[5]
set_location_assignment PIN_121 -to disp_bcd[4]
set_location_assignment PIN_124 -to disp_bcd[3]
set_location_assignment PIN_125 -to disp_bcd[2]
set_location_assignment PIN_126 -to disp_bcd[1]
set_location_assignment PIN_127 -to disp_bcd[0]
set_location_assignment PIN_133 -to disp_strobe[3]
set_location_assignment PIN_132 -to disp_strobe[2]
set_location_assignment PIN_129 -to disp_strobe[1]
set_location_assignment PIN_128 -to disp_strobe[0]
set_location_assignment PIN_72 -to lamp_row_sel
set_location_assignment PIN_71 -to lamp_strobe_sel
set_location_assignment PIN_136 -to lamps[7]
set_location_assignment PIN_137 -to lamps[6]
set_location_assignment PIN_143 -to lamps[5]
set_location_assignment PIN_73 -to lamps[4]
set_location_assignment PIN_74 -to lamps[3]
set_location_assignment PIN_138 -to lamps[2]
set_location_assignment PIN_141 -to lamps[1]
set_location_assignment PIN_135 -to lamps[0]
set_location_assignment PIN_2 -to MISO
set_location_assignment PIN_31 -to MOSI
set_location_assignment PIN_99 -to sol_1_8_sel
set_location_assignment PIN_100 -to sol_9_16_sel
set_location_assignment PIN_98 -to sol_spec_sel
set_location_assignment PIN_111 -to solenoids[7]
set_location_assignment PIN_110 -to solenoids[6]
set_location_assignment PIN_104 -to solenoids[5]
set_location_assignment PIN_101 -to solenoids[4]
set_location_assignment PIN_103 -to solenoids[3]
set_location_assignment PIN_105 -to solenoids[2]
set_location_assignment PIN_106 -to solenoids[1]
set_location_assignment PIN_112 -to solenoids[0]
set_location_assignment PIN_30 -to SPI_CLK
set_location_assignment PIN_60 -to sw_return[7]
set_location_assignment PIN_64 -to sw_return[6]
set_location_assignment PIN_65 -to sw_return[5]
set_location_assignment PIN_66 -to sw_return[4]
set_location_assignment PIN_67 -to sw_return[3]
set_location_assignment PIN_68 -to sw_return[2]
set_location_assignment PIN_69 -to sw_return[1]
set_location_assignment PIN_70 -to sw_return[0]
set_location_assignment PIN_44 -to sw_strobe[7]
set_location_assignment PIN_49 -to sw_strobe[6]
set_location_assignment PIN_46 -to sw_strobe[5]
set_location_assignment PIN_51 -to sw_strobe[4]
set_location_assignment PIN_50 -to sw_strobe[3]
set_location_assignment PIN_53 -to sw_strobe[2]
set_location_assignment PIN_52 -to sw_strobe[1]
set_location_assignment PIN_54 -to sw_strobe[0]
set_location_assignment PIN_24 -to Dip_Ret_3
set_location_assignment PIN_25 -to Dip_Ret_2
set_location_assignment PIN_28 -to Dip_Ret_1
set_location_assignment PIN_55 -to Mem_prot
set_location_assignment PIN_58 -to Advance
set_location_assignment PIN_59 -to up_down
set_location_assignment PIN_88 -to SPC_Sol_Trig[2]
set_location_assignment PIN_89 -to SPC_Sol_Trig[3]
set_location_assignment PIN_90 -to SPC_Sol_Trig[4]
set_location_assignment PIN_91 -to SPC_Sol_Trig[1]
set_location_assignment PIN_113 -to SPC_Sol_Trig[5]
set_location_assignment PIN_114 -to SPC_Sol_Trig[6]
set_location_assignment PIN_144 -to reset_sw
set_location_assignment PIN_3 -to LED_active
set_location_assignment PIN_1 -to LED_SD_Error
set_location_assignment PIN_10 -to LED_status
set_location_assignment PIN_77 -to Diag_SW
set_location_assignment PIN_76 -to Enter_SW
set_location_assignment PIN_142 -to sound_com_sel
set_location_assignment PIN_87 -to W_PA_DIP[0]
set_location_assignment PIN_80 -to W_PA_DIP[1]
set_location_assignment PIN_83 -to W_PA_DIP[2]
set_location_assignment PIN_86 -to W_PA_DIP[3]
set_location_assignment PIN_39 -to SB_Speech
set_location_assignment PIN_34 -to SB_Sound
set_location_assignment PIN_11 -to Dip_Ret_4
set_location_assignment PIN_42 -to SB_Test
