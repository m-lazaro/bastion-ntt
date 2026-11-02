// =============================================================
// MEMORY BANK, SEQUENTIAL CORE — 256 x 16-bit TRUE DUAL-PORT
// =============================================================
// One bank holds the same parity class of both shares: address
// {share, logical[7:1]}. Read-first, 1-cycle latency, as memory_bank.
// `clr_a` / `clr_b` reset the output latch of each port synchronously
// (RSTRAM of the RAMB18E1); a write in the same cycle still happens.
// The core clears the latches between the passes and outside active
// accesses, so no latch goes directly from a word of one share to a
// word of the other.
// =============================================================
(* KEEP_HIERARCHY = "yes" *)
module memory_bank_seq (
    input  wire               clk,
    input  wire               we_a,
    input  wire               clr_a,
    input  wire [7:0]         addr_a,
    input  wire signed [15:0] din_a,
    output reg  signed [15:0] dout_a,
    input  wire               we_b,
    input  wire               clr_b,
    input  wire [7:0]         addr_b,
    input  wire signed [15:0] din_b,
    output reg  signed [15:0] dout_b
);

    (* ram_style = "block", KEEP = "true", DONT_TOUCH = "true" *)
    reg signed [15:0] mem [0:255];

    always @(posedge clk) begin
        if (we_a) mem[addr_a] <= din_a;
        if (clr_a) dout_a <= 16'sd0;
        else       dout_a <= mem[addr_a];
    end

    always @(posedge clk) begin
        if (we_b) mem[addr_b] <= din_b;
        if (clr_b) dout_b <= 16'sd0;
        else       dout_b <= mem[addr_b];
    end

endmodule
