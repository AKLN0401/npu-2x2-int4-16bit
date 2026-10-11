read_sdc $::env(SCRIPTS_DIR)/base.sdc

# Add duty cycle uncertainty - due to the high capacitance of the TT mux
# we're pretty uncertain about the duty cycle
set_clock_uncertainty 2.5 -rise_from clk -fall_to clk
set_clock_uncertainty 2 -fall_from clk -rise_to clk

# Fix reset delay
set_input_delay 1.5 -clock [get_clocks $::env(CLOCK_PORT)] {rst_n}

# Host interface (ui_in data, uio_in[2:0] address, uio_in[3] write strobe, uo_out read data):
# asynchronous to clk. The strobe goes through a 2-flop synchronizer; address and data are held
# stable >= 4 clk around the synchronized edge, and the host reads uo_out after it settles.
# So these keep the default IO delay from the base SDC above (IO_DELAY_CONSTRAINT, 20% of the
# period): it only keeps the paths short, it is not a real interface timing.

# DFT pins (uio[4] test_mode, uio[5] scan_en, uio[6] scan_in) are static during normal operation;
# on the bench they are changed with the clock slow or stopped. Same for scan_out (uio[7]).
set_false_path -from [get_ports {uio_in[4] uio_in[5] uio_in[6]}]
set_false_path -to [get_ports {uio_out[7]}]

set_propagated_clock [all_clocks]
