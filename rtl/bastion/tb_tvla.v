`timescale 1ns / 1ps
// =============================================================
// TVLA TESTBENCH — Fixed-vs-Random Leakage Assessment (v3)
// =============================================================
// Methodology: Schneider & Moradi (JCE 2016)
//
// Changes vs v2:
//
//   BUG FIX #1 — Observe one BFU per share, not two of the same.
//     Per ntt_top.v architecture:
//         BFU0, BFU1 -> share 0
//         BFU2, BFU3 -> share 1
//     We now log HW of dut.bf0.a_out (share 0) and
//     dut.bf2.a_out (share 1). The CSV channel labels
//     ("s0", "s1") now correspond to the real shares.
//
//   BUG FIX #2 — Equalize PRNG consumption between fixed and
//     random traces. In v2, the fixed branch skipped 256 LCG
//     advances while the random branch consumed them. The share
//     generation that followed therefore started from a different
//     LCG state depending on the input class, introducing a
//     *statistical* fixed-vs-random difference in the shares
//     themselves — indistinguishable from genuine leakage under
//     Welch's t-test. We now advance the LCG the same number of
//     times in both branches (advances are discarded in the
//     fixed case), so the share distribution is identical across
//     classes.
//
//   BUG FIX #3 — Decorrelate input and share streams by using two
//     independent LCG states (`rng_in` for inputs, `rng_sh` for
//     shares). This removes any residual correlation between a
//     random input polynomial and its corresponding share 0.
// =============================================================
module tb_tvla;

    parameter N_TRACES    = 30000;
    parameter MAX_CYCLES  = 4500;
    parameter Q           = 3329;

    reg         clk, rst, start;
    wire        done;
    reg         ext_we, ext_share_sel;
    reg  [7:0]  ext_addr_w;
    reg  signed [15:0] ext_data_w;
    reg  [7:0]  ext_addr_r;
    wire signed [15:0] ext_data_r;

    ntt_top dut (
        .clk(clk), .rst(rst), .start(start), .done(done),
        .ext_we(ext_we), .ext_share_sel(ext_share_sel),
        .ext_addr_w(ext_addr_w), .ext_data_w(ext_data_w),
        .ext_addr_r(ext_addr_r), .ext_data_r(ext_data_r)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    reg signed [15:0] g_in     [0:255];
    reg signed [15:0] g_share0 [0:255];
    reg signed [15:0] g_share1 [0:255];
    reg signed [15:0] g_fixed  [0:255];

    integer i, t_idx, fd, cycle_cnt;
    integer is_fixed, tmp_s;
    reg [31:0] rng_in, rng_sh, dummy;

    reg [4:0] hw0_log [0:MAX_CYCLES-1];  // share 0 (BFU0)
    reg [4:0] hw1_log [0:MAX_CYCLES-1];  // share 1 (BFU2)

    // ---------------------------------------------------------
    function [4:0] hw;
        input [15:0] val;
        integer k;
        begin
            hw = 0;
            for (k = 0; k < 16; k = k + 1)
                hw = hw + val[k];
        end
    endfunction

    function [31:0] next_rng;
        input [31:0] state;
        begin
            next_rng = state * 32'd1103515245 + 32'd12345;
        end
    endfunction

    // ---------------------------------------------------------
    task do_reset;
        begin
            rst=1; start=0;
            ext_we=0; ext_share_sel=0;
            ext_addr_w=0; ext_data_w=0; ext_addr_r=0;
            repeat(4) @(posedge clk);
            rst=0;
            repeat(2) @(posedge clk);
        end
    endtask

    task load_shares;
        begin
            ext_share_sel = 0;
            ext_we = 1;
            for (i = 0; i < 256; i = i+1) begin
                ext_addr_w = i[7:0];
                ext_data_w = g_share0[i];
                @(posedge clk);
            end
            ext_we = 0;
            @(posedge clk);

            ext_share_sel = 1;
            ext_we = 1;
            for (i = 0; i < 256; i = i+1) begin
                ext_addr_w = i[7:0];
                ext_data_w = g_share1[i];
                @(posedge clk);
            end
            ext_we = 0;
            ext_share_sel = 0;
            @(posedge clk);
        end
    endtask

    // ---------------------------------------------------------
    initial begin
        for (i = 0; i < 256; i = i+1)
            g_fixed[i] = 16'sd42;

        rng_in = 32'hCAFEBABE;
        rng_sh = 32'hDEADBEEF;

        fd = $fopen("tvla_traces.csv", "w");
        $fwrite(fd, "trace_id,type,share");
        for (i = 0; i < MAX_CYCLES; i = i+1)
            $fwrite(fd, ",c%0d", i);
        $fwrite(fd, "\n");

        for (t_idx = 0; t_idx < N_TRACES; t_idx = t_idx + 1) begin

            is_fixed = (t_idx % 2 == 0);

            // Balanced PRNG consumption: both branches advance
            // rng_in 256 times
            if (is_fixed) begin
                for (i = 0; i < 256; i = i+1) begin
                    rng_in = next_rng(rng_in);
                    dummy  = rng_in;
                    g_in[i] = g_fixed[i];
                end
            end else begin
                for (i = 0; i < 256; i = i+1) begin
                    rng_in = next_rng(rng_in);
                    g_in[i] = rng_in % Q;
                end
            end

            // Shares from an independent stream
            for (i = 0; i < 256; i = i+1) begin
                rng_sh = next_rng(rng_sh);
                g_share0[i] = rng_sh % Q;
                tmp_s = g_in[i] - g_share0[i];
                if (tmp_s < 0) tmp_s = tmp_s + Q;
                g_share1[i] = tmp_s[15:0];
            end

            do_reset;
            load_shares;

            ext_we = 0;
            @(posedge clk); start <= 1;
            @(posedge clk); start <= 0;

            cycle_cnt = 0;
            while (!done && cycle_cnt < MAX_CYCLES) begin
                hw0_log[cycle_cnt] = hw(dut.bf0.a_out);   // share 0
                hw1_log[cycle_cnt] = hw(dut.bf2.a_out);   // share 1
                cycle_cnt = cycle_cnt + 1;
                @(posedge clk);
            end

            $fwrite(fd, "%0d,%s,s0", t_idx, is_fixed ? "F" : "R");
            for (i = 0; i < cycle_cnt; i = i+1)
                $fwrite(fd, ",%0d", hw0_log[i]);
            $fwrite(fd, "\n");

            $fwrite(fd, "%0d,%s,s1", t_idx, is_fixed ? "F" : "R");
            for (i = 0; i < cycle_cnt; i = i+1)
                $fwrite(fd, ",%0d", hw1_log[i]);
            $fwrite(fd, "\n");

            @(posedge clk);

            if ((t_idx + 1) % 500 == 0)
                $display("[TVLA] Completed %0d / %0d traces",
                         t_idx + 1, N_TRACES);
        end

        $fclose(fd);
        $display("[TVLA] Traces written to tvla_traces.csv");
        $display("[TVLA] Run: python3 tvla_analyze.py");
        $finish;
    end

    initial begin #5_000_000_000; $display("[WATCHDOG]"); $finish; end

endmodule
