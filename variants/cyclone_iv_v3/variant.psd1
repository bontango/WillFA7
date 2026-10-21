@{
    Name        = 'cyclone_iv_v3'
    Title       = 'WillFA7 Cyclone IV board v3.x (EP4CE6F17C8)'
    BoardId     = 2
    RtlFamily   = 'cyclone_iv'
    Options     = @()   # 'sound' only; the monitor is decided by HAS_MONITOR in variant_pkg.vhd
    BinFolder   = 'Cyclone_IV\FPGA_board_v3.x'
    ReleaseArtifact = 'jic'
    Dormant     = $false
    VirtualPins = @('LED_debug',
                    'SB_Sound', 'SB_Speech', 'SB_Test', 'Dip_Ret_4')
    Notes       = 'The serial monitor costs about 550 logic elements.'
}
