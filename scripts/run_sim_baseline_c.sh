#!/usr/bin/env bash
# Functional simulation of Baseline C (iso-architectural unmasked control).
set -euo pipefail
KAT="$(cd "$(dirname "$0")/../kat" && pwd)"
cd "$(dirname "$0")/../rtl/baseline_c"
cp "$KAT/kat_input.hex" "$KAT/kat_expected.hex" .
iverilog -o sim_ntt tb_ntt_top.v butterfly.v memory_bank.v \
                    lfsr16.v ntt_controller.v ntt_top.v twiddle_rom.v
./sim_ntt
