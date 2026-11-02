// =============================================================
// MEMORY — TRUE DUAL-PORT BRAM (Vivado-Inferred)
// =============================================================
// 256 x 16-bit, single address per port.
// Follows Xilinx UG901 TDP BRAM template exactly.
//
// Port A: addr_a selects read AND write location
// Port B: addr_b selects read AND write location
// Read latency: 1 cycle (synchronous).
// =============================================================
module memory (
    input  wire               clk,

    // Port A
    input  wire               we_a,
    input  wire [7:0]         addr_a,
    input  wire signed [15:0] din_a,
    output reg  signed [15:0] dout_a,

    // Port B
    input  wire               we_b,
    input  wire [7:0]         addr_b,
    input  wire signed [15:0] din_b,
    output reg  signed [15:0] dout_b
);

    (* ram_style = "block" *) reg signed [15:0] mem [0:255];

    // Port A: write-first
    always @(posedge clk) begin
        if (we_a)
            mem[addr_a] <= din_a;
        dout_a <= mem[addr_a];
    end

    // Port B: write-first
    always @(posedge clk) begin
        if (we_b)
            mem[addr_b] <= din_b;
        dout_b <= mem[addr_b];
    end

endmodule
