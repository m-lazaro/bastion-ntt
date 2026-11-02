// =============================================================
// NTT_TOP — FIRST-ORDER MASKED, STAGGERED SCHEDULE (2 BFU per share)
// =============================================================
// Same datapath as the lock-step BASTION core (rtl/bastion): two
// share domains, each with an even and an odd bank and two
// butterflies, and the same read-back path. What changes is the
// schedule: the two domains run the same program `delta` cycles apart,
// in an order chosen by a fresh random bit per execution, following
// HOPE-MLKEM.
//
//   ctrl_p, lfsr_p : primary controller and LFSR; ctrl_p starts with
//                    `start`, lfsr_p runs freely as in the lock-step core.
//   ctrl_s, lfsr_s : secondary copies. lfsr_s is loaded with the state of
//                    lfsr_p at `start` and released `delta` cycles later,
//                    when ctrl_s starts, so the secondary domain repeats
//                    the address, twiddle, dummy and shuffle sequence of
//                    the primary one exactly `delta` cycles later.
//   lead           : order bit, sampled from `order_rand` at `start`.
//                    lead = 0: domain 0 follows ctrl_p and leads;
//                    lead = 1: domain 1 follows ctrl_p and leads.
//   twiddle ROM    : one dual-port ROM; port A serves ctrl_p, port B
//                    serves ctrl_s.
//
// Latency: 4,034 + delta cycles from the cycle in which `start` is high
// to the edge that raises `done` (lock-step core: 4,034), delta >= 1.
// `delta` and `order_rand` are public and sampled at `start`; the area
// does not depend on delta.
//
// SECURITY ARGUMENT AND INTERFACE REQUIREMENTS: as in rtl/bastion/ntt_top.v.
// In particular, read back only two clock edges after done or later: done
// rises while the last butterfly of the lagging domain is still in the
// pipeline.
// Every bank, butterfly, pipeline register and read register belongs to
// one domain; the multiplexers added here select between the two
// controllers' public signals (addresses, enables, twiddles, dummies)
// and never carry share data. `done` is the AND of both controllers'
// done, so read-back starts only after both transforms have finished.
// =============================================================
(* KEEP_HIERARCHY = "yes" *)
module ntt_top (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    output wire        done,
    // Schedule configuration (public, sampled at start)
    input  wire [12:0] delta,           // offset between the domains, >= 1
    input  wire        order_rand,      // fresh random bit: which domain leads
    // External interface (as in rtl/bastion)
    input  wire        ext_we,
    input  wire        ext_share_sel,   // 0=share0, 1=share1
    input  wire [7:0]  ext_addr_w,
    input  wire signed [15:0] ext_data_w,
    input  wire [7:0]  ext_addr_r,
    input  wire        ext_re,          // read-back enable (after DONE)
    output wire signed [15:0] ext_data_r
);

    // =========================================================
    // Schedule control: order bit and delayed start of ctrl_s
    // =========================================================
    reg        lead;
    reg        waiting;     // between start and the release of ctrl_s
    reg [12:0] dcnt;
    reg        running_s;   // lfsr_s steps from the release onwards

    wire start_s = waiting && (dcnt == 13'd0);

    always @(posedge clk) begin
        if (rst) begin
            lead      <= 1'b0;
            waiting   <= 1'b0;
            dcnt      <= 13'd0;
            running_s <= 1'b0;
        end else if (start) begin
            lead      <= order_rand;
            waiting   <= 1'b1;
            dcnt      <= delta - 13'd1;
            running_s <= 1'b0;
        end else if (waiting) begin
            if (dcnt == 13'd0) begin
                waiting   <= 1'b0;
                running_s <= 1'b1;
            end else begin
                dcnt <= dcnt - 13'd1;
            end
        end
    end

    // =========================================================
    // LFSRs — entropy for L1 (dummy) + L2 (shuffle)
    // =========================================================
    wire [15:0] lfsr_p_out, lfsr_s_out;
    lfsr16    prng_p (.clk(clk), .rst(rst), .out(lfsr_p_out));
    lfsr16_ld prng_s (.clk(clk), .rst(rst),
                      .load(start), .load_val(lfsr_p_out),
                      .en(start_s || running_s), .out(lfsr_s_out));

    wire signed [15:0] p_dummy_a = $signed(lfsr_p_out);
    wire signed [15:0] p_dummy_b = $signed({lfsr_p_out[7:0], lfsr_p_out[15:8]});
    wire signed [15:0] p_dummy_w = $signed({lfsr_p_out[11:0], lfsr_p_out[15:12]});
    wire signed [15:0] s_dummy_a = $signed(lfsr_s_out);
    wire signed [15:0] s_dummy_b = $signed({lfsr_s_out[7:0], lfsr_s_out[15:8]});
    wire signed [15:0] s_dummy_w = $signed({lfsr_s_out[11:0], lfsr_s_out[15:12]});

    // =========================================================
    // Controllers (public control only)
    // =========================================================
    wire [7:0] p_addr_a, p_addr_b, p_addr_wa, p_addr_wb, p_zeta_addr;
    wire [7:0] s_addr_a, s_addr_b, s_addr_wa, s_addr_wb, s_zeta_addr;
    wire       p_we, s_we, p_done, s_done, p_bf_active, s_bf_active;

    ntt_controller ctrl_p (
        .clk(clk), .reset(rst), .start(start), .done(p_done),
        .rand_seed(lfsr_p_out),
        .addr_a(p_addr_a), .addr_b(p_addr_b),
        .addr_write_a(p_addr_wa), .addr_write_b(p_addr_wb),
        .we(p_we), .zeta_addr(p_zeta_addr),
        .bf_active(p_bf_active)
    );

    ntt_controller ctrl_s (
        .clk(clk), .reset(rst), .start(start_s), .done(s_done),
        .rand_seed(lfsr_s_out),
        .addr_a(s_addr_a), .addr_b(s_addr_b),
        .addr_write_a(s_addr_wa), .addr_write_b(s_addr_wb),
        .we(s_we), .zeta_addr(s_zeta_addr),
        .bf_active(s_bf_active)
    );

    assign done = p_done && s_done;

    // =========================================================
    // Twiddle ROM (PUBLIC): port A for ctrl_p, port B for ctrl_s
    // =========================================================
    wire signed [15:0] p_twiddle, s_twiddle;
    twiddle_rom rom (.clk(clk),
                     .addr(p_zeta_addr),   .zeta(p_twiddle),
                     .addr_b(s_zeta_addr), .zeta_b(s_twiddle));

    // =========================================================
    // Per-domain selection of the public control signals
    // =========================================================
    wire d0p = ~lead;   // domain 0 follows the primary controller

    wire [7:0] d0_addr_a  = d0p ? p_addr_a  : s_addr_a;
    wire [7:0] d0_addr_b  = d0p ? p_addr_b  : s_addr_b;
    wire [7:0] d0_addr_wa = d0p ? p_addr_wa : s_addr_wa;
    wire [7:0] d0_addr_wb = d0p ? p_addr_wb : s_addr_wb;
    wire       d0_we      = d0p ? p_we      : s_we;
    wire       d0_active  = d0p ? p_bf_active : s_bf_active;
    wire signed [15:0] d0_twiddle = d0p ? p_twiddle : s_twiddle;
    wire signed [15:0] d0_dummy_a = d0p ? p_dummy_a : s_dummy_a;
    wire signed [15:0] d0_dummy_b = d0p ? p_dummy_b : s_dummy_b;
    wire signed [15:0] d0_dummy_w = d0p ? p_dummy_w : s_dummy_w;

    wire [7:0] d1_addr_a  = d0p ? s_addr_a  : p_addr_a;
    wire [7:0] d1_addr_b  = d0p ? s_addr_b  : p_addr_b;
    wire [7:0] d1_addr_wa = d0p ? s_addr_wa : p_addr_wa;
    wire [7:0] d1_addr_wb = d0p ? s_addr_wb : p_addr_wb;
    wire       d1_we      = d0p ? s_we      : p_we;
    wire       d1_active  = d0p ? s_bf_active : p_bf_active;
    wire signed [15:0] d1_twiddle = d0p ? s_twiddle : p_twiddle;
    wire signed [15:0] d1_dummy_a = d0p ? s_dummy_a : p_dummy_a;
    wire signed [15:0] d1_dummy_b = d0p ? s_dummy_b : p_dummy_b;
    wire signed [15:0] d1_dummy_w = d0p ? s_dummy_w : p_dummy_w;

    // =========================================================
    // Address derivation (per domain)
    // =========================================================
    // Even butterfly at addr, odd butterfly at addr + 1; physical
    // address = logical[7:1].
    wire [7:0] d0_ra_odd = d0_addr_a  + 8'd1;
    wire [7:0] d0_rb_odd = d0_addr_b  + 8'd1;
    wire [7:0] d0_wa_odd = d0_addr_wa + 8'd1;
    wire [7:0] d0_wb_odd = d0_addr_wb + 8'd1;
    wire [7:0] d1_ra_odd = d1_addr_a  + 8'd1;
    wire [7:0] d1_rb_odd = d1_addr_b  + 8'd1;
    wire [7:0] d1_wa_odd = d1_addr_wa + 8'd1;
    wire [7:0] d1_wb_odd = d1_addr_wb + 8'd1;

    wire [6:0] d0_pa_even  = d0_addr_a[7:1];
    wire [6:0] d0_pb_even  = d0_addr_b[7:1];
    wire [6:0] d0_pa_odd   = d0_ra_odd[7:1];
    wire [6:0] d0_pb_odd   = d0_rb_odd[7:1];
    wire [6:0] d0_pwa_even = d0_addr_wa[7:1];
    wire [6:0] d0_pwb_even = d0_addr_wb[7:1];
    wire [6:0] d0_pwa_odd  = d0_wa_odd[7:1];
    wire [6:0] d0_pwb_odd  = d0_wb_odd[7:1];

    wire [6:0] d1_pa_even  = d1_addr_a[7:1];
    wire [6:0] d1_pb_even  = d1_addr_b[7:1];
    wire [6:0] d1_pa_odd   = d1_ra_odd[7:1];
    wire [6:0] d1_pb_odd   = d1_rb_odd[7:1];
    wire [6:0] d1_pwa_even = d1_addr_wa[7:1];
    wire [6:0] d1_pwb_even = d1_addr_wb[7:1];
    wire [6:0] d1_pwa_odd  = d1_wa_odd[7:1];
    wire [6:0] d1_pwb_odd  = d1_wb_odd[7:1];

    // External access helpers
    wire ext_is_even = ~ext_addr_w[0];
    wire ext_is_odd  =  ext_addr_w[0];
    wire [6:0] ext_phys_w = ext_addr_w[7:1];
    wire [6:0] ext_phys_r = ext_addr_r[7:1];
    wire ext_r_even = ~ext_addr_r[0];

    // =========================================================
    // Butterfly outputs — KEEP prevents cross-share retiming
    // =========================================================
    (* KEEP = "true", DONT_TOUCH = "true" *)
    wire signed [15:0] bf0_ao, bf0_bo;  // share0 even
    (* KEEP = "true", DONT_TOUCH = "true" *)
    wire signed [15:0] bf1_ao, bf1_bo;  // share0 odd
    (* KEEP = "true", DONT_TOUCH = "true" *)
    wire signed [15:0] bf2_ao, bf2_bo;  // share1 even
    (* KEEP = "true", DONT_TOUCH = "true" *)
    wire signed [15:0] bf3_ao, bf3_bo;  // share1 odd

    // =========================================================
    // Bank data outputs — KEEP prevents sharing with other banks
    // =========================================================
    (* KEEP = "true", DONT_TOUCH = "true" *)
    wire signed [15:0] s0e_da, s0e_db;  // share0 even
    (* KEEP = "true", DONT_TOUCH = "true" *)
    wire signed [15:0] s0o_da, s0o_db;  // share0 odd
    (* KEEP = "true", DONT_TOUCH = "true" *)
    wire signed [15:0] s1e_da, s1e_db;  // share1 even
    (* KEEP = "true", DONT_TOUCH = "true" *)
    wire signed [15:0] s1o_da, s1o_db;  // share1 odd

    // =========================================================
    // SHARE 0 — EVEN BANK (BFU0 a-side=portA, b-side=portB)
    // =========================================================
    wire s0e_ext = ext_we && !ext_share_sel && ext_is_even;
    wire s0e_wea = s0e_ext || d0_we;
    wire s0e_web = d0_we;

    wire [6:0] s0e_aa = s0e_ext             ? ext_phys_w :
                        (done && ext_re && !ext_share_sel && ext_r_even) ? ext_phys_r :
                        d0_we                ? d0_pwa_even :
                                               d0_pa_even;
    wire [6:0] s0e_ab = d0_we ? d0_pwb_even : d0_pb_even;

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
    wire s0o_wea = s0o_ext || d0_we;
    wire s0o_web = d0_we;

    wire [6:0] s0o_aa = s0o_ext             ? ext_phys_w :
                        (done && ext_re && !ext_share_sel && !ext_r_even) ? ext_phys_r :
                        d0_we                ? d0_pwa_odd :
                                               d0_pa_odd;
    wire [6:0] s0o_ab = d0_we ? d0_pwb_odd : d0_pb_odd;

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
    wire s1e_wea = s1e_ext || d1_we;
    wire s1e_web = d1_we;

    wire [6:0] s1e_aa = s1e_ext             ? ext_phys_w :
                        (done && ext_re && ext_share_sel && ext_r_even) ? ext_phys_r :
                        d1_we                ? d1_pwa_even :
                                               d1_pa_even;
    wire [6:0] s1e_ab = d1_we ? d1_pwb_even : d1_pb_even;

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
    wire s1o_wea = s1o_ext || d1_we;
    wire s1o_web = d1_we;

    wire [6:0] s1o_aa = s1o_ext             ? ext_phys_w :
                        (done && ext_re && ext_share_sel && !ext_r_even) ? ext_phys_r :
                        d1_we                ? d1_pwa_odd :
                                               d1_pa_odd;
    wire [6:0] s1o_ab = d1_we ? d1_pwb_odd : d1_pb_odd;

    wire signed [15:0] s1o_da_in = s1o_ext ? ext_data_w : bf3_ao;

    memory_bank s1_odd (
        .clk(clk),
        .we_a(s1o_wea), .addr_a(s1o_aa), .din_a(s1o_da_in), .dout_a(s1o_da),
        .we_b(s1o_web), .addr_b(s1o_ab), .din_b(bf3_bo),    .dout_b(s1o_db)
    );

    // =========================================================
    // Read-back path: one register per share domain (as rtl/bastion)
    // =========================================================
    reg rd0_en_d, rd1_en_d, rd_even_d;
    (* KEEP = "true", DONT_TOUCH = "true" *) reg signed [15:0] rd0_q;
    (* KEEP = "true", DONT_TOUCH = "true" *) reg signed [15:0] rd1_q;

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
    wire signed [15:0] bf0_ai = d0_active ? s0e_da : d0_dummy_a;
    wire signed [15:0] bf0_bi = d0_active ? s0e_db : d0_dummy_b;
    wire signed [15:0] bf0_wi = d0_active ? d0_twiddle : d0_dummy_w;

    butterfly bf0 (
        .clk(clk), .rst(rst),
        .a_in(bf0_ai), .b_in(bf0_bi), .w_in(bf0_wi),
        .a_out(bf0_ao), .b_out(bf0_bo)
    );

    // BFU1: share0, odd addresses
    wire signed [15:0] bf1_ai = d0_active ? s0o_da : d0_dummy_a;
    wire signed [15:0] bf1_bi = d0_active ? s0o_db : d0_dummy_b;
    wire signed [15:0] bf1_wi = d0_active ? d0_twiddle : d0_dummy_w;

    butterfly bf1 (
        .clk(clk), .rst(rst),
        .a_in(bf1_ai), .b_in(bf1_bi), .w_in(bf1_wi),
        .a_out(bf1_ao), .b_out(bf1_bo)
    );

    // BFU2: share1, even addresses
    wire signed [15:0] bf2_ai = d1_active ? s1e_da : d1_dummy_a;
    wire signed [15:0] bf2_bi = d1_active ? s1e_db : d1_dummy_b;
    wire signed [15:0] bf2_wi = d1_active ? d1_twiddle : d1_dummy_w;

    butterfly bf2 (
        .clk(clk), .rst(rst),
        .a_in(bf2_ai), .b_in(bf2_bi), .w_in(bf2_wi),
        .a_out(bf2_ao), .b_out(bf2_bo)
    );

    // BFU3: share1, odd addresses
    wire signed [15:0] bf3_ai = d1_active ? s1o_da : d1_dummy_a;
    wire signed [15:0] bf3_bi = d1_active ? s1o_db : d1_dummy_b;
    wire signed [15:0] bf3_wi = d1_active ? d1_twiddle : d1_dummy_w;

    butterfly bf3 (
        .clk(clk), .rst(rst),
        .a_in(bf3_ai), .b_in(bf3_bi), .w_in(bf3_wi),
        .a_out(bf3_ao), .b_out(bf3_bo)
    );

endmodule
