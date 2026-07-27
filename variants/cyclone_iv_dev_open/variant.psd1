@{
    Name        = 'cyclone_iv_dev_open'
    Title       = 'WillFA7 on an off-the-shelf Cyclone IV dev board (EP4CE6E22C8)'
    BoardId     = 5
    RtlFamily   = 'cyclone_iv'
    Options     = @()
    BinFolder   = 'dev_open'
    ReleaseArtifact = 'jic'
    Dormant     = $false
    VirtualPins = @('USB_Tx', 'USB_Rx', 'debug')   # LED_debug exists on this board
    Notes       = 'Aliexpress dev board. LED_debug shows reset_sw. reset_sw has no weak pull-up here.'
}
