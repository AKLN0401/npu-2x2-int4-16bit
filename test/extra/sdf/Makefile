# SDF back-annotated gate-level sim of the 1x1 NPU: the cocotb tests of test/ (copied here) on the
# post-PnR netlist with timing cell models (patched, see patch_lib.py) and one corner's SDF.
# Usage: make CORNER=max_ss_n40C_1v60   (timing checks are not evaluated by Icarus)
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
CORNER ?= nom_tt_025C_1v80
SIM_BUILD = sim_build/$(CORNER)
GATES = yes
export GATES
SDF = /work/runs/sdf/sdf_fixed/$(CORNER).sdf
COMPILE_ARGS += -DGL_TEST -DUSE_POWER_PINS -gspecify -DSDF_FILE=\"$(SDF)\"
VERILOG_SOURCES = $(PWD)/primitives.v $(PWD)/sky130_fd_sc_hd_sdf.v $(PWD)/gate_level_netlist.v $(PWD)/tb.v
TOPLEVEL = tb
COCOTB_TEST_MODULES = test
MODULE = test
include $(shell cocotb-config --makefiles)/Makefile.sim
