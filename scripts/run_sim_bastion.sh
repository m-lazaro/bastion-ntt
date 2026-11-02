#!/usr/bin/env bash
# Functional simulation of the BASTION masked core (lock-step schedule):
# KAT on six ML-KEM-512 vectors plus the read-back monitor.
set -euo pipefail
KAT="$(cd "$(dirname "$0")/../kat" && pwd)"
cd "$(dirname "$0")/../rtl/bastion"
cp "$KAT/kat_input.hex" "$KAT/kat_expected.hex" .
iverilog -g2012 -DCHK_RUNS=6 -o sim_ntt tb_ntt_top.v chk_readback.v \
    butterfly.v memory_bank.v lfsr16.v ntt_controller.v ntt_top.v twiddle_rom.v
vvp -n sim_ntt
