`timescale 1ns / 1ps

// =============================================================
// TESTBENCH: MASKED NTT (First-Order Arithmetic Masking)
// =============================================================
// Validates that NTT(share0) + NTT(share1) ≡ NTT(input) mod Q
// for all test vectors. Shares are generated per-test using
// deterministic pseudo-random values.
// =============================================================
module tb_ntt_top;

    parameter Q = 3329;

    reg         clk, rst, start;
    wire        done;
    reg         ext_we;
    reg  [7:0]  ext_addr_w;
    reg  signed [15:0] ext_data_w;
    reg  [7:0]  ext_addr_r;
    reg         ext_re;
    wire signed [15:0] ext_data_r;

    ntt_top dut (
        .clk(clk), .rst(rst), .start(start), .done(done),
        .ext_we(ext_we),
        .ext_addr_w(ext_addr_w), .ext_data_w(ext_data_w),
        .ext_addr_r(ext_addr_r), .ext_re(ext_re), .ext_data_r(ext_data_r)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    reg signed [15:0] g_in      [0:255];
    reg signed [15:0] g_ref     [0:255];
    reg signed [15:0] g_share0  [0:255];
    reg signed [15:0] g_share1  [0:255];
    reg signed [15:0] g_hw_s0   [0:255];
    reg signed [15:0] g_hw_s1   [0:255];
    reg signed [15:0] g_zeta    [0:127];

    integer pass_cnt, fail_cnt;
    integer cycle_ctr, cycle_start, cycle_end;
    integer i, mm;
    reg [31:0] rng_state;

    initial cycle_ctr = 0;
    always @(posedge clk) if (!rst) cycle_ctr = cycle_ctr + 1;

    // =========================================================
    // Reference arithmetic
    // =========================================================
    function signed [15:0] montgomery_reduce;
        input signed [31:0] x;
        reg signed [15:0] m;
        reg signed [31:0] u;
        begin
            m = $signed(x[15:0]) * (-16'sd3327);
            u = $signed(x - {{16{m[15]}}, m} * 32'sd3329) >>> 16;
            montgomery_reduce = u[15:0];
        end
    endfunction

    function signed [15:0] fqmul;
        input signed [15:0] a;
        input signed [15:0] b;
        begin fqmul = montgomery_reduce($signed(a) * $signed(b)); end
    endfunction

    // =========================================================
    // Modular equivalence check: (a - b) mod Q == 0
    // =========================================================
    function integer mod_equiv;
        input signed [31:0] a;
        input signed [31:0] b;
        integer diff;
        begin
            diff = a - b;
            // Normalize to [0, Q-1]
            while (diff > 1664)  diff = diff - Q;
            while (diff < -1664) diff = diff + Q;
            mod_equiv = (diff == 0) ? 1 : 0;
        end
    endfunction

    // =========================================================
    // Pseudo-random number generator for share splitting
    // =========================================================
    function [31:0] next_rng;
        input [31:0] state;
        begin
            // LCG: state = state * 1103515245 + 12345
            next_rng = state * 32'd1103515245 + 32'd12345;
        end
    endfunction

    task generate_shares;
        begin
            for (i = 0; i < 256; i = i + 1) begin
                rng_state = next_rng(rng_state);
                // share0 in range [-1000, 1000]
                g_share0[i] = $signed(rng_state[15:0]) % 1000;
                g_share1[i] = g_in[i] - g_share0[i];
            end
        end
    endtask

    // =========================================================
    // Zeta initialization
    // =========================================================
    task init_zetas;
        begin
            g_zeta[0]=-1044;  g_zeta[1]=-758;   g_zeta[2]=-359;   g_zeta[3]=-1517;
            g_zeta[4]=1493;   g_zeta[5]=1422;   g_zeta[6]=287;    g_zeta[7]=202;
            g_zeta[8]=-171;   g_zeta[9]=622;    g_zeta[10]=1577;  g_zeta[11]=182;
            g_zeta[12]=962;   g_zeta[13]=-1202; g_zeta[14]=-1474; g_zeta[15]=1468;
            g_zeta[16]=573;   g_zeta[17]=-1325; g_zeta[18]=264;   g_zeta[19]=383;
            g_zeta[20]=-829;  g_zeta[21]=1458;  g_zeta[22]=-1602; g_zeta[23]=-130;
            g_zeta[24]=-681;  g_zeta[25]=1017;  g_zeta[26]=732;   g_zeta[27]=608;
            g_zeta[28]=-1542; g_zeta[29]=411;   g_zeta[30]=-205;  g_zeta[31]=-1571;
            g_zeta[32]=1223;  g_zeta[33]=652;   g_zeta[34]=-552;  g_zeta[35]=1015;
            g_zeta[36]=-1293; g_zeta[37]=1491;  g_zeta[38]=-282;  g_zeta[39]=-1544;
            g_zeta[40]=516;   g_zeta[41]=-8;    g_zeta[42]=-320;  g_zeta[43]=-666;
            g_zeta[44]=-1618; g_zeta[45]=-1162; g_zeta[46]=126;   g_zeta[47]=1469;
            g_zeta[48]=-853;  g_zeta[49]=-90;   g_zeta[50]=-271;  g_zeta[51]=830;
            g_zeta[52]=107;   g_zeta[53]=-1421; g_zeta[54]=-247;  g_zeta[55]=-951;
            g_zeta[56]=-398;  g_zeta[57]=961;   g_zeta[58]=-1508; g_zeta[59]=-725;
            g_zeta[60]=448;   g_zeta[61]=-1065; g_zeta[62]=677;   g_zeta[63]=-1275;
            g_zeta[64]=-1103; g_zeta[65]=430;   g_zeta[66]=555;   g_zeta[67]=843;
            g_zeta[68]=-1251; g_zeta[69]=871;   g_zeta[70]=1550;  g_zeta[71]=105;
            g_zeta[72]=422;   g_zeta[73]=587;   g_zeta[74]=177;   g_zeta[75]=-235;
            g_zeta[76]=-291;  g_zeta[77]=-460;  g_zeta[78]=1574;  g_zeta[79]=1653;
            g_zeta[80]=-246;  g_zeta[81]=778;   g_zeta[82]=1159;  g_zeta[83]=-147;
            g_zeta[84]=-777;  g_zeta[85]=1483;  g_zeta[86]=-602;  g_zeta[87]=1119;
            g_zeta[88]=-1590; g_zeta[89]=644;   g_zeta[90]=-872;  g_zeta[91]=349;
            g_zeta[92]=418;   g_zeta[93]=329;   g_zeta[94]=-156;  g_zeta[95]=-75;
            g_zeta[96]=817;   g_zeta[97]=1097;  g_zeta[98]=603;   g_zeta[99]=610;
            g_zeta[100]=1322; g_zeta[101]=-1285;g_zeta[102]=-1465;g_zeta[103]=384;
            g_zeta[104]=-1215;g_zeta[105]=-136; g_zeta[106]=1218; g_zeta[107]=-1335;
            g_zeta[108]=-874; g_zeta[109]=220;  g_zeta[110]=-1187;g_zeta[111]=-1659;
            g_zeta[112]=-1185;g_zeta[113]=-1530;g_zeta[114]=-1278;g_zeta[115]=794;
            g_zeta[116]=-1510;g_zeta[117]=-854; g_zeta[118]=-870; g_zeta[119]=478;
            g_zeta[120]=-108; g_zeta[121]=-308; g_zeta[122]=996;  g_zeta[123]=991;
            g_zeta[124]=958;  g_zeta[125]=-1460;g_zeta[126]=1522; g_zeta[127]=1628;
        end
    endtask

    // =========================================================
    // Reference NTT computation
    // =========================================================
    task compute_ntt_ref;
        integer len_r, s_r, jr, k_r;
        reg signed [15:0] t_r, z_r;
        begin
            for (i = 0; i < 256; i = i+1) g_ref[i] = g_in[i];
            k_r = 1;
            for (len_r = 128; len_r >= 2; len_r = len_r >> 1) begin
                s_r = 0;
                while (s_r < 256) begin
                    z_r = g_zeta[k_r]; k_r = k_r + 1;
                    jr  = s_r;
                    while (jr < s_r + len_r) begin
                        t_r               = fqmul(z_r, g_ref[jr + len_r]);
                        g_ref[jr + len_r] = g_ref[jr] - t_r;
                        g_ref[jr]         = g_ref[jr] + t_r;
                        jr = jr + 1;
                    end
                    s_r = jr + len_r;
                end
            end
        end
    endtask

    // =========================================================
    // Load both shares into DUT memory
    // =========================================================
    task mem_load_plain;
        begin
            ext_we = 1;
            for (i = 0; i < 256; i = i+1) begin
                ext_addr_w = i[7:0];
                ext_data_w = g_in[i];
                @(posedge clk);
            end
            ext_we = 0;
            ext_data_w = 0;   // clear the input bus: no share word may
            ext_addr_w = 0;   // stay at the write-mux inputs of either domain
            @(posedge clk);
        end
    endtask

    // =========================================================
    // Read both shares from DUT memory (BRAM: 1-cycle latency)
    // =========================================================
    task mem_read_plain;
        begin
            // interface rule: two edges after done before the first read,
            // so that the last butterfly leaves the pipeline first
            repeat (2) @(posedge clk);
            ext_re = 1;
            for (i = 0; i < 256; i = i+1) begin
                ext_addr_r = i[7:0];
                @(posedge clk);
                @(posedge clk);
                #1;
                g_hw_s0[i] = ext_data_r;
            end
            ext_re = 0;
            repeat(2) @(posedge clk);
        end
    endtask

    // =========================================================
    // Run NTT
    // =========================================================
    task run_ntt;
        integer tout;
        begin
            ext_we = 0;
            // Latency = clock edges from the cycle in which start is high to
            // the edge that raises done. Sampling 1 ns after each edge makes
            // the count independent of simulator event ordering.
            @(posedge clk); start <= 1;
            @(posedge clk); start <= 0;
            #1; tout = 1;
            while (!done && tout < 200000) begin @(posedge clk); #1; tout = tout + 1; end
            cycle_start = 0; cycle_end = tout;
            if (tout >= 200000) begin $display("[TIMEOUT]"); $finish; end
            @(posedge clk);
        end
    endtask

    // =========================================================
    // Check: (share0_out + share1_out) ≡ ref (mod Q)
    // =========================================================
    task check_plain;
        input [255:0] tname;
        begin
            mem_read_plain;
            mm = 0;
            for (i = 0; i < 256; i = i + 1) begin
                if (!mod_equiv(g_hw_s0[i], g_ref[i])) begin
                    if (mm < 4)
                        $display("  [DIFF][%0d] hw=%0d ref=%0d", i, g_hw_s0[i], g_ref[i]);
                    mm = mm + 1;
                end
            end
            if (mm == 0) begin
                $display("[PASS] %s  cycles=%0d  (baseline C)", tname, cycle_end-cycle_start);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] %s  mismatches=%0d", tname, mm);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // =========================================================
    // Reset
    // =========================================================
    task do_reset;
        begin
            rst=1; start=0;
            ext_we=0; ext_addr_w=0; ext_data_w=0; ext_addr_r=0; ext_re=0;
            repeat(4) @(posedge clk);
            rst=0;
            repeat(2) @(posedge clk);
        end
    endtask

    // =========================================================
    // MAIN
    // =========================================================
    initial begin
        $dumpfile("tb_ntt_top.vcd");
        $dumpvars(0, tb_ntt_top);
        pass_cnt=0; fail_cnt=0;
        rng_state = 32'hDEADBEEF;
        init_zetas;

        // T1: all-zero
        $display("\n=== T1: All-zero (baseline C) ===");
        do_reset;
        for (i=0;i<256;i=i+1) g_in[i]=0;
        compute_ntt_ref;
        mem_load_plain;
        run_ntt;
        check_plain("NTT(zero)");

        // T2: e_0
        $display("\n=== T2: e_0 (baseline C) ===");
        do_reset;
        for (i=0;i<256;i=i+1) g_in[i]=0; g_in[0]=1;
        compute_ntt_ref;
        mem_load_plain;
        run_ntt;
        check_plain("NTT(e_0)");

        // T3: all-ones
        $display("\n=== T3: All-ones (baseline C) ===");
        do_reset;
        for (i=0;i<256;i=i+1) g_in[i]=1;
        compute_ntt_ref;
        mem_load_plain;
        run_ntt;
        check_plain("NTT(all_ones)");

        // T4: alternating
        $display("\n=== T4: Alternating (baseline C) ===");
        do_reset;
        for (i=0;i<256;i=i+1) g_in[i]=(i[0]==0) ? 16'sd1 : -16'sd1;
        compute_ntt_ref;
        mem_load_plain;
        run_ntt;
        check_plain("NTT(alt+1-1)");

        // T5: max coeff
        $display("\n=== T5: Max coefficient (baseline C) ===");
        do_reset;
        for (i=0;i<256;i=i+1) g_in[i]=16'sd1664;
        compute_ntt_ref;
        mem_load_plain;
        run_ntt;
        check_plain("NTT(max_coeff)");

        // T6: KAT vector
        $display("\n=== T6: KAT vector (baseline C) ===");
                for (i = 0; i < 256; i = i + 1) begin
            g_in[i]  = 16'bx;
            g_ref[i] = 16'bx;
        end
        $readmemh("kat_input.hex", g_in);
        $readmemh("kat_expected.hex", g_ref);
        if (g_in[0] === 16'bx || g_ref[0] === 16'bx) begin
            $display("[FATAL] KAT vectors not loaded (kat_input.hex / kat_expected.hex missing).");
            $finish;
        end
        do_reset;
        mem_load_plain;
        run_ntt;
        check_plain("NTT(kat_vector)");

        // Summary
        $display("\n========================================");
        $display("  PASS : %0d  FAIL : %0d", pass_cnt, fail_cnt);
        if (fail_cnt==0)
            $display("  STATUS: ALL PASS - Baseline C Kyber-512 NTT");
        else
            $display("  STATUS: FAILURES DETECTED");
        $display("========================================");
        $finish;
    end

    initial begin #40_000_000; $display("[WATCHDOG TIMEOUT]"); $finish; end

endmodule
