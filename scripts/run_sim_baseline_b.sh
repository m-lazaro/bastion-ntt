#!/usr/bin/env bash
# Functional simulation of Baseline B (4-BFU hardened-unmasked baseline).
set -euo pipefail
KAT="$(cd "$(dirname "$0")/../kat" && pwd)"
cd "$(dirname "$0")/../rtl/baseline_b"
cp "$KAT/kat_input.hex" "$KAT/kat_expected.hex" .
iverilog -o sim_ntt tb_ntt_top.v butterfly.v memory.v memory_bank.v \
                    lfsr16.v ntt_controller.v ntt_top.v twiddle_rom.v
./sim_ntt
