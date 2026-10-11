# Vector-based power: routed netlist + SPEF + VCD activity. Env: VCD, LIB, SPEF
set P /pdk/sky130A/libs.ref/sky130_fd_sc_hd/lib
read_liberty $P/$::env(LIB)
read_verilog /work/runs/wokwi/final/nl/tt_um_akln0401_npu.nl.v
link_design tt_um_akln0401_npu
read_spef /work/runs/wokwi/final/spef/$::env(SPEF)/tt_um_akln0401_npu.$::env(SPEF).spef
set ::env(CLOCK_PORT) clk
read_sdc /work/runs/wokwi/final/sdc/tt_um_akln0401_npu.sdc
read_vcd -scope ptb/user_project $::env(VCD)
puts "--- annotation"; report_activity_annotation
puts "--- power"; report_power -digits 6
puts "--- top instances"; report_power -highest_power_instances 12 -digits 6
