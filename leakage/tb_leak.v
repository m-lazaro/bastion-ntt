`timescale 1ns / 1ps
// =============================================================
// LEAKAGE TESTBENCH: whole-design toggle traces
// =============================================================
// One configuration per compilation, chosen by a macro:
//   CFG_MASKED   rtl/bastion, rtl/bastion_nodt, rtl/bastion_seq
//   CFG_STAG     rtl/bastion_stag (adds the delta and order_rand inputs)
//   CFG_BASE_C   rtl/baseline_c (one share: the polynomial in the clear)
//   CFG_BASE_B   rtl/baseline_b (one share, one-edge read latency)
// Optional injected flaws (positive controls, Section 6.3 of the paper):
//   CTRL_C1      a register loads the sum of the two even-bank outputs
//   CTRL_C2      a register loads the share-0 and the share-1 even-bank
//                output in alternate cycles
// (C3, weak share randomness, is a property of the input file.)
//
// Plusargs:
//   +in=<hex>     inputs: per execution one flag word (bit 0 group,
//                 bit 1 order_rand, bit 2 skip: run it but record nothing,
//                 used to set the memory state for the next execution)
//                 then 256 words of share 0 and 256 of share 1 (the
//                 unmasked baselines use share 0 only)
//   +n=<count>    executions in the file
//   +out=<bin>    toggle traces, one uint16 row per execution
//   +delta=<d>    staggered core only
//   +chk=<hex>    optional: read-back words of every execution
//   +dump=<bin>   oracle mode: value of every register at the opening of
//                 the window and after every clock edge in it, instead of
//                 toggle traces; +names=<txt> lists the registers
//
// Every stimulus change happens on the falling edge, after the sample of
// the preceding rising edge has been taken, so the traces do not depend
// on simulator event ordering. The window opens before the first load
// edge and closes after the last read-back edge: loading, transform and
// read-back of both shares are all inside it.
// =============================================================
module tb_leak;

    reg         clk = 0;
    always #5 clk = ~clk;

    reg         rst, start;
    wire        done;
    reg         ext_we;
    reg         ext_share_sel;
    reg  [7:0]  ext_addr_w;
    reg  signed [15:0] ext_data_w;
    reg  [7:0]  ext_addr_r;
    reg         ext_re;
    wire signed [15:0] ext_data_r;
    reg  [12:0] delta;
    reg         order_rand;

    leak_wrap wrap (
        .clk(clk), .rst(rst), .start(start), .done(done),
        .ext_we(ext_we), .ext_share_sel(ext_share_sel),
        .ext_addr_w(ext_addr_w), .ext_data_w(ext_data_w),
        .ext_addr_r(ext_addr_r), .ext_re(ext_re), .ext_data_r(ext_data_r),
        .delta(delta), .order_rand(order_rand)
    );

`ifdef CFG_BASE_B
    localparam RD_LAT = 1;
`else
    localparam RD_LAT = 2;
`endif
`ifdef CFG_BASE_B
    localparam NSH = 1;
`elsif CFG_BASE_C
    localparam NSH = 1;
`else
    localparam NSH = 2;
`endif

    reg [15:0] inmem [0:513*20000-1];
    reg signed [15:0] rd [0:511];
    integer n, t, i, s, base, rowlen, samples, chk_fd;
    reg in_window, dump_mode;
    reg [1023:0] fin, fout, fchk, fdump, fnames;

    // Falling edge: take the sample of the preceding rising edge.
    reg skip;   // oracle mode: execution that only sets the memory state
`ifdef TG_VERILOG
    // Build for the Verilator simulator (NO_VPI): the same toggle model
    // without VPI. The
    // generated include defines tg_cur, the concatenation of exactly the
    // registers that the VPI module collects (leakage/verilator.py writes
    // it from that module's register list), so both simulators compute
    // the same sample.
`include "tg_regs.vh"
    reg [TG_W-1:0] tg_prev;
    reg [15:0]     tg_row [0:16383];
    integer        tg_fd;
