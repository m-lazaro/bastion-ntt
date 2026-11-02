#!/usr/bin/env bash
# TVLA pipeline for BASTION (parallel / sufficient-statistics flow).
# SUPERSEDED: earlier methodology (per-domain toggle traces, first order
# only). Kept for reproducibility of the earlier version.
#
# The testbench accumulates (n, sum, sum-of-squares) per cycle per group
# and emits ~200 kB of partial statistics per job, NOT raw traces.
# Merging the per-job partials yields the exact Welch t-statistic.
#
# For a 30,000-trace campaign, run several jobs with far-apart LCG seeds
# (see gen_seeds.py) and merge (see merge_tvla.py). This script runs a
# single job as a smoke test; edit N_TRACES / seeds for a full campaign.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASTION_DIR="$REPO_ROOT/rtl/bastion"

echo "==> Compiling BASTION parallel TVLA testbench..."
cd "$BASTION_DIR"
iverilog -o sim_tvla tb_tvla_parallel.v butterfly.v memory.v memory_bank.v \
                     lfsr16.v ntt_controller.v ntt_top.v twiddle_rom.v

echo "==> Running one TVLA job (smoke test)..."
vvp sim_tvla +SEED_IN=cafebabe +SEED_SH=deadbeef +JOB=0

echo ""
echo "==> Output: tvla_partial_0.csv"
echo "==> For a full 30k campaign: see gen_seeds.py, run_parallel.sh, merge_tvla.py in ../tvla/"
echo "==> NOTE: this is the earlier per-domain, first-order methodology. It is"
echo "==> superseded by the whole-design harness of the revised paper and is"
echo "==> kept only to reproduce the earlier version."
