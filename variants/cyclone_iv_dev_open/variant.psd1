@{
    Name        = 'cyclone_iv_dev_open'
    Title       = 'WillFA7 on an off-the-shelf Cyclone IV dev board (EP4CE6E22C8)'
    BoardId     = 5
    RtlFamily   = 'cyclone_iv'
    Options     = @()
    BinFolder   = 'dev_open'
    ReleaseArtifact = 'jic'
    Dormant     = $false
    VirtualPins = @('USB_Tx', 'USB_Rx', 'debug',   # LED_debug exists on this board
                    'SB_Sound', 'SB_Speech', 'SB_Test', 'Dip_Ret_4')
    # Board wiring worth keeping, it used to be a comment in this variant's own copy of
    # the top level: the four dev board LEDs are D5 = LED_SD_Error (IO98),
    # D4 = LED_active (IO99), D3 = LED_status (IO100), D2 = LED_debug (IO101); reset is
    # S2 (IO90). LED_active looks like a plain LED here but carries the blanking line
    # once the board sits on a WillFA7 PCB - see docs/blanking_led_active.md.
    Notes       = 'Aliexpress dev board. LED_debug shows reset_sw. reset_sw has no weak pull-up here.'
}
