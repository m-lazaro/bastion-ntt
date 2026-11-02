// =============================================================
// NTT CONTROLLER — SEQUENTIAL SCHEDULE (one datapath, two passes)
// =============================================================
// The lock-step controller (rtl/bastion/ntt_controller.v) extended to
// run the transform twice: pass 0 on share 0, three FLUSH cycles, then
// pass 1 on share 1. `pass` is the share index, used as the address
// MSB of the banks. In the FLUSH cycles the memory output latches are
// cleared (ntt_top) and the butterflies receive dummy operands, so the
// last butterfly of pass 0 leaves the pipeline before the first
// operands of pass 1 enter it, and no register goes directly from a
// value of one share to a value of the other. The LFSR state captured
// at `start` is restored at the edge that enters the third FLUSH cycle,
// so that cycle behaves as the start cycle and pass 1 replays the
// address, twiddle, dummy and shuffle sequence of pass 0 exactly
// PASS_OFFSET = 4,035 cycles later.
//
// Processes 2 butterflies per iteration (even + odd).
//
// j+=2 stepping with even/odd banking: conflict-free for all
// 7 NTT stages including len=2 (no crossbar needed).
//
// Shuffle (Level 2): XOR-bijection on group counter within blocks.
// Pipeline: BRAM(1) + butterfly(5) = 6 wait cycles.
// =============================================================
module ntt_controller_seq (
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
    output wire        bf_active,

    output reg         pass,          // share index of the current pass
    output wire        flush,         // FLUSH cycles between the passes
    output wire        busy,          // a pass or the flush is in progress
    output wire        lfsr_capture,  // capture the LFSR state at start
    output wire        lfsr_reload    // restore it in the second FLUSH cycle
);

    parameter N = 256;

    localparam IDLE  = 3'd0;
    localparam READ  = 3'd1;
    localparam WAIT  = 3'd2;
    localparam WRITE = 3'd3;
    localparam NEXT  = 3'd4;
    localparam DONE  = 3'd5;
    localparam FLUSH = 3'd6;

    reg [2:0] state;
    reg [7:0] len;
    reg [7:0] start_idx;
    reg [7:0] k;
    reg [2:0] pipe_cnt;
    reg [1:0] flush_cnt;    // FLUSH cycle 0, 1, 2

    // Shuffle state
    reg [7:0] gc;
    reg [7:0] shuffle_mask;
    reg [7:0] saved_j;

    wire [8:0] next_block = start_idx + (len << 1);

    // Groups of 2: num_groups = len/2
    wire [7:0] num_groups = len >> 1;

    assign bf_active = (state == WAIT);
    assign flush     = (state == FLUSH);
    assign busy      = (state != IDLE) && (state != DONE);

    assign lfsr_capture = (state == IDLE) && start;
    assign lfsr_reload  = (state == FLUSH) && (flush_cnt == 2'd1);

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
            pass          <= 1'b0;
            flush_cnt     <= 2'd0;
        end else begin
            case (state)

                IDLE: begin
                    done <= 0;
                    we   <= 0;
                    if (start) begin
                        pass         <= 1'b0;
                        addr_a       <= 0;
                        addr_b       <= 0;
                        addr_write_a <= 0;
                        addr_write_b <= 0;
                        zeta_addr    <= 0;
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
                            end else if (!pass) begin
                                pass      <= 1'b1;
                                flush_cnt <= 2'd0;
                                state     <= FLUSH;
                            end else begin
                                state <= DONE;
                            end
                        end
                    end
                end

                FLUSH: begin
                    // Two cycles that only drain the pipeline, then, in the
                    // third, restart for pass 1 from the state pass 0
                    // started in: the LFSR, reloaded at the edge entering
                    // this cycle, holds the state it had at start, so the
                    // shuffle mask and every later value repeat pass 0's.
                    if (flush_cnt != 2'd2) begin
                        flush_cnt <= flush_cnt + 2'd1;
                    end else begin
                        addr_a       <= 0;
                        addr_b       <= 0;
                        addr_write_a <= 0;
                        addr_write_b <= 0;
                        zeta_addr    <= 0;
                        len          <= 128;
                        start_idx    <= 0;
                        gc           <= 0;
                        k            <= 1;
                        shuffle_mask <= rand_seed[7:0];
                        state        <= READ;
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
