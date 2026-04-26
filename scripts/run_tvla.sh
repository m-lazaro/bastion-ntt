#!/usr/bin/env bash
# Full TVLA pipeline for BASTION:
#   1. Generate 30,000 traces (~536 MB) via Icarus Verilog testbench.
#   2. Compute Welch t-statistic per cycle (tvla_analyze.py).
#   3. Compute scaling-law evolution plot (tvla_evolution.py).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASTION_DIR="$REPO_ROOT/rtl/bastion"
TVLA_DIR="$REPO_ROOT/tvla"

echo "==> Compiling BASTION TVLA testbench..."
cd "$BASTION_DIR"
iverilog -o sim_tvla tb_tvla.v butterfly.v memory.v memory_bank.v \
                     lfsr16.v ntt_controller.v ntt_top.v twiddle_rom.v

echo "==> Generating traces (this takes ~30-60 min and ~536 MB of disk)..."
./sim_tvla

echo "==> Running TVLA per-cycle analysis..."
cd "$TVLA_DIR"
python3 tvla_analyze.py "$BASTION_DIR/tvla_traces.csv"

echo "==> Running TVLA scaling-law analysis..."
python3 tvla_evolution.py "$BASTION_DIR/tvla_traces.csv"

echo ""
echo "==> Done. Expected outputs:"
echo "    - tvla_plot.{pdf,png}        (Fig. 4 of paper)"
echo "    - tvla_evolution.{pdf,png}   (Fig. 5 of paper)"
echo "    - tvla_evolution.csv         (raw checkpoints)"
echo ""
echo "==> Expected result: max|t| = 3.961 < 4.5 (PASS)"
