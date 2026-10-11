# Clock-gating checks on the row ICG GATE pins, async reset recovery/removal and unconstrained
# endpoints on the routed netlist. Env: LIB (liberty file name), SPEF (min|nom|max).
set P /pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib
read_liberty $P/$::env(LIB)
read_verilog /work/runs/wokwi/final/nl/tt_um_akln0401_npu.nl.v
link_design tt_um_akln0401_npu
read_spef /work/runs/wokwi/final/spef/$::env(SPEF)/tt_um_akln0401_npu.$::env(SPEF).spef
set ::env(CLOCK_PORT) clk
read_sdc /work/runs/wokwi/final/sdc/tt_um_akln0401_npu.sdc
foreach r {0 1} {
  set pin [get_pins "i_array.g_row\\\[$r\\\].i_cg.icg/GATE"]
  puts "--- row $r ICG GATE setup"; report_checks -to $pin -path_delay max -format end
  puts "--- row $r ICG GATE hold";  report_checks -to $pin -path_delay min -format end
}
puts "--- async reset recovery/removal"; report_checks -path_group asynchronous -path_delay min_max -format end
puts "--- unconstrained endpoints"; check_setup -unconstrained_endpoints
puts "--- end"
