#!/usr/bin/env bash
# Functional simulation of Cara B unmasked (4-BFU hardened baseline).

set -euo pipefail
cd "$(dirname "$0")/../rtl/caraB_unmasked"

iverilog -o sim_ntt tb_ntt_top.v *.v
./sim_ntt
