`timescale 1ns / 1ps
// =============================================================
// CHK_SEQ — simulation monitor for the sequential schedule
// =============================================================
//  (1) pass 1 replays pass 0: for every cycle c of pass 0 (1 to 4,032;
//      the first two of the three flush cycles that follow do not
//      replay anything), controller outputs and LFSR at cycle c + 4,035
//      equal those at cycle c, with the pass bit 0 and 1;
//  (2) no bank output latch goes directly from a word of one share to a
//      word of the other (tags: share 0, share 1, or cleared);
//  (3) the read register never goes directly from one share to the other.
// Reports mismatches and violations (all must be zero).
// =============================================================
module chk_seq;
  localparam T = 4035;      // pass offset
  localparam PASS = 4032;   // cycles of one pass after the start cycle
  integer cyc, t0, viol_replay, viol_latch, viol_rd, compared, i;
  reg [7:0]  r_aa [0:20000]; reg [7:0] r_ab [0:20000];
  reg [7:0]  r_wa [0:20000]; reg [7:0] r_wb [0:20000];
  reg [7:0]  r_z  [0:20000]; reg r_we [0:20000]; reg r_act [0:20000];
  reg [15:0] r_lf [0:20000]; reg r_pass [0:20000];
  reg running;
  // latch tags: 2 = Z (cleared / never loaded), 0 = share 0, 1 = share 1
  reg [1:0] tag_ea, tag_eb, tag_oa, tag_ob, tag_rd, nxt_ea, nxt_eb, nxt_oa, nxt_ob, nxt_rd;
  reg [1:0] rdsrc_d;
  initial begin
    cyc = 0; viol_replay = 0; viol_latch = 0; viol_rd = 0; compared = 0; running = 0;
    tag_ea = 2; tag_eb = 2; tag_oa = 2; tag_ob = 2; tag_rd = 2; rdsrc_d = 2;
  end
  function [1:0] trans_ok; input [1:0] a; input [1:0] b;
    trans_ok = !((a != 2) && (b != 2) && (a != b)); endfunction

  // Sample the inputs that decide the next latch values mid-cycle.
  always @(negedge tb_ntt_top.clk) begin
    nxt_ea = tb_ntt_top.dut.clr_a ? 2 : {1'b0, tb_ntt_top.dut.e_aa[7]};
    nxt_eb = tb_ntt_top.dut.clr_b ? 2 : {1'b0, tb_ntt_top.dut.e_ab[7]};
    nxt_oa = tb_ntt_top.dut.clr_a ? 2 : {1'b0, tb_ntt_top.dut.o_aa[7]};
    nxt_ob = tb_ntt_top.dut.clr_b ? 2 : {1'b0, tb_ntt_top.dut.o_ab[7]};
    // rd_q <= rd_en_d ? latch(port A, chosen parity) : 0
    nxt_rd = tb_ntt_top.dut.rd_en_d ? (tb_ntt_top.dut.rd_even_d ? tag_ea : tag_oa) : 2;
  end
  always @(posedge tb_ntt_top.clk) begin
    #1;
    if (!trans_ok(tag_ea, nxt_ea) || !trans_ok(tag_eb, nxt_eb) ||
        !trans_ok(tag_oa, nxt_oa) || !trans_ok(tag_ob, nxt_ob)) begin
      viol_latch = viol_latch + 1;
      if (viol_latch < 5) $display("  LATCH VIOLATION at t=%0t ea %0d>%0d eb %0d>%0d oa %0d>%0d ob %0d>%0d",
          $time, tag_ea, nxt_ea, tag_eb, nxt_eb, tag_oa, nxt_oa, tag_ob, nxt_ob);
    end
    if (!trans_ok(tag_rd, nxt_rd)) begin
      viol_rd = viol_rd + 1;
      if (viol_rd < 5) $display("  READ-REGISTER VIOLATION at t=%0t %0d>%0d", $time, tag_rd, nxt_rd);
    end
    tag_ea = nxt_ea; tag_eb = nxt_eb; tag_oa = nxt_oa; tag_ob = nxt_ob; tag_rd = nxt_rd;

    // Replay recording, from the start cycle to done
    if (tb_ntt_top.dut.start && !running) begin running = 1; t0 = cyc; end
    if (running) begin
      i = cyc - t0;
      r_aa[i] = tb_ntt_top.dut.ctrl_addr_a;  r_ab[i] = tb_ntt_top.dut.ctrl_addr_b;
      r_wa[i] = tb_ntt_top.dut.ctrl_addr_wa; r_wb[i] = tb_ntt_top.dut.ctrl_addr_wb;
      r_z[i]  = tb_ntt_top.dut.ctrl_zeta_addr; r_we[i] = tb_ntt_top.dut.ctrl_we;
      r_act[i] = tb_ntt_top.dut.bf_active; r_lf[i] = tb_ntt_top.dut.lfsr_out;
      r_pass[i] = tb_ntt_top.dut.pass;
      if (tb_ntt_top.dut.done) begin
        running = 0;
        for (i = 1; i <= PASS; i = i + 1) begin
          compared = compared + 1;
          if (r_aa[i] !== r_aa[i+T] || r_ab[i] !== r_ab[i+T] || r_wa[i] !== r_wa[i+T] ||
              r_wb[i] !== r_wb[i+T] || r_z[i] !== r_z[i+T] || r_we[i] !== r_we[i+T] ||
              r_act[i] !== r_act[i+T] || r_lf[i] !== r_lf[i+T] || r_pass[i] !== 1'b0 || r_pass[i+T] !== 1'b1) begin
            viol_replay = viol_replay + 1;
            if (viol_replay < 5) $display("  REPLAY MISMATCH at offset %0d", i);
          end
        end
      end
    end
    cyc = cyc + 1;
  end
  initial begin
    wait (tb_ntt_top.pass_cnt + tb_ntt_top.fail_cnt == `CHK_RUNS);
    $display("CHECK SEQ: replay cycles compared=%0d mismatches=%0d | latch violations=%0d | read-register violations=%0d",
             compared, viol_replay, viol_latch, viol_rd);
  end
endmodule
