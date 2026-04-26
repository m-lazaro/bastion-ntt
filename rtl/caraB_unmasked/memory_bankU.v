// =============================================================
// MEMORY BANK — 64 x 16-bit TRUE DUAL-PORT
// =============================================================
// Banking: logical_addr[1:0] selects bank, [7:2] is physical addr.
// 4 instances total (banks 0-3).
// Read latency: 1 cycle. Write: write-first.
// =============================================================
module memory_bank (
    input  wire               clk,
    input  wire               we_a,
    input  wire [5:0]         addr_a,
    input  wire signed [15:0] din_a,
    output reg  signed [15:0] dout_a,
    input  wire               we_b,
    input  wire [5:0]         addr_b,
    input  wire signed [15:0] din_b,
    output reg  signed [15:0] dout_b
);

    reg signed [15:0] mem [0:63];

    always @(posedge clk) begin
        if (we_a) mem[addr_a] <= din_a;
        dout_a <= mem[addr_a];
    end

    always @(posedge clk) begin
        if (we_b) mem[addr_b] <= din_b;
        dout_b <= mem[addr_b];
    end

endmodule
