@{
    # WillFA7 board variant metadata. Read by scripts\gen_qsf.ps1 and scripts\check.ps1.
    # The single source of truth for what goes into the generated WillFA7.qsf.
    Name        = 's_cyclone_iv_v4'
    Title       = 'WillFA7S HW1.0 with sound board, Cyclone IV (EP4CE10E22C8)'
    BoardId     = 6               # first digit of the displayed version, see variant_pkg.vhd
    RtlFamily   = 'cyclone_iv'    # which rtl/<family>/ folder supplies the megafunctions
    Options     = @()             # the sound board is NOT a file list option: it hangs on
                                  # HAS_SOUND in variant_pkg.vhd, and its sources are part
                                  # of every variant anyway because Quartus resolves entity
                                  # references in a not taken generate branch too.
                                  # See scripts\files_common.tcl.
    BinFolder   = 'WillFA7S'
    ReleaseArtifact = 'jic'
    Dormant     = $false

    # Since 6.21 this is an ordinary variant: same top/WillFA7.vhd, same rtl/common/,
    # same WillFA7.sdc as the lead variant, generated .qsf. Everything the sound board
    # changes is collected in docs/soundcard_variant.md.
    VirtualPins = @('LED_debug', 'USB_Tx', 'USB_Rx', 'debug',
                    # The sound board took these four pins for SB_Sound, SB_Speech and
                    # SB_Test; the DIP matrix borrows sw_strobe and a fourth return
                    # line instead.
                    'DIP_Str_1', 'DIP_Str_2', 'DIP_Str_3', 'DIP_Str_4')

    Notes       = 'EP4CE10 for the memory, not the logic: five 4 KByte sound ROMs are 163,840 bits on top. Needs a 64 KByte per game SD image with a CRC16 - a standard card does not boot here, and this card does not boot on a standard board.'
}
