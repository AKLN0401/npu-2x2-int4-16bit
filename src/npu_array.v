/*
 * Copyright (c) 2026 AKLN0401
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// ROWS x COLS int4 outer-product MAC array with one clock gate per row.
// On step: acc[i][j] += a[i] * b[j] for every enabled row i. The row enable acts on
// both the clock gate and the PE step input, so a disabled row also holds in test
// mode, where the clock gates are forced on.
//
// Scan chain (scan_in first): row 0 PE 0 acc[0..ACC_W-1], row 0 PE 1, ...,
// row ROWS-1 PE COLS-1 (each acc shifted LSB in / MSB out) -> scan_out.
module npu_array #(
    parameter ROWS  = 2,
    parameter COLS  = 2,
    parameter DW    = 4,
    parameter ACC_W = 12
) (
    input  wire                      clk,
    input  wire                      test_mode,
    input  wire                      clear,
    input  wire                      step,
    input  wire [ROWS-1:0]           row_en,
    input  wire [ROWS*DW-1:0]        a,          // a[i] in bits DW*i +: DW
    input  wire [COLS*DW-1:0]        b,          // b[j] in bits DW*j +: DW
    input  wire                      scan_en,
    input  wire                      scan_in,
    output wire                      scan_out,
    output wire [ROWS*COLS*ACC_W-1:0] acc        // acc[i][j] at ACC_W*(COLS*i + j)
);

    wire [ROWS*COLS:0] chain;
    assign chain[0] = scan_in;
    assign scan_out = chain[ROWS*COLS];

    genvar i, j;
    generate
        for (i = 0; i < ROWS; i = i + 1) begin : g_row
            wire gclk;
            clk_gate i_cg (
                .clk    (clk),
                .en     ((step && row_en[i]) || clear),
                .test_en(test_mode),
                .gclk   (gclk)
            );
            for (j = 0; j < COLS; j = j + 1) begin : g_col
                npu_pe #(.DW(DW), .ACC_W(ACC_W)) i_pe (
                    .clk     (gclk),
                    .clear   (clear),
                    .step    (step && row_en[i]),
                    .a       (a[DW*i +: DW]),
                    .b       (b[DW*j +: DW]),
                    .scan_en (scan_en),
                    .scan_in (chain[COLS*i + j]),
                    .scan_out(chain[COLS*i + j + 1]),
                    .acc     (acc[ACC_W*(COLS*i + j) +: ACC_W])
                );
            end
        end
    endgenerate

endmodule
