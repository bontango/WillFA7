@{
    Name        = 'cyclone_iv_v3'
    Title       = 'WillFA7 Cyclone IV board v3.x (EP4CE6F17C8)'
    BoardId     = 2
    RtlFamily   = 'cyclone_iv'
    Options     = @('serial_api')   # the only variant carrying the USB monitor API
    Dormant     = $false
    VirtualPins = @('LED_debug')
    Notes       = 'The serial monitor costs about 550 logic elements.'
}
