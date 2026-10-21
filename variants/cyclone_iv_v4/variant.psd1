@{
    Name        = 'cyclone_iv_v4'
    Title       = 'WillFA7 Cyclone IV board v4.x (EP4CE6E22C8)'
    BoardId     = 3
    RtlFamily   = 'cyclone_iv'
    Options     = @()
    BinFolder   = 'Cyclone_IV\FPGA_board_v4.x'
    ReleaseArtifact = 'jic'
    Dormant     = $false
    VirtualPins = @('LED_debug', 'USB_Tx', 'USB_Rx', 'debug',
                    'SB_Sound', 'SB_Speech', 'SB_Test', 'Dip_Ret_4')
    Notes       = 'Lead variant - development and hardware testing happen here.'
}
