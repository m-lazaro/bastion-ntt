// =============================================================
// LFSR16 — 16-bit Maximal-Length PRNG
// =============================================================
// Polynomial: x^16 + x^15 + x^13 + x^4 + 1 (XAPP052)
// Period: 2^16 - 1 = 65535
// Purpose: Generate pseudo-random dummy data for uniform
//          power consumption during butterfly idle cycles.
// =============================================================
module lfsr16 (
    input  wire        clk,
    input  wire        rst,
    output wire [15:0] out
);

    reg [15:0] sr;

    wire feedback = sr[15] ^ sr[14] ^ sr[12] ^ sr[3];

    always @(posedge clk) begin
        if (rst)
            sr <= 16'hACE1;   // non-zero seed (mandatory for LFSR)
        else
            sr <= {sr[14:0], feedback};
    end

    assign out = sr;

endmodule
