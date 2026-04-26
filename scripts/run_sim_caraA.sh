#!/usr/bin/env bash
# Functional simulation of Cara A (single-BFU baseline NTT).
# Compiles all RTL with Icarus Verilog and runs the testbench.

set -euo pipefail
cd "$(dirname "$0")/../rtl/caraA"

iverilog -o sim_ntt tb_ntt_top.v *.v
./sim_ntt
