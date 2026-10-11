// Stimulus for vector-based power of the post-PnR netlist. One scenario per run (plusargs):
//   +tm=0|1      test_mode: 0 = clock gating active, 1 = row clocks forced on (gating defeated)
//   +rowen=N     ROWEN mask (3 = both rows, 1 = row 0 only)
//   +gap=N       strobe-low clocks after each write (2 = protocol minimum, 94 = one write per 100 clk)
//   +work=0|1    0 = idle (clock only), 1 = matmul stream: A0, B0, CTRL.step per step
//   +cycles=N    measured window in clocks; VCD covers exactly this window
// Same seed in every run, so tm=0 and tm=1 see identical bus traffic.
`timescale 1ns / 1ps
module ptb;
  reg clk = 0, rst_n = 0, ena = 1;
  reg [7:0] ui_in = 0, uio_in = 0;
  wire [7:0] uo_out, uio_out, uio_oe;
  wire VPWR = 1'b1, VGND = 1'b0;
  tt_um_akln0401_npu user_project (.VPWR(VPWR), .VGND(VGND), .ui_in(ui_in), .uo_out(uo_out),
      .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe), .ena(ena), .clk(clk), .rst_n(rst_n));
  always #10 clk = ~clk;   // 50 MHz

  integer tm, rowen, gap, work, cycles, seed, steps, t0;
  reg [255:0] vcd;
  task wr(input [2:0] a, input [7:0] d);
    begin
      @(negedge clk); ui_in = d; uio_in = (tm << 4) | 8'h08 | a;   // data, addr, strobe together
      repeat (4) @(negedge clk); uio_in = (tm << 4) | a;           // strobe low
      repeat (gap) @(negedge clk);
    end
  endtask
  initial begin
    if (!$value$plusargs("tm=%d", tm)) tm = 0;
    if (!$value$plusargs("rowen=%d", rowen)) rowen = 3;
    if (!$value$plusargs("gap=%d", gap)) gap = 2;
    if (!$value$plusargs("work=%d", work)) work = 1;
    if (!$value$plusargs("cycles=%d", cycles)) cycles = 10000;
    if (!$value$plusargs("vcd=%s", vcd)) vcd = "power.vcd";
    seed = 12345; steps = 0;
    repeat (10) @(negedge clk); rst_n = 1; repeat (5) @(negedge clk);
    uio_in = tm << 4;
    wr(5, rowen);                    // ROWEN
    wr(4, 1);                        // clear
    repeat (20) @(negedge clk);
    $dumpfile(vcd); $dumpvars(0, ptb.user_project);
    t0 = $time;
    fork
      begin repeat (cycles) @(posedge clk); end
      if (work) forever begin
        wr(0, $random(seed)); wr(2, $random(seed)); wr(4, 2); steps = steps + 1;
      end else begin
        repeat (cycles + 1) @(posedge clk);   // idle: keep this branch alive past the window
      end
    join_any
    $display("POWER_TB tm=%0d rowen=%0d gap=%0d work=%0d cycles=%0d window_ns=%0d steps=%0d acc00=%0d acc11=%0d",
             tm, rowen, gap, work, cycles, $time - t0, steps,
             $signed({user_project.\acc[15] , user_project.\acc[14] , user_project.\acc[13] , user_project.\acc[12] ,
                      user_project.\acc[11] , user_project.\acc[10] , user_project.\acc[9] , user_project.\acc[8] ,
                      user_project.\acc[7] , user_project.\acc[6] , user_project.\acc[5] , user_project.\acc[4] ,
                      user_project.\acc[3] , user_project.\acc[2] , user_project.\acc[1] , user_project.\acc[0] }),
             $signed({user_project.\acc[63] , user_project.\acc[62] , user_project.\acc[61] , user_project.\acc[60] ,
                      user_project.\acc[59] , user_project.\acc[58] , user_project.\acc[57] , user_project.\acc[56] ,
                      user_project.\acc[55] , user_project.\acc[54] , user_project.\acc[53] , user_project.\acc[52] ,
                      user_project.\acc[51] , user_project.\acc[50] , user_project.\acc[49] , user_project.\acc[48] }));
    $finish;
  end
endmodule
