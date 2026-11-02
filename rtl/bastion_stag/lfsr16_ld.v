// =============================================================
// LFSR16_LD — 16-bit maximal-length LFSR with load and enable
// =============================================================
// Same polynomial and seed as lfsr16 (x^16 + x^15 + x^13 + x^4 + 1,
// XAPP052). `load` copies `load_val` into the register; otherwise the
// register steps only while `en` is high. The staggered core loads it
// with the state of the primary LFSR at `start` and enables it when
// the secondary controller starts, delta cycles later, so that the
// secondary domain sees the same dummy and shuffle sequence.
// =============================================================
module lfsr16_ld (
    input  wire        clk,
    input  wire        rst,
    input  wire        load,
    input  wire [15:0] load_val,
    input  wire        en,
    output wire [15:0] out
);

    reg [15:0] sr;

    wire feedback = sr[15] ^ sr[14] ^ sr[12] ^ sr[3];

    always @(posedge clk) begin
        if (rst)
            sr <= 16'hACE1;
        else if (load)
            sr <= load_val;
        else if (en)
            sr <= {sr[14:0], feedback};
    end

    assign out = sr;

endmodule
