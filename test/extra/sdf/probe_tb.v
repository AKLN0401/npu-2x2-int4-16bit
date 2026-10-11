`default_nettype none
`timescale 1ns / 1ps
// Check that SDF delays reach the simulation: clk->Q of _1875_ (a_reg[0]) and C->X of _1229_ (or3_2)
module probe_tb;
  reg clk = 0, rst_n = 0;
  reg [7:0] ui_in = 0, uio_in = 0;
  wire [7:0] uo_out, uio_out, uio_oe;
  wire VPWR = 1'b1, VGND = 1'b0;
  tt_um_akln0401_npu user_project (.VPWR(VPWR), .VGND(VGND), .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in),
      .uio_out(uio_out), .uio_oe(uio_oe), .ena(1'b1), .clk(clk), .rst_n(rst_n));
  initial $sdf_annotate(`SDF_FILE, user_project);
  always #10 clk = ~clk;
  realtime t_clk, t_cpin, t_c;
  always @(posedge clk) t_clk = $realtime;
  always @(posedge user_project._1875_.CLK) t_cpin = $realtime;
  always @(user_project._1875_.Q) if ($realtime > 100)
    $display("_1875_: clk port->CLK pin %.3f ns, CLK->Q %.3f ns (Q=%b)", t_cpin - t_clk, $realtime - t_cpin, user_project._1875_.Q);
  always @(user_project._1229_.C) t_c = $realtime;
  always @(user_project._1229_.X) if ($realtime > 100 && $realtime - t_c < 5)
    $display("_1229_: C->X %.3f ns (X=%b, A=%b B=%b C=%b)", $realtime - t_c, user_project._1229_.X,
             user_project._1229_.A, user_project._1229_.B, user_project._1229_.C);
  task wr(input [2:0] a, input [7:0] d); begin
    @(negedge clk); uio_in[2:0] = a; ui_in = d; uio_in[3] = 1; repeat (4) @(negedge clk); uio_in[3] = 0; repeat (3) @(negedge clk);
  end endtask
  integer k;
  initial begin
    repeat (4) @(negedge clk); rst_n = 1; repeat (4) @(negedge clk);
    for (k = 0; k < 6; k = k + 1) begin wr(0, k[0] ? 8'h01 : 8'h0F); wr(2, k[1] ? 8'h7F : 8'h81); end
    $finish;
  end
endmodule
