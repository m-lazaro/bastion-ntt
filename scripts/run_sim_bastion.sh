#!/usr/bin/env bash
# Functional simulation of BASTION masked NTT core.

set -euo pipefail
cd "$(dirname "$0")/../rtl/bastion"

iverilog -o sim_ntt tb_ntt_top.v butterfly.v memory.v memory_bank.v \
                    lfsr16.v ntt_controller.v ntt_top.v twiddle_rom.v
./sim_ntt
