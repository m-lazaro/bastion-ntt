// =============================================================
// KYBER-512 NTT BUTTERFLY — 5-STAGE PIPELINE
// =============================================================
// Latency: 5 cycles
//
// Stage 1: Input latch
// Stage 2: Multiply  t_reg = zeta * b
// Stage 3: Montgomery step 1:  m16 = low16(t_reg) * QINV
// Stage 4: Montgomery step 2:  t_red = (t_reg - sext(m16)*Q) >>> 16
// Stage 5: CT butterfly:  a_out = a + t_red,  b_out = a - t_red
// =============================================================
module butterfly #(
    parameter signed [15:0] Q    = 16'sd3329,
    parameter signed [15:0] QINV = -16'sd3327
)(
    input  wire               clk,
    input  wire               rst,
    input  wire signed [15:0] a_in,
    input  wire signed [15:0] b_in,
    input  wire signed [15:0] w_in,
    output reg  signed [15:0] a_out,
    output reg  signed [15:0] b_out
);

    // STAGE 1: input latch
    reg signed [15:0] a_s1, b_s1, w_s1;
    always @(posedge clk) begin
        if (rst) begin a_s1 <= 0; b_s1 <= 0; w_s1 <= 0; end
        else     begin a_s1 <= a_in; b_s1 <= b_in; w_s1 <= w_in; end
    end

    // STAGE 2: multiply  t_full = zeta * b
    reg signed [31:0] t_full;
    reg signed [15:0] a_s2;
    always @(posedge clk) begin
        if (rst) begin t_full <= 0; a_s2 <= 0; end
        else     begin t_full <= b_s1 * w_s1; a_s2 <= a_s1; end
    end

    // STAGE 3: Montgomery part 1 — m16 = low16(t_full) * QINV
    wire signed [15:0] m16_comb = $signed(t_full[15:0]) * QINV;

    reg signed [15:0] m16_s3;
    reg signed [31:0] t_full_s3;
    reg signed [15:0] a_s3;
    always @(posedge clk) begin
        if (rst) begin m16_s3 <= 0; t_full_s3 <= 0; a_s3 <= 0; end
        else     begin m16_s3 <= m16_comb; t_full_s3 <= t_full; a_s3 <= a_s2; end
    end

    // STAGE 4: Montgomery part 2 — t_red = (t_full - sext(m16)*Q) >>> 16
    wire signed [31:0] m32_ext = {{16{m16_s3[15]}}, m16_s3};
    wire signed [31:0] u_comb  = $signed(t_full_s3 - m32_ext * Q) >>> 16;

    reg signed [15:0] t_red;
    reg signed [15:0] a_s4;
    always @(posedge clk) begin
        if (rst) begin t_red <= 0; a_s4 <= 0; end
        else     begin t_red <= u_comb[15:0]; a_s4 <= a_s3; end
    end

    // STAGE 5: butterfly output
    always @(posedge clk) begin
        if (rst) begin a_out <= 0; b_out <= 0; end
        else     begin a_out <= a_s4 + t_red; b_out <= a_s4 - t_red; end
    end

endmodule
