/*
 * Copyright (c) 2026 AKLN0401
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Standalone int4 MAC-array accelerator for one Tiny Tapeout tile, driven from pins
// by a host microcontroller (e.g. the demo board's RP2040).
//
// Pins:
//   ui[7:0]   data in (write byte)
//   uo[7:0]   data out (byte selected by RSEL)
//   uio[2:0]  register address          (in)
//   uio[3]    write strobe, active high  (in; synchronized, acts on its rising edge)
//   uio[4]    test_mode                  (in; forces row clocks on, enables scan)
//   uio[5]    scan_en                    (in; only acts while test_mode is high)
//   uio[6]    scan_in                    (in)
//   uio[7]    scan_out                   (out; 0 unless test_mode)
//
// Write protocol: set uio[2:0] and ui[7:0], raise uio[3], keep everything stable
// for at least 4 clocks, drop uio[3], wait 2 clocks before the next write.
//
// Registers (write):
//   0 A0    a[0] = bits 3:0, a[1] = bits 7:4            (signed int4)
//   1 A1    a[2] = bits 3:0, a[3] = bits 7:4
//   2 B0    b[0] = bits 3:0, b[1] = bits 7:4
//   3 B1    b[2] = bits 3:0, b[3] = bits 7:4; also steps if CTRL.auto is set
//   4 CTRL  bit 0: clear all accumulators, bit 1: step, bit 2: auto (sticky:
//           a write to B1 also steps). Clear and step in the same write: only clears
//   5 ROWEN row enable mask (reset: all rows enabled); a disabled row's clock stops
//   6 RSEL  read select: bit 7 = 0: uo = byte bits[5:4] of acc[bits 3:0]
//           (index = COLS*i + j, sign-extended); bit 7 = 1: uo = ID byte bits[1:0]
//   7       reserved
// ID bytes: 0 = 0x4E 'N', 1 = {ROWS, COLS}, 2 = ACC_W, 3 = 0x01 (version)
//
// One step: acc[i][j] += a[i] * b[j] for all enabled rows i, all columns j.
// Reset clears the accumulators and the A/B operand registers.
//
// Scan chain (scan_in first): wr_sync[0..2], a_reg[0..], b_reg[0..], auto, row_en[0..],
// rsel[0..7], step_q, clear_q, then the array (row-major, each acc LSB first).
// Off the chain: the two reset synchronizer flops.
module tt_um_akln0401_npu #(
    parameter ROWS  = 2,
    parameter COLS  = 2,
    parameter ACC_W = 16
) (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    localparam DW = 4;
    localparam AW = ROWS * DW;
    localparam BW = COLS * DW;
    localparam NPE = ROWS * COLS;

    localparam REG_A0    = 3'd0;
    localparam REG_A1    = 3'd1;
    localparam REG_B0    = 3'd2;
    localparam REG_B1    = 3'd3;
    localparam REG_CTRL  = 3'd4;
    localparam REG_ROWEN = 3'd5;
    localparam REG_RSEL  = 3'd6;

    wire [2:0] addr      = uio_in[2:0];
    wire       wr_pin    = uio_in[3];
    wire       test_mode = uio_in[4];
    wire       scan_en   = uio_in[5] & test_mode;
    wire       scan_in   = uio_in[6];

    // Reset synchronizer (off the scan chain so reset stays controllable in test mode)
    reg [1:0] rst_sync;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) rst_sync <= 2'b00;
        else        rst_sync <= {rst_sync[0], 1'b1};
    wire rstn = rst_sync[1];

    // ---- interface state: one scannable vector ----------------------------------
    // Field offsets, scan_in enters bit 0
    localparam O_WR    = 0;              // wr_sync[2:0]
    localparam O_A     = O_WR + 3;       // a_reg
    localparam O_B     = O_A + AW;       // b_reg
    localparam O_AUTO  = O_B + BW;       // auto
    localparam O_ROWEN = O_AUTO + 1;     // row_en
    localparam O_RSEL  = O_ROWEN + ROWS; // rsel[7:0]
    localparam O_STEP  = O_RSEL + 8;     // step_q
    localparam O_CLEAR = O_STEP + 1;     // clear_q
    localparam NST     = O_CLEAR + 1;

    reg  [NST-1:0] st;
    wire [2:0]      wr_sync = st[O_WR +: 3];
    wire [AW-1:0]   a_reg   = st[O_A +: AW];
    wire [BW-1:0]   b_reg   = st[O_B +: BW];
    wire            auto    = st[O_AUTO];
    wire [ROWS-1:0] row_en  = st[O_ROWEN +: ROWS];
    wire [7:0]      rsel    = st[O_RSEL +: 8];
    wire            step_q  = st[O_STEP];
    wire            clear_q = st[O_CLEAR];

    wire wr = wr_sync[1] & ~wr_sync[2];   // rising edge of the synchronized strobe

    // Byte writes into the A/B operand registers (only the bytes that exist)
    reg [AW-1:0] a_next;
    reg [BW-1:0] b_next;
    integer k;
    always @(*) begin
        a_next = a_reg;
        b_next = b_reg;
        for (k = 0; k < AW; k = k + 1)
            if (wr && addr == (k < 8 ? REG_A0 : REG_A1)) a_next[k] = ui_in[k % 8];
        for (k = 0; k < BW; k = k + 1)
            if (wr && addr == (k < 8 ? REG_B0 : REG_B1)) b_next[k] = ui_in[k % 8];
    end

    wire ctrl_wr  = wr && addr == REG_CTRL;
    wire step_req = (ctrl_wr && ui_in[1]) || (wr && addr == REG_B1 && auto);
    wire clr_req  = ctrl_wr && ui_in[0];

    reg [NST-1:0] st_next;
    always @(*) begin
        st_next = st;
        st_next[O_WR +: 3]      = {wr_sync[1:0], wr_pin};
        st_next[O_A +: AW]      = a_next;
        st_next[O_B +: BW]      = b_next;
        if (ctrl_wr)                st_next[O_AUTO]          = ui_in[2];
        if (wr && addr == REG_ROWEN) st_next[O_ROWEN +: ROWS] = ui_in[ROWS-1:0];
        if (wr && addr == REG_RSEL)  st_next[O_RSEL +: 8]     = ui_in;
        // step/clear act one cycle after the write, so a step sees the operand
        // bytes written in the same cycle (auto-step on B1)
        st_next[O_STEP]         = step_req;
        st_next[O_CLEAR]        = clr_req;
        if (!rstn) begin
            st_next[O_WR +: 3]      = 3'b000;
            st_next[O_A +: AW]      = {AW{1'b0}};
            st_next[O_B +: BW]      = {BW{1'b0}};
            st_next[O_AUTO]         = 1'b0;
            st_next[O_ROWEN +: ROWS] = {ROWS{1'b1}};
            st_next[O_RSEL +: 8]    = 8'h00;
            st_next[O_STEP]         = 1'b0;
            st_next[O_CLEAR]        = 1'b1;
        end
    end

    always @(posedge clk)
        st <= scan_en ? {st[NST-2:0], scan_in} : st_next;

    // ---- MAC array -----------------------------------------------------------------
    wire [NPE*ACC_W-1:0] acc;
    wire array_scan_out;
    npu_array #(.ROWS(ROWS), .COLS(COLS), .DW(DW), .ACC_W(ACC_W)) i_array (
        .clk      (clk),
        .test_mode(test_mode),
        .clear    (clear_q || !rstn),
        .step     (step_q && !scan_en),
        .row_en   (row_en),
        .a        (a_reg),
        .b        (b_reg),
        .scan_en  (scan_en),
        .scan_in  (st[NST-1]),
        .scan_out (array_scan_out),
        .acc      (acc)
    );

    // ---- read-back ---------------------------------------------------------------------
    localparam [4:0] NPE5 = NPE[4:0];
    wire [3:0]  idx = rsel[3:0];
    wire [ACC_W-1:0] acc_sel = ({1'b0, idx} < NPE5) ? acc[ACC_W*idx +: ACC_W] : {ACC_W{1'b0}};
    wire [31:0] acc_ext = {{(32-ACC_W){acc_sel[ACC_W-1]}}, acc_sel};
    reg  [7:0]  id_byte;
    always @(*) begin
        case (rsel[1:0])
            2'd0:    id_byte = 8'h4E;
            2'd1:    id_byte = {ROWS[3:0], COLS[3:0]};
            2'd2:    id_byte = ACC_W[7:0];
            default: id_byte = 8'h01;
        endcase
    end

    assign uo_out  = rsel[7] ? id_byte : acc_ext[8*rsel[5:4] +: 8];
    assign uio_out = {test_mode & array_scan_out, 7'b0};
    assign uio_oe  = 8'b1000_0000;

    wire _unused = &{ena, uio_in[7], rsel[6], 1'b0};

endmodule
