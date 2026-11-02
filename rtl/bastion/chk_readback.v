`timescale 1ns / 1ps
// =============================================================
// CHK_READBACK — simulation monitor for the read-back path
// =============================================================
// Compile together with tb_ntt_top.v of a two-domain core (lock-step or
// staggered) and define CHK_RUNS as the number of test runs. Tracks,
// cycle by cycle, which domain each read register and the output port
// hold data from (0, 1, or none) and reports:
//   both   : cycles in which rd0 and rd1 both hold data
//   early  : cycles in which a read register holds data before done
//   direct : output-port transitions from a word of one domain directly
//            to a word of the other
//   loaded : cycles in which a read register holds data (sanity check)
// All counts except `loaded` must be zero.
// =============================================================
module chk_readback;
  integer both, early, direct, loaded;
  reg en0, en1;          // load enables seen before the edge
  reg r0, r1;            // rd0 / rd1 hold data after the edge
  reg [1:0] port_tag, nxt_tag;  // 0, 1, or 2 = no data
  initial begin
    both = 0; early = 0; direct = 0; loaded = 0;
    en0 = 0; en1 = 0; r0 = 0; r1 = 0; port_tag = 2;
  end
  always @(negedge tb_ntt_top.clk) begin
    en0 = tb_ntt_top.dut.rd0_en_d;
    en1 = tb_ntt_top.dut.rd1_en_d;
  end
  always @(posedge tb_ntt_top.clk) begin
    #1;
    r0 = en0; r1 = en1;
    if (r0 && r1) both = both + 1;
    if ((r0 || r1) && !tb_ntt_top.dut.done) early = early + 1;
    if (r0 || r1) loaded = loaded + 1;
    nxt_tag = tb_ntt_top.ext_share_sel ? (r1 ? 2'd1 : 2'd2) : (r0 ? 2'd0 : 2'd2);
    if (port_tag != 2 && nxt_tag != 2 && port_tag != nxt_tag) direct = direct + 1;
    port_tag = nxt_tag;
  end
  initial begin
    wait (tb_ntt_top.pass_cnt + tb_ntt_top.fail_cnt == `CHK_RUNS);
    $display("CHECK READBACK: both=%0d early=%0d direct=%0d loaded=%0d", both, early, direct, loaded);
  end
endmodule
