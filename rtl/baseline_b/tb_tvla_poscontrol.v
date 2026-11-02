`timescale 1ns / 1ps
// =============================================================
// TVLA POSITIVE CONTROL — Baseline B (UNMASKED)
// =============================================================
// Purpose: instrument validation, not evaluation of Baseline B.
// The identical fixed-vs-random harness that reports max|t| = 3.96
// on the masked core is applied here to the hardened-but-unmasked
// Baseline B, which carries its coefficients in the clear. A
// correct harness MUST detect leakage here: max|t| should exceed
// the 4.5 threshold by a wide margin. A pass would indicate a
// broken instrument.
//
// Differences vs tb_tvla.v (the masked-core harness):
//   - No share split. Baseline B has no ext_share_sel and loads
//     the polynomial directly, so the fixed-vs-random contrast is
//     applied to the plaintext coefficient itself.
//   - One observation channel. There is no share 1; we log
//     HW(dut.bf0.a_out) only.
//   - N_TRACES = 5000. If B leaks it shows far below 30k; this is
//     ~20 min in RTL. Raise if the margin is unexpectedly thin.
//
// Everything else (LCG, fixed value 42, Welch analysis via the
// same tvla_analyze.py) is unchanged, so the two campaigns are
// directly comparable.
// =============================================================
module tb_tvla_posctrl;
    parameter N_TRACES    = 5000;
    parameter MAX_CYCLES  = 4500;
    parameter Q           = 3329;

    reg         clk, rst, start;
    wire        done;
    reg         ext_we;
    reg  [7:0]  ext_addr_w;
    reg  signed [15:0] ext_data_w;
    reg  [7:0]  ext_addr_r;
    wire signed [15:0] ext_data_r;

    // Baseline B top-level: no ext_share_sel port.
    ntt_top dut (
        .clk(clk), .rst(rst), .start(start), .done(done),
        .ext_we(ext_we),
        .ext_addr_w(ext_addr_w), .ext_data_w(ext_data_w),
        .ext_addr_r(ext_addr_r), .ext_data_r(ext_data_r)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    reg signed [15:0] g_in    [0:255];
    reg signed [15:0] g_fixed [0:255];
    integer i, t_idx, fd, cycle_cnt;
    integer is_fixed;
    reg [31:0] rng_in, dummy;
    reg [4:0] hw0_log [0:MAX_CYCLES-1];   // single channel: bf0.a_out

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
            ext_we=0; ext_addr_w=0; ext_data_w=0; ext_addr_r=0;
            repeat(4) @(posedge clk);
            rst=0;
            repeat(2) @(posedge clk);
        end
    endtask

    // Load the polynomial directly (no share split).
    task load_plain;
        begin
            ext_we = 1;
            for (i = 0; i < 256; i = i+1) begin
                ext_addr_w = i[7:0];
                ext_data_w = g_in[i];
                @(posedge clk);
            end
            ext_we = 0;
            @(posedge clk);
        end
    endtask

    initial begin
        for (i = 0; i < 256; i = i+1)
            g_fixed[i] = 16'sd42;
        rng_in = 32'hCAFEBABE;

        fd = $fopen("tvla_traces_posctrl.csv", "w");
        $fwrite(fd, "trace_id,type,share");
        for (i = 0; i < MAX_CYCLES; i = i+1)
            $fwrite(fd, ",c%0d", i);
        $fwrite(fd, "\n");

        for (t_idx = 0; t_idx < N_TRACES; t_idx = t_idx + 1) begin
            is_fixed = (t_idx % 2 == 0);
            // Balanced PRNG consumption across both classes.
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

            do_reset;
            load_plain;
            ext_we = 0;
            @(posedge clk); start <= 1;
            @(posedge clk); start <= 0;

            cycle_cnt = 0;
            while (!done && cycle_cnt < MAX_CYCLES) begin
                hw0_log[cycle_cnt] = hw(dut.bf0.a_out);
                cycle_cnt = cycle_cnt + 1;
                @(posedge clk);
            end

            $fwrite(fd, "%0d,%s,s0", t_idx, is_fixed ? "F" : "R");
            for (i = 0; i < cycle_cnt; i = i+1)
                $fwrite(fd, ",%0d", hw0_log[i]);
            $fwrite(fd, "\n");

            @(posedge clk);
            if ((t_idx + 1) % 500 == 0)
                $display("[TVLA-PC] Completed %0d / %0d traces",
                         t_idx + 1, N_TRACES);
        end

        $fclose(fd);
        $display("[TVLA-PC] Traces written to tvla_traces_posctrl.csv");
        $finish;
    end

    initial begin #5_000_000_000; $display("[WATCHDOG]"); $finish; end
endmodule
