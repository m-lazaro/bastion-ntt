#!/usr/bin/env bash
# Functional simulation of the sequential core: KAT on six ML-KEM-512
# vectors plus the replay and latch monitor.
set -euo pipefail
KAT="$(cd "$(dirname "$0")/../kat" && pwd)"
cd "$(dirname "$0")/../rtl/bastion_seq"
cp "$KAT/kat_input.hex" "$KAT/kat_expected.hex" .
iverilog -g2012 -DCHK_RUNS=6 -o sim_ntt tb_ntt_top.v chk_seq.v \
    ntt_top.v ntt_controller_seq.v butterfly.v memory_bank_seq.v lfsr16_cr.v twiddle_rom.v
vvp -n sim_ntt
