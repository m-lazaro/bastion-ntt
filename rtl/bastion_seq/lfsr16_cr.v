// =============================================================
// LFSR16_CR — 16-bit maximal-length LFSR with capture and reload
// =============================================================
// Same polynomial and seed as lfsr16 (x^16 + x^15 + x^13 + x^4 + 1,
// XAPP052). `capture` stores the current state; `reload` restores it
// at the next edge instead of stepping. The sequential core captures
// the state at start and restores it at the edge entering the third
// FLUSH cycle, so that pass 1 sees the same dummy and shuffle sequence
// as pass 0.
// =============================================================
module lfsr16_cr (
    input  wire        clk,
    input  wire        rst,
    input  wire        capture,
    input  wire        reload,
    output wire [15:0] out
);

    reg [15:0] sr;
    reg [15:0] cap;

    wire feedback = sr[15] ^ sr[14] ^ sr[12] ^ sr[3];

    always @(posedge clk) begin
        if (rst) begin
            sr  <= 16'hACE1;
            cap <= 16'hACE1;
        end else begin
            if (capture) cap <= sr;
            if (reload)  sr  <= cap;
            else         sr  <= {sr[14:0], feedback};
        end
    end

    assign out = sr;

endmodule
