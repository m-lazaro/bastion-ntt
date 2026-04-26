// =============================================================
// NTT_TOP — KYBER-512 NTT TOP MODULE
// =============================================================
// Address muxing:
//   - During NTT READ:  port A = ctrl_addr_a,  port B = ctrl_addr_b
//   - During NTT WRITE: port A = ctrl_write_a, port B = ctrl_write_b
//   - During ext write: port A = ext_addr_w
//   - During ext read:  port A = ext_addr_r
// =============================================================
module ntt_top (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    output wire        done,
    input  wire        ext_we,
    input  wire [7:0]  ext_addr_w,
    input  wire signed [15:0] ext_data_w,
    input  wire [7:0]  ext_addr_r,
    output wire signed [15:0] ext_data_r
);

    // --- Controller signals ---
    wire [7:0] ctrl_addr_a, ctrl_addr_b;
    wire [7:0] ctrl_addr_write_a, ctrl_addr_write_b;
    wire       ctrl_we;
    wire [7:0] ctrl_zeta_addr;

    // --- Butterfly signals ---
    wire signed [15:0] bf_a_out, bf_b_out;
    wire signed [15:0] twiddle;

    // --- BRAM port signals ---
    wire [7:0]         mem_addr_a, mem_addr_b;
    wire               mem_we_a, mem_we_b;
    wire signed [15:0] mem_din_a, mem_din_b;
    wire signed [15:0] mem_dout_a, mem_dout_b;

    // === Port A address mux (priority: ext_we > done > ctrl_we > ctrl_read) ===
    assign mem_addr_a = ext_we  ? ext_addr_w :
                        done    ? ext_addr_r :
                        ctrl_we ? ctrl_addr_write_a :
                                  ctrl_addr_a;

    // === Port B address mux (only used during NTT) ===
    assign mem_addr_b = ctrl_we ? ctrl_addr_write_b : ctrl_addr_b;

    // === Write enables ===
    assign mem_we_a = ext_we | ctrl_we;
    assign mem_we_b = ctrl_we;  // ext writes only go through port A

    // === Data inputs ===
    assign mem_din_a = ext_we ? ext_data_w : bf_a_out;
    assign mem_din_b = bf_b_out;

    // === External read output (always from port A) ===
    assign ext_data_r = mem_dout_a;

    // === Memory (TDP BRAM) ===
    memory mem (
        .clk(clk),
        .we_a(mem_we_a),  .addr_a(mem_addr_a), .din_a(mem_din_a), .dout_a(mem_dout_a),
        .we_b(mem_we_b),  .addr_b(mem_addr_b), .din_b(mem_din_b), .dout_b(mem_dout_b)
    );

    // === Controller ===
    ntt_controller ctrl (
        .clk(clk), .reset(rst), .start(start), .done(done),
        .addr_a(ctrl_addr_a),         .addr_b(ctrl_addr_b),
        .addr_write_a(ctrl_addr_write_a), .addr_write_b(ctrl_addr_write_b),
        .we(ctrl_we),
        .zeta_addr(ctrl_zeta_addr)
    );

    // === Twiddle ROM ===
    twiddle_rom rom (
        .clk(clk),
        .addr(ctrl_zeta_addr),
        .zeta(twiddle)
    );

    // === Butterfly (5-stage pipeline) ===
    butterfly bf (
        .clk(clk), .rst(rst),
        .a_in(mem_dout_a), .b_in(mem_dout_b), .w_in(twiddle),
        .a_out(bf_a_out),  .b_out(bf_b_out)
    );

endmodule
