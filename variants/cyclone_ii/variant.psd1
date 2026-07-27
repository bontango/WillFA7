@{
    # WillFA7 board variant metadata. Read by scripts\gen_qsf.ps1 and scripts\check.ps1.
    # The single source of truth for what goes into the generated WillFA7.qsf.
    Name        = 'cyclone_ii'
    Title       = 'WillFA7 Cyclone II (EP2C5T144C8)'
    BoardId     = 1               # first digit of the displayed version, see variant_pkg.vhd
    RtlFamily   = 'cyclone_ii'    # which rtl/<family>/ folder supplies the megafunctions
    Options     = @()             # 'serial_api' and/or 'sound'
    BinFolder   = 'Cyclone_II'
    ReleaseArtifact = 'pof'   # EPCS4, programmed straight from the compile output
    Dormant     = $false
    # Optional top level ports this board does NOT have. They stay in the port list
    # and get VIRTUAL_PIN so Quartus does not place and drive them on a real pin.
    VirtualPins = @('LED_debug', 'USB_Tx', 'USB_Rx', 'debug')
    Notes       = 'Quartus 13.0sp1. 95 % logic elements - check every addition with quartus_fit. 5 ROMs, 10 KByte SD image.'
}
