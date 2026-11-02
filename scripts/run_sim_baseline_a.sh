#!/usr/bin/env bash
# Functional simulation of Baseline A (single-BFU baseline NTT).
set -euo pipefail
KAT="$(cd "$(dirname "$0")/../kat" && pwd)"
cd "$(dirname "$0")/../rtl/baseline_a"
cp "$KAT/kat_input.hex" "$KAT/kat_expected.hex" .
iverilog -o sim_ntt tb_ntt_top.v butterfly.v memory.v ntt_controller.v ntt_top.v twiddle_rom.v
./sim_ntt
