/*
 * Copyright (c) 2026 AKLN0401
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Glitch-free clock gate. All clock gating in the design goes through this module.
// test_en forces the clock on so every flop is clocked during scan shift.
module clk_gate (
    input  wire clk,
    input  wire en,       // sampled while clk is low
    input  wire test_en,  // scan/test mode: clock always on
    output wire gclk
);

`ifdef SIM
    // Behavioural model of a latch-based ICG (RTL sim only)
    reg en_latched;
    /* verilator lint_off LATCH */
    always @(clk or en or test_en)
        if (!clk) en_latched = en | test_en;
    /* verilator lint_on LATCH */
    assign gclk = clk & en_latched;
`else
    sky130_fd_sc_hd__dlclkp_1 icg (
        .CLK (clk),
        .GATE(en | test_en),
        .GCLK(gclk)
    );
`endif

endmodule
