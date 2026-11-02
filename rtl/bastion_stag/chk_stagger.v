`timescale 1ns / 1ps
// =============================================================
// CHK_STAGGER — simulation monitor for the staggered schedule
// =============================================================
// The lagging domain's public control (addresses, write enables,
// butterfly enable, twiddle and dummy operands) at cycle c + delta must
// equal the leading domain's at cycle c, for every cycle of the leading
// transform, and the leading domain must be domain `order_rand`.
// Reports the cycles compared and the mismatches (must be zero).
// =============================================================
module chk_stagger;
  integer cyc, t0, i, d, viol, compared, lead_err;
  reg running;
  reg [7:0]  L_aa [0:20000]; reg [7:0] L_ab [0:20000]; reg [7:0] L_wa [0:20000]; reg [7:0] L_wb [0:20000];
  reg        L_we [0:20000]; reg L_act [0:20000]; reg [15:0] L_tw [0:20000]; reg [15:0] L_da [0:20000];
  reg [7:0]  G_aa [0:20000]; reg [7:0] G_ab [0:20000]; reg [7:0] G_wa [0:20000]; reg [7:0] G_wb [0:20000];
  reg        G_we [0:20000]; reg G_act [0:20000]; reg [15:0] G_tw [0:20000]; reg [15:0] G_da [0:20000];
  initial begin cyc = 0; viol = 0; compared = 0; running = 0; lead_err = 0; end
  always @(posedge tb_ntt_top.clk) begin
    #1;
    if (tb_ntt_top.dut.start && !running) begin running = 1; t0 = cyc; end
    if (running) begin
      i = cyc - t0;
      // L = leading domain, G = lagging domain
      if (tb_ntt_top.dut.lead == 1'b0) begin
        L_aa[i] = tb_ntt_top.dut.d0_addr_a; L_ab[i] = tb_ntt_top.dut.d0_addr_b; L_wa[i] = tb_ntt_top.dut.d0_addr_wa; L_wb[i] = tb_ntt_top.dut.d0_addr_wb;
        L_we[i] = tb_ntt_top.dut.d0_we; L_act[i] = tb_ntt_top.dut.d0_active; L_tw[i] = tb_ntt_top.dut.d0_twiddle; L_da[i] = tb_ntt_top.dut.d0_dummy_a;
        G_aa[i] = tb_ntt_top.dut.d1_addr_a; G_ab[i] = tb_ntt_top.dut.d1_addr_b; G_wa[i] = tb_ntt_top.dut.d1_addr_wa; G_wb[i] = tb_ntt_top.dut.d1_addr_wb;
        G_we[i] = tb_ntt_top.dut.d1_we; G_act[i] = tb_ntt_top.dut.d1_active; G_tw[i] = tb_ntt_top.dut.d1_twiddle; G_da[i] = tb_ntt_top.dut.d1_dummy_a;
      end else begin
        L_aa[i] = tb_ntt_top.dut.d1_addr_a; L_ab[i] = tb_ntt_top.dut.d1_addr_b; L_wa[i] = tb_ntt_top.dut.d1_addr_wa; L_wb[i] = tb_ntt_top.dut.d1_addr_wb;
        L_we[i] = tb_ntt_top.dut.d1_we; L_act[i] = tb_ntt_top.dut.d1_active; L_tw[i] = tb_ntt_top.dut.d1_twiddle; L_da[i] = tb_ntt_top.dut.d1_dummy_a;
        G_aa[i] = tb_ntt_top.dut.d0_addr_a; G_ab[i] = tb_ntt_top.dut.d0_addr_b; G_wa[i] = tb_ntt_top.dut.d0_addr_wa; G_wb[i] = tb_ntt_top.dut.d0_addr_wb;
        G_we[i] = tb_ntt_top.dut.d0_we; G_act[i] = tb_ntt_top.dut.d0_active; G_tw[i] = tb_ntt_top.dut.d0_twiddle; G_da[i] = tb_ntt_top.dut.d0_dummy_a;
      end
      if (i == 2 && tb_ntt_top.dut.lead !== tb_ntt_top.order_rand) lead_err = lead_err + 1;
      if (tb_ntt_top.dut.done) begin
        running = 0;
        d = tb_ntt_top.delta;
        // cycle 1 = first cycle after the start cycle; compare the whole
        // leading transform (4,034 cycles) with the lagging one
        for (i = 1; i <= 4034; i = i + 1) begin
          compared = compared + 1;
          if (L_aa[i] !== G_aa[i+d] || L_ab[i] !== G_ab[i+d] || L_wa[i] !== G_wa[i+d] || L_wb[i] !== G_wb[i+d] ||
              L_we[i] !== G_we[i+d] || L_act[i] !== G_act[i+d] || L_tw[i] !== G_tw[i+d] || L_da[i] !== G_da[i+d]) begin
            viol = viol + 1;
            if (viol < 4) $display("  STAGGER MISMATCH delta=%0d offset=%0d", d, i);
          end
        end
      end
    end
    cyc = cyc + 1;
  end
  initial begin
    wait (tb_ntt_top.pass_cnt + tb_ntt_top.fail_cnt == `CHK_RUNS);
    $display("CHECK STAGGER: cycles compared=%0d mismatches=%0d lead-bit errors=%0d", compared, viol, lead_err);
  end
endmodule