`endif
    task tick;
        begin
            @(negedge clk);
            if (in_window) begin
`ifndef NO_VPI
                if (dump_mode) begin if (!skip) $tg_dump; end
                else $tg_sample;
`endif
`ifdef TG_VERILOG
                tg_row[samples] = $countones(tg_cur ^ tg_prev);
                tg_prev = tg_cur;
`endif
                samples = samples + 1;
            end
        end
    endtask

    task do_reset;
        begin
            tick; rst = 1; start = 0; ext_we = 0; ext_share_sel = 0;
            ext_addr_w = 0; ext_data_w = 0; ext_addr_r = 0; ext_re = 0;
            repeat (4) tick;
            rst = 0;
            repeat (2) tick;
        end
    endtask

    task load_share(input integer sh);
        begin
            ext_share_sel = sh;
            for (i = 0; i < 256; i = i + 1) begin
                if (!(sh == 0 && i == 0)) tick;   // first edge: window opened by caller
                ext_we = 1; ext_addr_w = i; ext_data_w = inmem[base + 1 + 256*sh + i];
            end
            tick;
            ext_we = 0; ext_addr_w = 0; ext_data_w = 0;   // clear the input bus
        end
    endtask

    task read_share(input integer sh);
        begin
            tick;
            ext_share_sel = sh;
            for (i = 0; i < 256 + RD_LAT; i = i + 1) begin
                if (i > 0) tick;
                if (i >= RD_LAT) rd[256*sh + i - RD_LAT] = ext_data_r;
                if (i < 256) begin ext_re = 1; ext_addr_r = i; end
                else         begin ext_re = 0; ext_addr_r = 0; end
            end
            // ext_re low for two edges before the other share is selected
            tick; ext_re = 0; ext_addr_r = 0;
            tick;
        end
    endtask

    initial begin
        if (!$value$plusargs("in=%s", fin)) begin $display("missing +in"); $finish; end
        if (!$value$plusargs("n=%d", n))    begin $display("missing +n");  $finish; end
        if (!$value$plusargs("delta=%d", delta)) delta = 1;
        dump_mode = $value$plusargs("dump=%s", fdump);
        chk_fd = 0;
        if ($value$plusargs("chk=%s", fchk)) chk_fd = $fopen(fchk, "w");
        $readmemh(fin, inmem, 0, 513*n - 1);
`ifndef NO_VPI
        $tg_init(wrap);
        if (dump_mode) begin
            $tg_dump_open(fdump);
            if ($value$plusargs("names=%s", fnames)) $tg_names(fnames);
        end else begin
            if (!$value$plusargs("out=%s", fout)) begin $display("missing +out"); $finish; end
            $tg_open(fout);
        end
`endif
`ifdef TG_VERILOG
        if (!$value$plusargs("out=%s", fout)) begin $display("missing +out"); $finish; end
        tg_fd = $fopen(fout, "wb");
`endif
        in_window = 0; rowlen = 0; order_rand = 0; skip = 0;

        for (t = 0; t < n; t = t + 1) begin
            base = 513*t;
            do_reset;
            order_rand = inmem[base][1];
            skip = inmem[base][2];
            samples = 0;

            // ---- window opens before the first load edge ----
            tick;
`ifndef NO_VPI
            if (dump_mode) begin if (!skip) $tg_dump; end else $tg_sync;
`endif
`ifdef TG_VERILOG
            tg_prev = tg_cur;
`endif
            in_window = 1;
            load_share(0);
            if (NSH == 2) load_share(1);
            ext_share_sel = 0;

            tick; start = 1;
            tick; start = 0;
            while (!done) tick;
            // interface rule: two more edges before the first read, so that
            // the last butterfly leaves the pipeline before any share word
            // reaches a latch or a read register
            repeat (2) tick;

            read_share(0);
            if (NSH == 2) read_share(1);
            ext_share_sel = 0;
            in_window = 0;
            // ---- window closed ----

            if (rowlen == 0) rowlen = samples;
            if (samples != rowlen) begin
                $display("[ERROR] execution %0d: %0d samples, expected %0d", t, samples, rowlen);
                $finish;
            end
`ifndef NO_VPI
            // an execution flagged skip (bit 2) only sets the memory state
            // for the next one: its row is discarded
            if (!dump_mode) begin if (skip) $tg_sync; else $tg_flush(rowlen); end
