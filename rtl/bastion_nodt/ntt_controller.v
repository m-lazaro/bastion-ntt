// =============================================================
// NTT CONTROLLER — MASKED DUAL-SHARE (2 BFU per share)
// =============================================================
// Processes 2 butterflies per iteration (even + odd).
// Both shares use the same addresses and zeta simultaneously
// but are routed to separate memory banks and BFUs in ntt_top.
//
// j+=2 stepping with even/odd banking: conflict-free for all
// 7 NTT stages including len=2 (no crossbar needed).
//
// Shuffle (Level 2): XOR-bijection on group counter within blocks.
// Pipeline: BRAM(1) + butterfly(5) = 6 wait cycles.
// =============================================================
module ntt_controller (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire [15:0] rand_seed,

    output reg  [7:0]  addr_a,
    output reg  [7:0]  addr_b,

    output reg         we,
    output reg  [7:0]  addr_write_a,
    output reg  [7:0]  addr_write_b,

    output reg  [7:0]  zeta_addr,
    output reg         done,
    output wire        bf_active
);

    parameter N = 256;

    localparam IDLE  = 3'd0;
    localparam READ  = 3'd1;
    localparam WAIT  = 3'd2;
    localparam WRITE = 3'd3;
    localparam NEXT  = 3'd4;
    localparam DONE  = 3'd5;

    reg [2:0] state;
    reg [7:0] len;
    reg [7:0] start_idx;
    reg [7:0] k;
    reg [2:0] pipe_cnt;

    // Shuffle state
    reg [7:0] gc;
    reg [7:0] shuffle_mask;
    reg [7:0] saved_j;

    wire [8:0] next_block = start_idx + (len << 1);

    assign bf_active = (state == WAIT);

    // Groups of 2: num_groups = len/2
    wire [7:0] num_groups = len >> 1;
    wire [7:0] gs = gc ^ (shuffle_mask & (num_groups - 8'd1));
    wire [7:0] shuffled_j = gs << 1;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state     <= IDLE;
            len       <= 128;
            start_idx <= 0;
            k         <= 0;
            we        <= 0;
            done      <= 0;
            pipe_cnt  <= 0;
            zeta_addr <= 0;
            addr_a    <= 0;
            addr_b    <= 0;
            addr_write_a <= 0;
            addr_write_b <= 0;
            gc            <= 0;
            shuffle_mask  <= 0;
            saved_j       <= 0;
        end else begin
            case (state)

                IDLE: begin
                    done <= 0;
                    we   <= 0;
                    if (start) begin
                        len          <= 128;
                        start_idx    <= 0;
                        gc           <= 0;
                        k            <= 1;
                        shuffle_mask <= rand_seed[7:0];
                        state        <= READ;
                    end
                end

                READ: begin
                    addr_a    <= start_idx + shuffled_j;
                    addr_b    <= start_idx + shuffled_j + len;
                    saved_j   <= shuffled_j;
                    zeta_addr <= k;
                    we        <= 0;
                    pipe_cnt  <= 0;
                    state     <= WAIT;
                end

                WAIT: begin
                    pipe_cnt <= pipe_cnt + 1;
                    if (pipe_cnt == 3'd5)
                        state <= WRITE;
                end

                WRITE: begin
                    addr_write_a <= start_idx + saved_j;
                    addr_write_b <= start_idx + saved_j + len;
                    we    <= 1;
                    state <= NEXT;
                end

                NEXT: begin
                    we <= 0;
                    if (gc + 8'd1 < num_groups) begin
                        gc    <= gc + 8'd1;
                        state <= READ;
                    end else begin
                        gc           <= 0;
                        k            <= k + 1;
                        shuffle_mask <= rand_seed[7:0];

                        if (next_block < N) begin
                            start_idx <= next_block[7:0];
                            state     <= READ;
                        end else begin
                            start_idx <= 0;
                            if (len > 2) begin
                                len   <= len >> 1;
                                state <= READ;
                            end else begin
                                state <= DONE;
                            end
                        end
                    end
                end

                DONE: begin
                    done <= 1;
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule
