#!/bin/bash
# =============================================================
# Parallel TVLA campaign launcher
# =============================================================
# Usage:
#   ./run_parallel.sh              # full run: 8 jobs x 125,000 = 10^6
#   ./run_parallel.sh 250          # smoke test: 8 jobs x 250 = 2,000
#
# Run from the directory holding the BASTION RTL.
# =============================================================
set -e

PER_JOB=${1:-125000}
N_JOBS=8
RTL="butterfly.v lfsr16.v memory_bank.v ntt_controller.v twiddle_rom.v ntt_top.v"

echo "=== compiling (N_TRACES=$PER_JOB) ==="
iverilog -g2012 -P tb_tvla_parallel.N_TRACES=$PER_JOB \
    -o sim_parallel $RTL tb_tvla_parallel.v

echo "=== generating seeds ==="
python3 gen_seeds.py $N_JOBS $PER_JOB | tee seeds.txt

echo "=== launching $N_JOBS jobs ==="
rm -f tvla_partial_*.csv job_*.log
while read -r job sin ssh; do
    [[ "$job" =~ ^# ]] && continue
    [[ -z "$job" ]] && continue
    echo "  job $job  seed_in=$sin  seed_sh=$ssh"
    vvp sim_parallel +SEED_IN=$sin +SEED_SH=$ssh +JOB=$job \
        > job_$job.log 2>&1 &
done < <(grep -v '^#' seeds.txt | grep -v '^$')

echo "=== waiting (monitor with: tail -f job_0.log) ==="
wait

echo "=== merging ==="
python3 merge_tvla.py tvla_partial_*.csv
