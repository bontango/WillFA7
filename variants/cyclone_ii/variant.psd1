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

    # THE ONLY VARIANT THAT DOES NOT BUILD top/WillFA7.vhd DIRECTLY.
    # Quartus 13.0sp1 Web Edition accepts VIRTUAL_PIN and then ignores it
    # ("Warning (292013): Feature Virtual IO is only available with a valid
    # subscription license", 'Total virtual pins: 0'), so the optional ports would be
    # placed and driven on real pins of the EP2C5 - which is what happened in the
    # released 1.21. The shell top/WillFA7_cii.vhd declares only the 82 ports this
    # board really has. Read that file before changing anything here.
    TopEntity   = 'WillFA7_cii'
    VirtualPins = @()

    Notes       = 'Quartus 13.0sp1. 94 % logic elements - check every addition with quartus_fit. 5 ROMs, 10 KByte SD image. Builds through the WillFA7_cii shell, VIRTUAL_PIN does not work here.'
}
