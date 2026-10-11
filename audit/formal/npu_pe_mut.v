/*
 * Copyright (c) 2026 AKLN0401
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// One MAC unit: acc += a * b (signed). Clocked by a gated row clock, so it
// only toggles on cycles where its row is stepped or cleared.
// Scan: with scan_en high, acc shifts left one bit per clock (scan_in -> acc[0],
// acc[ACC_W-1] -> scan_out). scan_en overrides clear and step.
module npu_pe #(
    parameter DW    = 4,   // operand width
    parameter ACC_W = 16   // accumulator width
) (
    input  wire                    clk,   // gated row clock
    input  wire                    clear,
    input  wire                    step,
    input  wire signed [DW-1:0]    a,
    input  wire signed [DW-1:0]    b,
    input  wire                    scan_en,
    input  wire                    scan_in,
    output wire                    scan_out,
    output reg  signed [ACC_W-1:0] acc
);

    wire signed [2*DW-1:0] prod = a * b;

    always @(posedge clk) begin
        if (scan_en)
            acc <= {acc[ACC_W-2:0], scan_in};
        else if (clear)
            acc <= {ACC_W{1'b0}};
        else if (step)
            acc <= acc + {{(ACC_W-2*DW){1'b0}}, prod};
    end

    assign scan_out = acc[ACC_W-1];

endmodule
