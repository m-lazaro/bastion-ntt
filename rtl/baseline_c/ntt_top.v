// =============================================================
// NTT_TOP — BASELINE C: UNMASKED, 2-BFU, STRIDE-INVARIANT BANKING
// =============================================================
// Iso-architectural control for the masked core. Derived from the
// BASTION top-level by deleting one share domain and nothing else:
//
//   - banks s1_even / s1_odd        : removed
//   - butterflies bf2 / bf3         : removed
//   - port ext_share_sel            : removed
//   - read-back path                : one read register instead of two
//   - all synthesis attributes      : removed (nothing to separate),
//                                     matching Baseline B's regime
//
// EVERYTHING ELSE IS IDENTICAL TO THE MASKED CORE:
//   - same ntt_controller.v, instantiated unmodified
//   - same twiddle_rom.v, same lfsr16.v
//   - same even/odd stride-invariant banking (128x16 per bank)
//   - same L1 dummy-operand muxing on both butterflies
//   - same L2 XOR-bijection shuffle (p = 2 groups)
//   - same 5-stage Montgomery butterfly arithmetic
//
// PURPOSE: isolate the cost of first-order masking from the cost of
// the datapath reorganisation that masking imposes. Baseline C runs
// the same schedule in the same number of cycles as the masked core,
// so any resource delta between the two is attributable to masking
// alone: domain duplication plus the synthesis discipline that
// enforces the separation.
//
// INTERFACE: as the masked core, with one share. Read back only after
// done and two further clock edges, which let the last butterfly leave
// the pipeline; the word appears on ext_data_r two edges after its
// address.
// =============================================================
module ntt_top (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    output wire        done,
    // External interface
    input  wire        ext_we,
    input  wire [7:0]  ext_addr_w,
    input  wire signed [15:0] ext_data_w,
    input  wire [7:0]  ext_addr_r,
    input  wire        ext_re,          // read-back enable (after DONE)
    output wire signed [15:0] ext_data_r
);

    // =========================================================
    // LFSR — entropy source for L1 (dummy) + L2 (shuffle)
    // =========================================================
    wire [15:0] lfsr_out;
    lfsr16 prng (.clk(clk), .rst(rst), .out(lfsr_out));

    wire signed [15:0] dummy_a = $signed(lfsr_out);
    wire signed [15:0] dummy_b = $signed({lfsr_out[7:0], lfsr_out[15:8]});
    wire signed [15:0] dummy_w = $signed({lfsr_out[11:0], lfsr_out[15:12]});

    // =========================================================
    // Controller (unmodified from the masked core)
    // =========================================================
    wire [7:0] ctrl_addr_a, ctrl_addr_b;
    wire [7:0] ctrl_addr_wa, ctrl_addr_wb;
    wire       ctrl_we;
    wire [7:0] ctrl_zeta_addr;
    wire       bf_active;

    ntt_controller ctrl (
        .clk(clk), .reset(rst), .start(start), .done(done),
        .rand_seed(lfsr_out),
        .addr_a(ctrl_addr_a), .addr_b(ctrl_addr_b),
        .addr_write_a(ctrl_addr_wa), .addr_write_b(ctrl_addr_wb),
        .we(ctrl_we), .zeta_addr(ctrl_zeta_addr),
        .bf_active(bf_active)
    );

    // =========================================================
    // Twiddle ROM (public)
    // =========================================================
    wire signed [15:0] twiddle;
    twiddle_rom rom (.clk(clk), .addr(ctrl_zeta_addr), .zeta(twiddle));

    // =========================================================
    // Address derivation
    // =========================================================
    // BFU0 (even): use ctrl_addr_a directly
    // BFU1 (odd):  use ctrl_addr_a + 1
    wire [7:0] ra_even = ctrl_addr_a;
    wire [7:0] rb_even = ctrl_addr_b;
    wire [7:0] ra_odd  = ctrl_addr_a + 8'd1;
    wire [7:0] rb_odd  = ctrl_addr_b + 8'd1;

    wire [7:0] wa_even = ctrl_addr_wa;
    wire [7:0] wb_even = ctrl_addr_wb;
    wire [7:0] wa_odd  = ctrl_addr_wa + 8'd1;
    wire [7:0] wb_odd  = ctrl_addr_wb + 8'd1;

    // Physical addresses: logical[7:1]
    wire [6:0] pa_even = ra_even[7:1];
    wire [6:0] pb_even = rb_even[7:1];
    wire [6:0] pa_odd  = ra_odd[7:1];
    wire [6:0] pb_odd  = rb_odd[7:1];

    wire [6:0] pwa_even = wa_even[7:1];
    wire [6:0] pwb_even = wb_even[7:1];
    wire [6:0] pwa_odd  = wa_odd[7:1];
    wire [6:0] pwb_odd  = wb_odd[7:1];

    // External access helpers
    wire ext_is_even = ~ext_addr_w[0];
    wire ext_is_odd  =  ext_addr_w[0];
    wire [6:0] ext_phys_w = ext_addr_w[7:1];
    wire [6:0] ext_phys_r = ext_addr_r[7:1];
    wire ext_r_even = ~ext_addr_r[0];

    // =========================================================
    // Butterfly and bank outputs (no preservation attributes)
    // =========================================================
    wire signed [15:0] bf0_ao, bf0_bo;  // even
    wire signed [15:0] bf1_ao, bf1_bo;  // odd

    wire signed [15:0] e_da, e_db;      // even bank
    wire signed [15:0] o_da, o_db;      // odd bank

    // =========================================================
    // EVEN BANK (BFU0 a-side=portA, b-side=portB)
    // =========================================================
    wire e_ext = ext_we && ext_is_even;
    wire e_wea = e_ext || ctrl_we;
    wire e_web = ctrl_we;

    wire [6:0] e_aa = e_ext                ? ext_phys_w :
                      (done && ext_re && ext_r_even) ? ext_phys_r :
                      ctrl_we              ? pwa_even :
                                             pa_even;
    wire [6:0] e_ab = ctrl_we ? pwb_even : pb_even;

    wire signed [15:0] e_da_in = e_ext ? ext_data_w : bf0_ao;

    memory_bank even_bank (
        .clk(clk),
        .we_a(e_wea), .addr_a(e_aa), .din_a(e_da_in), .dout_a(e_da),
        .we_b(e_web), .addr_b(e_ab), .din_b(bf0_bo),  .dout_b(e_db)
    );

    // =========================================================
    // ODD BANK (BFU1 a-side=portA, b-side=portB)
    // =========================================================
    wire o_ext = ext_we && ext_is_odd;
    wire o_wea = o_ext || ctrl_we;
    wire o_web = ctrl_we;

    wire [6:0] o_aa = o_ext                 ? ext_phys_w :
                      (done && ext_re && !ext_r_even) ? ext_phys_r :
                      ctrl_we               ? pwa_odd :
                                              pa_odd;
    wire [6:0] o_ab = ctrl_we ? pwb_odd : pb_odd;

    wire signed [15:0] o_da_in = o_ext ? ext_data_w : bf1_ao;

    memory_bank odd_bank (
        .clk(clk),
        .we_a(o_wea), .addr_a(o_aa), .din_a(o_da_in), .dout_a(o_da),
        .we_b(o_web), .addr_b(o_ab), .din_b(bf1_bo),  .dout_b(o_db)
    );

    // =========================================================
    // Read-back path: one register, same pipeline as the masked core
    // =========================================================
    // Kept identical to one domain of the masked core's read-back path
    // so that Baseline C remains the masked core minus one domain.
    reg rd_en_d, rd_even_d;
    reg signed [15:0] rd_q;

    always @(posedge clk) begin
        if (rst) begin
            rd_en_d   <= 1'b0;
            rd_even_d <= 1'b0;
            rd_q      <= 16'sd0;
        end else begin
            rd_en_d   <= done && ext_re;
            rd_even_d <= ext_r_even;
            rd_q      <= rd_en_d ? (rd_even_d ? e_da : o_da) : 16'sd0;
        end
    end

    assign ext_data_r = rd_q;

    // =========================================================
    // BUTTERFLIES — with dummy operation muxing (Level 1)
    // =========================================================
    // BFU0: even addresses
    wire signed [15:0] bf0_ai = bf_active ? e_da    : dummy_a;
    wire signed [15:0] bf0_bi = bf_active ? e_db    : dummy_b;
    wire signed [15:0] bf0_wi = bf_active ? twiddle : dummy_w;

    butterfly bf0 (
        .clk(clk), .rst(rst),
        .a_in(bf0_ai), .b_in(bf0_bi), .w_in(bf0_wi),
        .a_out(bf0_ao), .b_out(bf0_bo)
    );

    // BFU1: odd addresses
    wire signed [15:0] bf1_ai = bf_active ? o_da    : dummy_a;
    wire signed [15:0] bf1_bi = bf_active ? o_db    : dummy_b;
    wire signed [15:0] bf1_wi = bf_active ? twiddle : dummy_w;

    butterfly bf1 (
        .clk(clk), .rst(rst),
        .a_in(bf1_ai), .b_in(bf1_bi), .w_in(bf1_wi),
        .a_out(bf1_ao), .b_out(bf1_bo)
    );

endmodule
