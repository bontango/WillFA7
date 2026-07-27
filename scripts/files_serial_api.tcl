# Option 'serial_api' - the USB monitor API. Costs about 550 logic elements, so
# it is only pulled in where variant.psd1 asks for it (today: cyclone_iv_v3).
set_global_assignment -name VHDL_FILE ../../rtl/serial_api/WillFA7_Monitor.vhd
set_global_assignment -name VHDL_FILE ../../rtl/serial_api/uart_tx.vhd
set_global_assignment -name VHDL_FILE ../../rtl/serial_api/uart_rx.vhd
