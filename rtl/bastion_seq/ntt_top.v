// =============================================================
// NTT_TOP — FIRST-ORDER MASKED, SEQUENTIAL SCHEDULE (one datapath)
// =============================================================
// The datapath of Baseline C (rtl/baseline_c): one even and one odd
// bank, two butterflies, one controller, one LFSR. Following Reparaz et
// al., the two shares are transformed one after the other on it:
//
//   banks      : 256 x 16 each; address {share, logical[7:1]}, so one
//                bank holds the same parity class of both shares.
//   controller : ntt_controller_seq runs pass 0 on share 0, three FLUSH
//                cycles, then pass 1 on share 1; `pass` drives the
//                address MSB. The three cycles let the last butterfly of
//                pass 0 leave the five-stage pipeline before the first
//                operands of pass 1 enter it.
//   LFSR       : lfsr16_cr captures its state at start and restores it
//                at the edge entering the third FLUSH cycle, so pass 1
//                replays the address, twiddle, dummy and shuffle sequence
//                of pass 0 exactly 4,035 cycles later.
//   latches    : the bank output latches are cleared in the FLUSH cycles
//                and whenever neither a pass nor a read-back is in
//                progress, and during read-back both banks read the
//                selected share, so no latch goes directly from a word of
//                one share to a word of the other. Between consecutive
//                iterations the butterfly pipeline is refilled with L1
//                dummy operands, so the same holds for its registers.
//
// Synthesis attributes: the preservation attributes of the lock-step
// core (rtl/bastion), so that the three schedules share one synthesis
// regime.
//
// INTERFACE: as rtl/bastion (ext_share_sel selects the share for load
// and read-back), including the requirements on the input bus and the
// read protocol: drive ext_data_w and ext_addr_w to zero after loading;
// read only after done and two further clock edges (the last butterfly
// of pass 1 drains), with ext_re low for two cycles between shares.
//
// Latency: 8,069 cycles from the cycle in which `start` is high to the
// edge that raises `done` (two passes of 4,032, the three flush cycles,
// and one cycle each to leave IDLE and to register done).
// =============================================================
(* KEEP_HIERARCHY = "yes" *)
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
    // Controller and LFSR
    // =========================================================
    wire [7:0] ctrl_addr_a, ctrl_addr_b;
    wire [7:0] ctrl_addr_wa, ctrl_addr_wb;
    wire       ctrl_we;
    wire [7:0] ctrl_zeta_addr;
    wire       bf_active;
    wire       pass, flush, busy, lfsr_capture, lfsr_reload;

    wire [15:0] lfsr_out;
    lfsr16_cr prng (.clk(clk), .rst(rst),
                    .capture(lfsr_capture), .reload(lfsr_reload),
                    .out(lfsr_out));

    wire signed [15:0] dummy_a = $signed(lfsr_out);
    wire signed [15:0] dummy_b = $signed({lfsr_out[7:0], lfsr_out[15:8]});
    wire signed [15:0] dummy_w = $signed({lfsr_out[11:0], lfsr_out[15:12]});

    ntt_controller_seq ctrl (
        .clk(clk), .reset(rst), .start(start), .done(done),
        .rand_seed(lfsr_out),
        .addr_a(ctrl_addr_a), .addr_b(ctrl_addr_b),
        .addr_write_a(ctrl_addr_wa), .addr_write_b(ctrl_addr_wb),
        .we(ctrl_we), .zeta_addr(ctrl_zeta_addr),
        .bf_active(bf_active),
        .pass(pass), .flush(flush), .busy(busy),
        .lfsr_capture(lfsr_capture), .lfsr_reload(lfsr_reload)
    );

    // =========================================================
    // Twiddle ROM (public)
    // =========================================================
    wire signed [15:0] twiddle;
    twiddle_rom rom (.clk(clk), .addr(ctrl_zeta_addr), .zeta(twiddle));

    // =========================================================
    // Address derivation: {share, logical[7:1]}
    // =========================================================
    wire [7:0] ra_odd = ctrl_addr_a  + 8'd1;
    wire [7:0] rb_odd = ctrl_addr_b  + 8'd1;
    wire [7:0] wa_odd = ctrl_addr_wa + 8'd1;
    wire [7:0] wb_odd = ctrl_addr_wb + 8'd1;

    wire [7:0] pa_even  = {pass, ctrl_addr_a[7:1]};
    wire [7:0] pb_even  = {pass, ctrl_addr_b[7:1]};
    wire [7:0] pa_odd   = {pass, ra_odd[7:1]};
    wire [7:0] pb_odd   = {pass, rb_odd[7:1]};
    wire [7:0] pwa_even = {pass, ctrl_addr_wa[7:1]};
    wire [7:0] pwb_even = {pass, ctrl_addr_wb[7:1]};
    wire [7:0] pwa_odd  = {pass, wa_odd[7:1]};
    wire [7:0] pwb_odd  = {pass, wb_odd[7:1]};

    wire ext_is_even = ~ext_addr_w[0];
    wire ext_is_odd  =  ext_addr_w[0];
    wire [7:0] ext_phys_w = {ext_share_sel, ext_addr_w[7:1]};
    wire [7:0] ext_phys_r = {ext_share_sel, ext_addr_r[7:1]};
    wire ext_r_even = ~ext_addr_r[0];

    // Output latches are cleared in the FLUSH cycles and whenever neither
    // a pass nor a read-back is in progress (port A), or no pass is in
    // progress (port B, unused by the read-back).
    wire reading = done && ext_re;
    wire clr_a   = flush || (!busy && !reading);
    wire clr_b   = flush || !busy;

    // =========================================================
    // Butterfly and bank outputs
    // =========================================================
    (* KEEP = "true", DONT_TOUCH = "true" *)
    wire signed [15:0] bf0_ao, bf0_bo;  // even
    (* KEEP = "true", DONT_TOUCH = "true" *)
    wire signed [15:0] bf1_ao, bf1_bo;  // odd

    (* KEEP = "true", DONT_TOUCH = "true" *)
    wire signed [15:0] e_da, e_db;      // even bank
    (* KEEP = "true", DONT_TOUCH = "true" *)
    wire signed [15:0] o_da, o_db;      // odd bank

    // =========================================================
    // EVEN BANK (BFU0 a-side=portA, b-side=portB)
    // =========================================================
    wire e_ext = ext_we && ext_is_even;
    wire e_wea = e_ext || ctrl_we;
    wire e_web = ctrl_we;

    // During read-back both banks read the same physical address of the
    // selected share, so neither latch holds a word of the other share.
    wire [7:0] e_aa = e_ext                ? ext_phys_w :
                      reading              ? ext_phys_r :
                      ctrl_we              ? pwa_even :
                                             pa_even;
    wire [7:0] e_ab = ctrl_we ? pwb_even : pb_even;

    wire signed [15:0] e_da_in = e_ext ? ext_data_w : bf0_ao;

    memory_bank_seq even_bank (
        .clk(clk),
        .we_a(e_wea), .clr_a(clr_a), .addr_a(e_aa), .din_a(e_da_in), .dout_a(e_da),
        .we_b(e_web), .clr_b(clr_b), .addr_b(e_ab), .din_b(bf0_bo),  .dout_b(e_db)
    );

    // =========================================================
    // ODD BANK (BFU1 a-side=portA, b-side=portB)
    // =========================================================
    wire o_ext = ext_we && ext_is_odd;
    wire o_wea = o_ext || ctrl_we;
    wire o_web = ctrl_we;

    wire [7:0] o_aa = o_ext                 ? ext_phys_w :
                      reading               ? ext_phys_r :
                      ctrl_we               ? pwa_odd :
                                              pa_odd;
    wire [7:0] o_ab = ctrl_we ? pwb_odd : pb_odd;

    wire signed [15:0] o_da_in = o_ext ? ext_data_w : bf1_ao;

    memory_bank_seq odd_bank (
        .clk(clk),
        .we_a(o_wea), .clr_a(clr_a), .addr_a(o_aa), .din_a(o_da_in), .dout_a(o_da),
        .we_b(o_web), .clr_b(clr_b), .addr_b(o_ab), .din_b(bf1_bo),  .dout_b(o_db)
    );

    // =========================================================
    // Read-back path: one register (as Baseline C)
    // =========================================================
    // Loads only after done with ext_re high, enable and parity delayed
    // by one cycle; zero otherwise. With ext_re low for two cycles
    // between the shares, it goes through zero between a word of share 0
    // and a word of share 1.
    reg rd_en_d, rd_even_d;
    (* KEEP = "true", DONT_TOUCH = "true" *) reg signed [15:0] rd_q;

    always @(posedge clk) begin
        if (rst) begin
            rd_en_d   <= 1'b0;
            rd_even_d <= 1'b0;
            rd_q      <= 16'sd0;
        end else begin
            rd_en_d   <= reading;
            rd_even_d <= ext_r_even;
            rd_q      <= rd_en_d ? (rd_even_d ? e_da : o_da) : 16'sd0;
        end
    end

    assign ext_data_r = rd_q;

    // =========================================================
    // BUTTERFLIES — with dummy operation muxing (Level 1)
    // =========================================================
    wire signed [15:0] bf0_ai = bf_active ? e_da    : dummy_a;
    wire signed [15:0] bf0_bi = bf_active ? e_db    : dummy_b;
    wire signed [15:0] bf0_wi = bf_active ? twiddle : dummy_w;

    butterfly bf0 (
        .clk(clk), .rst(rst),
        .a_in(bf0_ai), .b_in(bf0_bi), .w_in(bf0_wi),
        .a_out(bf0_ao), .b_out(bf0_bo)
    );

    wire signed [15:0] bf1_ai = bf_active ? o_da    : dummy_a;
    wire signed [15:0] bf1_bi = bf_active ? o_db    : dummy_b;
    wire signed [15:0] bf1_wi = bf_active ? twiddle : dummy_w;

    butterfly bf1 (
        .clk(clk), .rst(rst),
        .a_in(bf1_ai), .b_in(bf1_bi), .w_in(bf1_wi),
        .a_out(bf1_ao), .b_out(bf1_bo)
    );

endmodule
