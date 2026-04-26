// =============================================================
// MEMORY BANK — 128 x 16-bit TRUE DUAL-PORT (BRAM-INFERRED)
// =============================================================
// Used for even/odd address split within each share.
// Physical address = logical_addr[7:1].
// 8 instances total: 2 per share × 2 shares.
//
// SIDE-CHANNEL HARDENING ATTRIBUTES:
//   KEEP_HIERARCHY preserves module boundaries through synthesis,
//   preventing Vivado from flattening and sharing logic across
//   share-domain instantiations.
// =============================================================
(* KEEP_HIERARCHY = "yes" *)
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

    (* ram_style = "block", KEEP = "true", DONT_TOUCH = "true" *)
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
