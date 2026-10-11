# Audit cocotb run. Copied by run_pre_tapeout_audit.sh to <npu1x1>/runs/audit/sim and run in the
# tools container, where the npu1x1 repo is mounted at /work and the PDK at /pdk.
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR ?= /work/src
PROJECT_SOURCES = project.v npu_array.v npu_pe.v dft/clk_gate.v

ifneq ($(GATES),yes)
SIM_BUILD        = sim_build/rtl
VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))
COMPILE_ARGS    += -DSIM
else
SIM_BUILD        = sim_build/gl
COMPILE_ARGS    += -DGL_TEST -DFUNCTIONAL -DUSE_POWER_PINS -DSIM -DUNIT_DELAY=\#1
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v
VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v
VERILOG_SOURCES += $(NETLIST)
endif

VERILOG_SOURCES += /work/test/tb.v
TOPLEVEL = tb
COCOTB_TEST_MODULES = audit_arith
MODULE = audit_arith
include $(shell cocotb-config --makefiles)/Makefile.sim