`endif
`ifdef TG_VERILOG
            if (!skip)
                for (s = 0; s < rowlen; s = s + 1)
                    $fwrite(tg_fd, "%c%c", tg_row[s][7:0], tg_row[s][15:8]);
`endif
            if (chk_fd && !skip) begin
                for (s = 0; s < 256*NSH; s = s + 1) $fwrite(chk_fd, "%04h\n", rd[s] & 16'hffff);
            end
        end
`ifndef NO_VPI
        $tg_close;
`endif
`ifdef TG_VERILOG
        $fclose(tg_fd);
`endif
        if (chk_fd) $fclose(chk_fd);
        $display("[DONE] %0d executions, %0d samples each", n, rowlen);
        $finish;
    end

endmodule

// =============================================================
// Wrapper: the DUT and, for the positive controls, the injected flaw.
// The toggle model covers every register below this module.
// =============================================================
module leak_wrap (
    input  wire        clk, rst, start,
    output wire        done,
    input  wire        ext_we, ext_share_sel,
    input  wire [7:0]  ext_addr_w,
    input  wire signed [15:0] ext_data_w,
    input  wire [7:0]  ext_addr_r,
    input  wire        ext_re,
    output wire signed [15:0] ext_data_r,
    input  wire [12:0] delta,
    input  wire        order_rand
);
`ifdef CFG_STAG
    ntt_top dut (.clk(clk), .rst(rst), .start(start), .done(done),
        .delta(delta), .order_rand(order_rand),
        .ext_we(ext_we), .ext_share_sel(ext_share_sel),
        .ext_addr_w(ext_addr_w), .ext_data_w(ext_data_w),
        .ext_addr_r(ext_addr_r), .ext_re(ext_re), .ext_data_r(ext_data_r));
`elsif CFG_BASE_C
    ntt_top dut (.clk(clk), .rst(rst), .start(start), .done(done),
        .ext_we(ext_we),
        .ext_addr_w(ext_addr_w), .ext_data_w(ext_data_w),
        .ext_addr_r(ext_addr_r), .ext_re(ext_re), .ext_data_r(ext_data_r));
`elsif CFG_BASE_B
    ntt_top dut (.clk(clk), .rst(rst), .start(start), .done(done),
        .ext_we(ext_we),
        .ext_addr_w(ext_addr_w), .ext_data_w(ext_data_w),
        .ext_addr_r(ext_addr_r), .ext_data_r(ext_data_r));
`else
    ntt_top dut (.clk(clk), .rst(rst), .start(start), .done(done),
        .ext_we(ext_we), .ext_share_sel(ext_share_sel),
        .ext_addr_w(ext_addr_w), .ext_data_w(ext_data_w),
        .ext_addr_r(ext_addr_r), .ext_re(ext_re), .ext_data_r(ext_data_r));
`endif

`ifdef CTRL_C1
    // C1: two shares meet in one cell
    reg signed [15:0] c1_q;
    always @(posedge clk) c1_q <= dut.s0e_da + dut.s1e_da;
`endif
`ifdef CTRL_C2
    // C2: one register, share 0 and share 1 of the same word in
    // consecutive cycles (lock-step: both banks hold the same address)
    reg signed [15:0] c2_q;
    reg               c2_ph;
    always @(posedge clk) begin
        if (rst) c2_ph <= 1'b0; else c2_ph <= ~c2_ph;
        c2_q <= c2_ph ? dut.s1e_da : dut.s0e_da;
    end
`endif
endmodule
