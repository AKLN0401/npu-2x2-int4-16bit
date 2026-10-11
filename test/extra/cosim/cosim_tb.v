`default_nettype none
`timescale 1ns / 1ps
// Lock-step co-simulation: RTL (rtl_top) vs. the post-PnR netlist (tt_um_akln0401_npu),
// same random pin stimulus, all outputs compared 4-state once per cycle (just before posedge).
// Inputs change at negedge. Default clock 100 ns (unit-delay netlist); -DHALF=10 -DSDF_FILE=... for a 50 MHz timing sim.
module cosim_tb;
  reg clk = 0, rst_n = 0, ena = 1;
  reg [7:0] ui_in = 0, uio_in = 0;
  wire [7:0] uo_r, uio_r, oe_r, uo_g, uio_g, oe_g;
  wire VPWR = 1'b1, VGND = 1'b0;

  rtl_top rtl (.ui_in(ui_in), .uo_out(uo_r), .uio_in(uio_in), .uio_out(uio_r), .uio_oe(oe_r),
               .ena(ena), .clk(clk), .rst_n(rst_n));
  tt_um_akln0401_npu gl (.VPWR(VPWR), .VGND(VGND),
               .ui_in(ui_in), .uo_out(uo_g), .uio_in(uio_in), .uio_out(uio_g), .uio_oe(oe_g),
               .ena(ena), .clk(clk), .rst_n(rst_n));

`ifndef HALF
`define HALF 50
`endif
  always #(`HALF) clk = ~clk;
`ifdef SDF_FILE
  initial $sdf_annotate(`SDF_FILE, gl);
