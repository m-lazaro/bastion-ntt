`timescale 1ns / 1ps
// =============================================================
// TVLA TESTBENCH — PARALLEL / STREAMING-STATISTICS VARIANT
// =============================================================
// Same experiment as tb_tvla.v, but designed to be run as N
// independent jobs whose results are merged afterwards.
//
// Two differences vs tb_tvla.v:
//
//   1. LCG SEEDS ARE PARAMETERS. Passed with +SEED_IN=<hex> and
//      +SEED_SH=<hex>. Without this, parallel jobs would generate
//      byte-identical traces and add no statistical power. Seeds
//      must be far apart in the LCG sequence; use gen_seeds.py.
//
//   2. NO RAW TRACES ARE WRITTEN. Welch's t-statistic depends on
//      the traces only through (n, sum, sum-of-squares) per group
//      per cycle, so we accumulate those and emit ~4,034 rows at
//      the end. A 10^6-trace campaign that would occupy ~17 GB of
//      CSV instead produces ~200 kB per job, with no loss of
//      precision: the merged statistic is exact, not an estimate.
//
// Usage:
//   vvp sim_parallel +SEED_IN=cafebabe +SEED_SH=deadbeef +JOB=0
//
// Output: tvla_partial_<JOB>.csv, consumed by merge_tvla.py
// =============================================================
module tb_tvla_parallel;
    parameter N_TRACES    = 125000;   // per job; 8 jobs -> 10^6
    parameter MAX_CYCLES  = 4500;
    parameter Q           = 3329;

    reg         clk, rst, start;
    wire        done;
    reg         ext_we, ext_share_sel;
    reg  [7:0]  ext_addr_w;
    reg  signed [15:0] ext_data_w;
    reg  [7:0]  ext_addr_r;
    reg         ext_re;
    wire signed [15:0] ext_data_r;

    ntt_top dut (
        .clk(clk), .rst(rst), .start(start), .done(done),
        .ext_we(ext_we), .ext_share_sel(ext_share_sel),
        .ext_addr_w(ext_addr_w), .ext_data_w(ext_data_w),
        .ext_addr_r(ext_addr_r), .ext_re(ext_re), .ext_data_r(ext_data_r)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    reg signed [15:0] g_in     [0:255];
    reg signed [15:0] g_share0 [0:255];
    reg signed [15:0] g_share1 [0:255];
    reg signed [15:0] g_fixed  [0:255];
    integer i, t_idx, fd, cycle_cnt, min_cycles, job_id;
    integer is_fixed, tmp_s;
    reg [31:0] rng_in, rng_sh, dummy;
    reg [31:0] seed_in_arg, seed_sh_arg;
    reg [8*64:1] fname;

    reg [4:0] hw0_log [0:MAX_CYCLES-1];
    reg [4:0] hw1_log [0:MAX_CYCLES-1];

    // Sufficient statistics: per cycle, per channel, per group.
    reg [63:0] sum0_F [0:MAX_CYCLES-1];
    reg [63:0] sq0_F  [0:MAX_CYCLES-1];
    reg [63:0] sum1_F [0:MAX_CYCLES-1];
    reg [63:0] sq1_F  [0:MAX_CYCLES-1];
    reg [63:0] sum0_R [0:MAX_CYCLES-1];
    reg [63:0] sq0_R  [0:MAX_CYCLES-1];
    reg [63:0] sum1_R [0:MAX_CYCLES-1];
    reg [63:0] sq1_R  [0:MAX_CYCLES-1];
    integer n_F, n_R;

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

    task do_reset;
        begin
            rst=1; start=0;
            ext_we=0; ext_share_sel=0;
            ext_addr_w=0; ext_data_w=0; ext_addr_r=0; ext_re=0;
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
            ext_data_w = 0;   // clear the input bus: no share word may
            ext_addr_w = 0;   // stay at the write-mux inputs of either domain
            @(posedge clk);
            ext_share_sel = 1;
            ext_we = 1;
            for (i = 0; i < 256; i = i+1) begin
                ext_addr_w = i[7:0];
                ext_data_w = g_share1[i];
                @(posedge clk);
            end
            ext_we = 0;
            ext_data_w = 0;   // clear the input bus: no share word may
            ext_addr_w = 0;   // stay at the write-mux inputs of either domain
            ext_share_sel = 0;
            @(posedge clk);
        end
    endtask

    initial begin
        // ---- command-line configuration --------------------
        if (!$value$plusargs("SEED_IN=%h", seed_in_arg))
            seed_in_arg = 32'hCAFEBABE;
        if (!$value$plusargs("SEED_SH=%h", seed_sh_arg))
            seed_sh_arg = 32'hDEADBEEF;
        if (!$value$plusargs("JOB=%d", job_id))
            job_id = 0;

        $display("[TVLA-P] job=%0d seed_in=%h seed_sh=%h n_traces=%0d",
                 job_id, seed_in_arg, seed_sh_arg, N_TRACES);

        // ---- initialisation ---------------------------------
        for (i = 0; i < 256; i = i+1)
            g_fixed[i] = 16'sd42;
        rng_in = seed_in_arg;
        rng_sh = seed_sh_arg;
        n_F = 0;
        n_R = 0;
        min_cycles = MAX_CYCLES;
        for (i = 0; i < MAX_CYCLES; i = i+1) begin
            sum0_F[i] = 0;  sq0_F[i] = 0;
            sum1_F[i] = 0;  sq1_F[i] = 0;
            sum0_R[i] = 0;  sq0_R[i] = 0;
            sum1_R[i] = 0;  sq1_R[i] = 0;
        end

        // ---- main loop --------------------------------------
        for (t_idx = 0; t_idx < N_TRACES; t_idx = t_idx + 1) begin
            is_fixed = (t_idx % 2 == 0);

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
                hw0_log[cycle_cnt] = hw(dut.bf0.a_out);
                hw1_log[cycle_cnt] = hw(dut.bf2.a_out);
                cycle_cnt = cycle_cnt + 1;
                @(posedge clk);
            end
            if (cycle_cnt < min_cycles) min_cycles = cycle_cnt;

            // ---- accumulate instead of dumping --------------
            if (is_fixed) begin
                n_F = n_F + 1;
                for (i = 0; i < cycle_cnt; i = i+1) begin
                    sum0_F[i] = sum0_F[i] + hw0_log[i];
                    sq0_F[i]  = sq0_F[i]  + hw0_log[i]*hw0_log[i];
                    sum1_F[i] = sum1_F[i] + hw1_log[i];
                    sq1_F[i]  = sq1_F[i]  + hw1_log[i]*hw1_log[i];
                end
            end else begin
                n_R = n_R + 1;
                for (i = 0; i < cycle_cnt; i = i+1) begin
                    sum0_R[i] = sum0_R[i] + hw0_log[i];
                    sq0_R[i]  = sq0_R[i]  + hw0_log[i]*hw0_log[i];
                    sum1_R[i] = sum1_R[i] + hw1_log[i];
                    sq1_R[i]  = sq1_R[i]  + hw1_log[i]*hw1_log[i];
                end
            end

            @(posedge clk);
            if ((t_idx + 1) % 5000 == 0)
                $display("[TVLA-P] job=%0d  %0d / %0d traces",
                         job_id, t_idx + 1, N_TRACES);
        end

        // ---- emit partial statistics ------------------------
                $sformat(fname, "tvla_partial_%0d.csv", job_id);
        fd = $fopen(fname, "w");
        $fwrite(fd, "# job=%0d n_F=%0d n_R=%0d cycles=%0d seed_in=%h seed_sh=%h\n",
                job_id, n_F, n_R, min_cycles, seed_in_arg, seed_sh_arg);
        $fwrite(fd, "cycle,sum0_F,sq0_F,sum1_F,sq1_F,sum0_R,sq0_R,sum1_R,sq1_R\n");
        for (i = 0; i < min_cycles; i = i+1)
            $fwrite(fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n", i,
                    sum0_F[i], sq0_F[i], sum1_F[i], sq1_F[i],
                    sum0_R[i], sq0_R[i], sum1_R[i], sq1_R[i]);
        $fclose(fd);
        $display("[TVLA-P] job=%0d written to %0s (n_F=%0d n_R=%0d cycles=%0d)",
                 job_id, fname, n_F, n_R, min_cycles);
        $finish;
    end

    initial begin #200_000_000_000; $display("[WATCHDOG]"); $finish; end
endmodule
