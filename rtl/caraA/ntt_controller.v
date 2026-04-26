// =============================================================
// NTT CONTROLLER — KYBER-512 CLEAN (PQClean Compatible)
// =============================================================
// Pipeline: BRAM read (1 cycle) + 5-stage butterfly = 6 wait cycles
//
//   Cycle   State     Event
//   ------  --------  ------------------------------------------
//   N       READ      addr_a/addr_b/zeta_addr presented
//   N+1     WAIT(0)   BRAM + ROM latch addresses
//   N+2     WAIT(1)   data_a/data_b/zeta valid → butterfly S1 latches
//   N+3     WAIT(2)   butterfly S2: multiply (zeta * b)
//   N+4     WAIT(3)   butterfly S3: Montgomery part 1
//   N+5     WAIT(4)   butterfly S4: Montgomery part 2
//   N+6     WAIT(5)   butterfly S5: a_out/b_out VALID
//   N+7     WRITE     we=1 → memory captures results
//   N+8     NEXT      advance j/k/len
// =============================================================
module ntt_controller (
    input  wire       clk,
    input  wire       reset,
    input  wire       start,

    output reg  [7:0] addr_a,
    output reg  [7:0] addr_b,

    output reg        we,
    output reg  [7:0] addr_write_a,
    output reg  [7:0] addr_write_b,

    output reg  [7:0] zeta_addr,
    output reg        done
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
    reg [7:0] j;
    reg [7:0] k;

    reg [2:0] pipe_cnt;

    wire [8:0] next_block = start_idx + (len << 1);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state     <= IDLE;
            len       <= 128;
            start_idx <= 0;
            j         <= 0;
            k         <= 0;
            we        <= 0;
            done      <= 0;
            pipe_cnt  <= 0;
            zeta_addr <= 0;
            addr_a    <= 0;
            addr_b    <= 0;
            addr_write_a <= 0;
            addr_write_b <= 0;
        end else begin
            case (state)

                IDLE: begin
                    done <= 0;
                    we   <= 0;
                    if (start) begin
                        len       <= 128;
                        start_idx <= 0;
                        j         <= 0;
                        k         <= 1;
                        state     <= READ;
                    end
                end

                READ: begin
                    addr_a    <= start_idx + j;
                    addr_b    <= start_idx + j + len;
                    zeta_addr <= k;
                    we        <= 0;
                    pipe_cnt  <= 0;
                    state     <= WAIT;
                end

                // 6 wait cycles: BRAM(1) + butterfly S1-S5
                WAIT: begin
                    pipe_cnt <= pipe_cnt + 1;
                    if (pipe_cnt == 3'd5)
                        state <= WRITE;
                end

                WRITE: begin
                    addr_write_a <= start_idx + j;
                    addr_write_b <= start_idx + j + len;
                    we    <= 1;
                    state <= NEXT;
                end

                NEXT: begin
                    we <= 0;
                    if (j < len - 1) begin
                        j     <= j + 1;
                        state <= READ;
                    end else begin
                        j <= 0;
                        k <= k + 1;

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