`endif

  integer seed, seed0, ncycles, cyc = 0, errors = 0, checking = 0;
  integer n_wr [0:7];
  integer n_scan = 0, n_rand = 0, n_rst = 0, n_tm = 0, n_wrap = 0;
  integer i;

  // ---- compare ----
  initial forever begin
    @(negedge clk); #(`HALF - 1);   // 1 ns before posedge
    if (checking) begin
      if ({uo_r, uio_r, oe_r} !== {uo_g, uio_g, oe_g}) begin
        errors = errors + 1;
        if (errors <= 20)
          $display("MISMATCH cyc %0d: rtl uo=%h uio=%h oe=%h | gl uo=%h uio=%h oe=%h | ui=%h uio_in=%h",
                   cyc, uo_r, uio_r, oe_r, uo_g, uio_g, oe_g, ui_in, uio_in);
      end
    end
    cyc = cyc + 1;
  end

  // count accumulator wraps in the RTL (acc0 MSB flips 0->1 while adding a positive product)
  reg prev_msb = 0;
  always @(negedge clk) begin
    if (rtl.acc[15] && !prev_msb && rtl.a_reg[3:0] == 4'h8 && rtl.b_reg[3:0] == 4'h8) n_wrap = n_wrap + 1;
    prev_msb = rtl.acc[15];
  end

  // ---- stimulus helpers (all called right after a negedge) ----
  task cyc_wait(input integer n); integer j; begin for (j = 0; j < n; j = j + 1) @(negedge clk); end endtask

  task wr(input [2:0] a, input [7:0] d);
    integer hold, gap; begin
      hold = 4 + ($urandom(seed) % 3); gap = 2 + ($urandom(seed) % 3);
      uio_in[2:0] = a; ui_in = d; uio_in[3] = 1;  cyc_wait(hold);
      uio_in[3] = 0; cyc_wait(gap);
      n_wr[a] = n_wr[a] + 1;
    end
  endtask

  task protocol_burst(input integer n);
    integer j, r; reg [2:0] a; reg [7:0] d; begin
      for (j = 0; j < n; j = j + 1) begin
        r = $urandom(seed) % 16;
        a = $urandom(seed) % 8; d = $urandom(seed);
        if (r < 4) begin a = 4; d = $urandom(seed) % 8; end          // CTRL: clear/step/auto
        else if (r < 6) a = 6;                                            // RSEL read-back
        else if (r < 7) begin a = 6; d = 0; d[5:4] = $urandom(seed) % 4; d[3:0] = $urandom(seed) % 5; end
        wr(a, d);
      end
    end
  endtask

  // Drive the accumulators through 16-bit wrap: a = b = -8, auto-step on B1
  task wrap_burst;
    integer j; begin
      wr(4, 8'h01);              // clear, auto off
      wr(5, 8'h03);
      wr(0, 8'h88); wr(2, 8'h88);
      wr(4, 8'h04);              // auto on
      for (j = 0; j < 520 + ($urandom(seed) % 40); j = j + 1) wr(3, 8'h00);
      wr(6, 8'h00);
    end
  endtask

  // Read every byte of every accumulator (16 RSEL writes) and the ID bytes
  task readback_sweep;
    integer j; begin
      for (j = 0; j < 16; j = j + 1) wr(6, {2'b00, j[1:0], 2'b00, j[3:2]});
      for (j = 0; j < 4; j = j + 1) wr(6, {6'b100000, j[1:0]});
    end
  endtask

  // Shift the whole chain out (and random bits in) with test_mode on
  task scan_dump;
    integer j; begin
      uio_in[4] = 1; uio_in[5] = 1;
      for (j = 0; j < 100; j = j + 1) begin uio_in[6] = $urandom(seed); @(negedge clk); n_scan = n_scan + 1; end
      uio_in[6:4] = 0; @(negedge clk);
    end
  endtask

  task random_burst(input integer n);   // every input random every cycle, test_mode off mostly
    integer j; begin
      for (j = 0; j < n; j = j + 1) begin
        ui_in = $urandom(seed); uio_in = $urandom(seed); ena = $urandom(seed);
        if ($urandom(seed) % 8) uio_in[4] = 0;
        @(negedge clk); n_rand = n_rand + 1;
      end
    end
  endtask

  task scan_burst(input integer n);     // test_mode on, random scan_en/scan_in, random host pins
    integer j; begin
      uio_in[4] = 1;
      for (j = 0; j < n; j = j + 1) begin
        uio_in[5] = ($urandom(seed) % 4) != 0; uio_in[6] = $urandom(seed);
        if ($urandom(seed) % 4 == 0) begin ui_in = $urandom(seed); uio_in[3:0] = $urandom(seed); uio_in[7] = $urandom(seed); end
        @(negedge clk); n_scan = n_scan + 1;
      end
      uio_in[6:4] = 0; @(negedge clk);
    end
  endtask

  task reset_pulse; begin
      #($urandom(seed) % (`HALF / 2));   // async assert in the first half of the low phase (closer to the
                                       // edge, the netlist's rst_n buffers make it legitimately one cycle later)
      rst_n = 0;
      if ($test$plusargs("trace_rst")) $display("reset asserted cyc %0d at %0t (posedge at +%0d ns after negedge)", cyc, $time, `HALF);
      cyc_wait(1 + $urandom(seed) % 3); rst_n = 1; n_rst = n_rst + 1;
      @(negedge clk);
      case ($urandom(seed) % 3)
        0: scan_dump;
        1: begin wr(4, 8'h02); readback_sweep; end   // one step, then read everything
        default: ;
      endcase
    end
  endtask

  integer r;
  initial begin
    if (!$value$plusargs("seed=%d", seed)) seed = 1;
    seed0 = seed;
    if (!$value$plusargs("cycles=%d", ncycles)) ncycles = 200000;
        for (i = 0; i < 8; i = i + 1) n_wr[i] = 0;
    rst_n = 0; cyc_wait(5); rst_n = 1; cyc_wait(3);
    checking = 1;
    while (cyc < ncycles) begin
      r = $urandom(seed) % 100;
      if      (r < 50) protocol_burst(1 + $urandom(seed) % 30);
      else if (r < 54) readback_sweep;
      else if (r < 56) scan_dump;
      else if (r < 60) wrap_burst;
      else if (r < 75) random_burst(1 + $urandom(seed) % 200);
      else if (r < 92) scan_burst(1 + $urandom(seed) % 250);
      else if (r < 95) begin   // test mode with normal-looking traffic (clocks forced on)
        uio_in[4] = 1; uio_in[5] = 0; protocol_burst(1 + $urandom(seed) % 10); uio_in[4] = 0; n_tm = n_tm + 1;
      end
      else reset_pulse;
    end
    $display("COSIM seed=%0d cycles=%0d errors=%0d | writes A0 %0d A1 %0d B0 %0d B1 %0d CTRL %0d ROWEN %0d RSEL %0d r7 %0d | rand %0d scan %0d tm-bursts %0d resets %0d wraps %0d",
             seed0, cyc, errors, n_wr[0], n_wr[1], n_wr[2], n_wr[3], n_wr[4], n_wr[5], n_wr[6], n_wr[7],
             n_rand, n_scan, n_tm, n_rst, n_wrap);
    if (errors == 0) $display("COSIM PASS"); else $display("COSIM FAIL");
    $finish;
  end
endmodule
