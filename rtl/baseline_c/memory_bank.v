// =============================================================
// MEMORY BANK — 128 x 16-bit TRUE DUAL-PORT (BRAM-INFERRED)
// =============================================================
// Used for even/odd address split within each share.
// Physical address = logical_addr[7:1].
// BASELINE C: 2 instances total (even + odd), single unmasked polynomial.
//
// No preservation attributes: same synthesis freedom as Baseline B.
//   ram_style="block" is a primitive-style directive only, and forces the
//   RAMB18 inference that Baseline B obtains implicitly (a two-write-port
//   array cannot map to distributed RAM).
// =============================================================
module memory_bank (
    input  wire               clk,
    input  wire               we_a,
    input  wire [6:0]         addr_a,
    input  wire signed [15:0] din_a,
    output reg  signed [15:0] dout_a,
    input  wire               we_b,
    input  wire [6:0]         addr_b,
    input  wire signed [15:0] din_b,
    output reg  signed [15:0] dout_b
);

    (* ram_style = "block" *)
    reg signed [15:0] mem [0:127];

    always @(posedge clk) begin
        if (we_a) mem[addr_a] <= din_a;
        dout_a <= mem[addr_a];
    end

    always @(posedge clk) begin
        if (we_b) mem[addr_b] <= din_b;
        dout_b <= mem[addr_b];
    end

endmodule
