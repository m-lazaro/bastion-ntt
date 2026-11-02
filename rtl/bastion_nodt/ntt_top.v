// -------------------------------------------------------------
// BASTION-noDT VARIANT — RESOURCE MEASUREMENT CONTROL ONLY
// -------------------------------------------------------------
// Identical to the BASTION masked core except that every synthesis
// preservation attribute (KEEP_HIERARCHY, KEEP, DONT_TOUCH) has been
// removed, giving synthesis the same freedom Baseline B and Baseline C
// enjoy.
//
// THIS CONFIGURATION IS NOT CLAIMED SECURE. Without the attributes,
// synthesis may merge, retime or share logic across the share boundary,
// which is precisely what the discipline of Section 4.5 exists to
// prevent. It is synthesised solely to quantify the resource cost of
// that discipline, by comparison against BASTION proper.
// -------------------------------------------------------------
// =============================================================
// NTT_TOP — FIRST-ORDER MASKED, 4-BFU (2 per share)
// =============================================================
// SIDE-CHANNEL HARDENING:
//   Level 1: Uniform power profile (LFSR dummy operations)
//   Level 2: Randomized scheduling (XOR-bijection shuffle)
//   Level 3: First-order arithmetic masking (DOM-compatible)
//
// ARCHITECTURE:
//   Share 0: s0_even_bank + s0_odd_bank → BFU0 (even) + BFU1 (odd)
//   Share 1: s1_even_bank + s1_odd_bank → BFU2 (even) + BFU3 (odd)
//
// SECURITY ARGUMENT (revised read-back path):
//   Each BFU processes exactly one share and each memory bank stores
//   exactly one share. The twiddle factor (zeta), the addresses, the
//   shuffle and the dummy operands are public and common to both
//   domains. The only cell with inputs from both domains is the 2:1
//   multiplexer that drives ext_data_r, and its data inputs are the
//   per-domain read registers rd0_q and rd1_q. Each register loads only
//   when done, ext_re and its own share select are asserted, and holds
//   zero otherwise, so both are zero during the transform and they are
//   never non-zero in the same cycle (checked in simulation).
//
// INTERFACE REQUIREMENTS (the argument above relies on them):
//   - Load share 0 with ext_share_sel=0, then share 1 with
//     ext_share_sel=1. After the last word, drive ext_data_w and
//     ext_addr_w to zero: the input bus reaches the write multiplexers
//     of both domains, so no share word may stay on it while the
//     transform runs.
//   - Read back only after done, and not before two further clock
//     edges: done rises while the last butterfly is still in stages
//     four and five of the pipeline, and those edges let it drain before
//     the first word of a share reaches a latch or a read register.
//     Then assert ext_re and present ext_addr_r; the word appears on
//     ext_data_r two clock edges later. Between the two shares, hold
//     ext_re low for two cycles so that both read registers clear
//     before the other domain is selected.
//
// MASKING LINEARITY:
//   NTT is linear over Z_Q (integers mod Q=3329):
//     NTT(share0 + share1) = NTT(share0) + NTT(share1) mod Q
//   This holds because:
//   - Addition/subtraction in butterfly is linear
//   - fqmul(zeta, x) = zeta * x * R^-1 mod Q is linear in x
//   Both shares undergo identical NTT operations with the same
//   zeta values. Recombination: result[i] = (s0[i] + s1[i]) mod Q
//
// SYNTHESIS ATTRIBUTES:
//   KEEP_HIERARCHY preserves module boundaries of BFUs and banks
//   through synthesis, preventing the tool from flattening logic
//   and inadvertently creating cross-share optimizations.
//   KEEP/DONT_TOUCH on share-boundary signals prevents retiming,
//   resource sharing, and register merging between share domains.
// =============================================================
module ntt_top (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    output wire        done,
    // External interface
    input  wire        ext_we,
    input  wire        ext_share_sel,   // 0=share0, 1=share1
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
    // Controller (shared — same addresses for both shares)
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
    // Twiddle ROM (PUBLIC — shared safely by all BFUs)
    // =========================================================
    wire signed [15:0] twiddle;
    twiddle_rom rom (.clk(clk), .addr(ctrl_zeta_addr), .zeta(twiddle));

    // =========================================================
    // Address derivation
    // =========================================================
    // BFU0/2 (even): use ctrl_addr_a directly
    // BFU1/3 (odd):  use ctrl_addr_a + 1
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
    // Butterfly outputs — KEEP prevents cross-share retiming
    // =========================================================
    wire signed [15:0] bf0_ao, bf0_bo;  // share0 even
    wire signed [15:0] bf1_ao, bf1_bo;  // share0 odd
    wire signed [15:0] bf2_ao, bf2_bo;  // share1 even
    wire signed [15:0] bf3_ao, bf3_bo;  // share1 odd

    // =========================================================
    // Bank data outputs — KEEP prevents sharing with other banks
    // =========================================================
    wire signed [15:0] s0e_da, s0e_db;  // share0 even
    wire signed [15:0] s0o_da, s0o_db;  // share0 odd
    wire signed [15:0] s1e_da, s1e_db;  // share1 even
    wire signed [15:0] s1o_da, s1o_db;  // share1 odd

    // =========================================================
    // SHARE 0 — EVEN BANK (BFU0 a-side=portA, b-side=portB)
    // =========================================================
    wire s0e_ext = ext_we && !ext_share_sel && ext_is_even;
    wire s0e_wea = s0e_ext || ctrl_we;
    wire s0e_web = ctrl_we;

    wire [6:0] s0e_aa = s0e_ext             ? ext_phys_w :
                        (done && ext_re && !ext_share_sel && ext_r_even) ? ext_phys_r :
                        ctrl_we              ? pwa_even :
                                               pa_even;
    wire [6:0] s0e_ab = ctrl_we ? pwb_even : pb_even;

    wire signed [15:0] s0e_da_in = s0e_ext ? ext_data_w : bf0_ao;

    memory_bank s0_even (
        .clk(clk),
        .we_a(s0e_wea), .addr_a(s0e_aa), .din_a(s0e_da_in), .dout_a(s0e_da),
        .we_b(s0e_web), .addr_b(s0e_ab), .din_b(bf0_bo),    .dout_b(s0e_db)
    );

    // =========================================================
    // SHARE 0 — ODD BANK (BFU1 a-side=portA, b-side=portB)
    // =========================================================
    wire s0o_ext = ext_we && !ext_share_sel && ext_is_odd;
    wire s0o_wea = s0o_ext || ctrl_we;
    wire s0o_web = ctrl_we;

    wire [6:0] s0o_aa = s0o_ext             ? ext_phys_w :
                        (done && ext_re && !ext_share_sel && !ext_r_even) ? ext_phys_r :
                        ctrl_we              ? pwa_odd :
                                               pa_odd;
    wire [6:0] s0o_ab = ctrl_we ? pwb_odd : pb_odd;

    wire signed [15:0] s0o_da_in = s0o_ext ? ext_data_w : bf1_ao;

    memory_bank s0_odd (
        .clk(clk),
        .we_a(s0o_wea), .addr_a(s0o_aa), .din_a(s0o_da_in), .dout_a(s0o_da),
        .we_b(s0o_web), .addr_b(s0o_ab), .din_b(bf1_bo),    .dout_b(s0o_db)
    );

    // =========================================================
    // SHARE 1 — EVEN BANK (BFU2 a-side=portA, b-side=portB)
    // =========================================================
    wire s1e_ext = ext_we && ext_share_sel && ext_is_even;
    wire s1e_wea = s1e_ext || ctrl_we;
    wire s1e_web = ctrl_we;

    wire [6:0] s1e_aa = s1e_ext             ? ext_phys_w :
                        (done && ext_re && ext_share_sel && ext_r_even) ? ext_phys_r :
                        ctrl_we              ? pwa_even :
                                               pa_even;
    wire [6:0] s1e_ab = ctrl_we ? pwb_even : pb_even;

    wire signed [15:0] s1e_da_in = s1e_ext ? ext_data_w : bf2_ao;

    memory_bank s1_even (
        .clk(clk),
        .we_a(s1e_wea), .addr_a(s1e_aa), .din_a(s1e_da_in), .dout_a(s1e_da),
        .we_b(s1e_web), .addr_b(s1e_ab), .din_b(bf2_bo),    .dout_b(s1e_db)
    );

    // =========================================================
    // SHARE 1 — ODD BANK (BFU3 a-side=portA, b-side=portB)
    // =========================================================
    wire s1o_ext = ext_we && ext_share_sel && ext_is_odd;
    wire s1o_wea = s1o_ext || ctrl_we;
    wire s1o_web = ctrl_we;

    wire [6:0] s1o_aa = s1o_ext             ? ext_phys_w :
                        (done && ext_re && ext_share_sel && !ext_r_even) ? ext_phys_r :
                        ctrl_we              ? pwa_odd :
                                               pa_odd;
    wire [6:0] s1o_ab = ctrl_we ? pwb_odd : pb_odd;

    wire signed [15:0] s1o_da_in = s1o_ext ? ext_data_w : bf3_ao;

    memory_bank s1_odd (
        .clk(clk),
        .we_a(s1o_wea), .addr_a(s1o_aa), .din_a(s1o_da_in), .dout_a(s1o_da),
        .we_b(s1o_web), .addr_b(s1o_ab), .din_b(bf3_bo),    .dout_b(s1o_db)
    );

    // =========================================================
    // Read-back path (revised): one register per share domain
    // =========================================================
    // Each domain's bank outputs feed only that domain's read register.
    // A register loads only after DONE, with ext_re high and its own
    // domain selected; the enable and the parity bit are delayed by one
    // cycle so that the register captures the word addressed by
    // ext_addr_r, never a stale bank output. Otherwise it holds zero.
    // During the NTT both registers are therefore constant zero, and the
    // final 2:1 multiplexer never receives share data from both domains.
    // Protocol: read all of share 0, drop ext_re for two cycles (both
    // registers clear), then select share 1 and raise ext_re again.
    reg rd0_en_d, rd1_en_d, rd_even_d;
    reg signed [15:0] rd0_q;
    reg signed [15:0] rd1_q;

    always @(posedge clk) begin
        if (rst) begin
            rd0_en_d  <= 1'b0;
            rd1_en_d  <= 1'b0;
            rd_even_d <= 1'b0;
            rd0_q     <= 16'sd0;
            rd1_q     <= 16'sd0;
        end else begin
            rd0_en_d  <= done && ext_re && !ext_share_sel;
            rd1_en_d  <= done && ext_re &&  ext_share_sel;
            rd_even_d <= ext_r_even;
            rd0_q     <= rd0_en_d ? (rd_even_d ? s0e_da : s0o_da) : 16'sd0;
            rd1_q     <= rd1_en_d ? (rd_even_d ? s1e_da : s1o_da) : 16'sd0;
        end
    end

    assign ext_data_r = ext_share_sel ? rd1_q : rd0_q;

    // =========================================================
    // BUTTERFLIES — with dummy operation muxing (Level 1)
    // =========================================================
    // BFU0: share0, even addresses
    wire signed [15:0] bf0_ai = bf_active ? s0e_da : dummy_a;
    wire signed [15:0] bf0_bi = bf_active ? s0e_db : dummy_b;
    wire signed [15:0] bf0_wi = bf_active ? twiddle : dummy_w;

    butterfly bf0 (
        .clk(clk), .rst(rst),
        .a_in(bf0_ai), .b_in(bf0_bi), .w_in(bf0_wi),
        .a_out(bf0_ao), .b_out(bf0_bo)
    );

    // BFU1: share0, odd addresses
    wire signed [15:0] bf1_ai = bf_active ? s0o_da : dummy_a;
    wire signed [15:0] bf1_bi = bf_active ? s0o_db : dummy_b;
    wire signed [15:0] bf1_wi = bf_active ? twiddle : dummy_w;

    butterfly bf1 (
        .clk(clk), .rst(rst),
        .a_in(bf1_ai), .b_in(bf1_bi), .w_in(bf1_wi),
        .a_out(bf1_ao), .b_out(bf1_bo)
    );

    // BFU2: share1, even addresses
    wire signed [15:0] bf2_ai = bf_active ? s1e_da : dummy_a;
    wire signed [15:0] bf2_bi = bf_active ? s1e_db : dummy_b;
    wire signed [15:0] bf2_wi = bf_active ? twiddle : dummy_w;

    butterfly bf2 (
        .clk(clk), .rst(rst),
        .a_in(bf2_ai), .b_in(bf2_bi), .w_in(bf2_wi),
        .a_out(bf2_ao), .b_out(bf2_bo)
    );

    // BFU3: share1, odd addresses
    wire signed [15:0] bf3_ai = bf_active ? s1o_da : dummy_a;
    wire signed [15:0] bf3_bi = bf_active ? s1o_db : dummy_b;
    wire signed [15:0] bf3_wi = bf_active ? twiddle : dummy_w;

    butterfly bf3 (
        .clk(clk), .rst(rst),
        .a_in(bf3_ai), .b_in(bf3_bi), .w_in(bf3_wi),
        .a_out(bf3_ao), .b_out(bf3_bo)
    );

endmodule
