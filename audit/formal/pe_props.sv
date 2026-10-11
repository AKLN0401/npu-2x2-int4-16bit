// Unbounded proof of npu_pe's next-state function against an independent reference.
// acc starts unconstrained, so the proof covers every accumulator value and all 256 operand pairs.
`default_nettype none
module pe_props (
    input wire       clk,
    input wire       clear,
    input wire       step,
    input wire       scan_en,
    input wire       scan_in,
    input wire [3:0] a,
    input wire [3:0] b
);
    wire [15:0] acc;
    wire        so;
    npu_pe #(.DW(4), .ACC_W(16)) dut (
        .clk(clk), .clear(clear), .step(step), .a(a), .b(b),
        .scan_en(scan_en), .scan_in(scan_in), .scan_out(so), .acc(acc));

    // Reference: operands sign-extended to 16 bit first, 16x16 multiply, keep 16 bits.
    // (RTL instead multiplies at 8 bit and sign-extends the product.)
    wire [15:0] a16 = {{12{a[3]}}, a};
    wire [15:0] b16 = {{12{b[3]}}, b};
    wire [15:0] ref_prod = a16 * b16;

    reg        past_valid = 1'b0;
    reg [15:0] acc_q, prod_q;
    reg        clear_q, step_q, se_q, si_q;
    always @(posedge clk) begin
        past_valid <= 1'b1;
        acc_q <= acc; prod_q <= ref_prod;
        clear_q <= clear; step_q <= step; se_q <= scan_en; si_q <= scan_in;
        if (past_valid) begin
            if (se_q)          assert (acc == {acc_q[14:0], si_q});   // scan shift wins
            else if (clear_q)  assert (acc == 16'd0);                 // clear beats step
            else if (step_q)   assert (acc == acc_q + prod_q);        // wrap mod 2^16
            else               assert (acc == acc_q);                 // hold
        end
        assert (so == acc[15]);
    end
    // reachability sanity: the wrap boundary and the product extremes are reachable
    always @(posedge clk) if (past_valid) begin
        cover (step_q && !clear_q && !se_q && acc_q == 16'h7fff && acc == 16'h8000);
        cover (step_q && !clear_q && !se_q && prod_q == 16'd64);
        cover (step_q && !clear_q && !se_q && prod_q == 16'hffc8);   // -56
    end
endmodule
