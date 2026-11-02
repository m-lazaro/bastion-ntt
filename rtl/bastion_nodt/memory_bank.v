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
// MEMORY BANK — 128 x 16-bit TRUE DUAL-PORT (BRAM-INFERRED)
// =============================================================
// Used for even/odd address split within each share.
// Physical address = logical_addr[7:1].
// 4 instances total: 2 per share × 2 shares.
//
// SIDE-CHANNEL HARDENING ATTRIBUTES:
//   KEEP_HIERARCHY preserves module boundaries through synthesis,
//   preventing Vivado from flattening and sharing logic across
//   share-domain instantiations.
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
