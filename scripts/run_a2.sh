#!/usr/bin/env bash
# =============================================================
# A2 leakage campaigns: five independent pairs of runs per schedule.
# =============================================================
#   scripts/run_a2.sh [--procs P] [--n N] [--pairs K] [--only a,b,...]
#
# For every schedule (lock-step, staggered with delta 1, 4, 9, 18, 576 and
# 4034, sequential) and every pair k = 1..5: run A_k and B_k with N
# executions each, detect.py on the pair with the 16-point grid, keep the
# JSON, delete the traces of the pair. The controls (C1, C2, C3, Baseline
# B) run first, five pairs of 2,000 executions with their own grid. At the
# end, detect_pairs.py summarises every schedule.
#
# Results:  leakage/results/a2/<schedule>_pair<k>.json   (one per pair)
#           leakage/results/a2/<schedule>_summary.json   (five pairs)
#           leakage/results/a2/summary.txt               (all tables)
#           leakage/results/a2/logs/                     (one log per run)
# The script can be stopped and restarted: a pair whose JSON exists is not
# run again.
#
# --procs: simulations in parallel. Each is one single-threaded process
#   using about 0.3 GB of memory. On a 4-core, 8-thread machine use 7 if
#   nothing else runs, 5 while Vivado runs.
# Disk: a pair of 100,000-execution runs needs up to 3.7 GB while it runs
#   (lock-step about 2 GB, sequential and delta 4034 about 3.7 GB); it is
#   freed when the pair is done.
# =============================================================
set -euo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROCS=7; N=100000; PAIRS=5; ONLY=""; NCTRL=2000
while [ $# -gt 0 ]; do
    case "$1" in
        --procs) PROCS="$2"; shift 2 ;;
        --n)     N="$2"; shift 2 ;;
        --pairs) PAIRS="$2"; shift 2 ;;
        --only)  ONLY="$2"; shift 2 ;;
        --ncontrols) NCTRL="$2"; shift 2 ;;
        *) echo "unknown option $1"; exit 1 ;;
    esac
done

GRID="500,1000,2000,3000,5000,7500,10000,20000,30000,40000,50000,60000,70000,80000,90000,100000"
GRID_CTRL="25,50,100,150,200,300,400,500,750,1000,1500,2000"
# with a smaller --n (a test run), cut the grids at N
cut_grid() { echo "$1" | tr ',' '\n' | awk -v n="$2" '$1 <= n' | paste -sd, -; }
GRID=$(cut_grid "$GRID" "$N"); GRID_CTRL=$(cut_grid "$GRID_CTRL" "$NCTRL")

OUT=leakage/results/a2; mkdir -p "$OUT/logs"
CAMP=leakage/build/campaigns

# schedule label | campaign config | --delta for the campaign | bivariate offset
SCHEDULES="
c1|c1|0|0
c2|c2|0|0
c3|c3|0|0
baseline_b|baseline_b|0|0
lockstep|lockstep|0|0
sequential|sequential|0|4035
staggered_d1|staggered|1|1
staggered_d4|staggered|4|4
staggered_d9|staggered|9|9
staggered_d18|staggered|18|18
staggered_d576|staggered|576|576
staggered_d4034|staggered|4034|4034
"

want() { [ -z "$ONLY" ] || echo ",$ONLY," | grep -q ",$1,"; }
free_gb() { df -BG --output=avail "$ROOT" | tail -1 | tr -dc 0-9; }

run_one() {   # cfg run n delta -> campaign dir name
    local cfg=$1 run=$2 n=$3 delta=$4 name
    if [ "$cfg" = staggered ]; then name="${cfg}_d${delta}_${run}"; else name="${cfg}_${run}"; fi
    if [ ! -f "$CAMP/$name/summary.txt" ]; then
        local t0=$(date +%s)
        python3 -I leakage/run_campaign.py "$cfg" "$run" "$n" --delta "$delta" \
            --job 1000 --procs "$PROCS" > "$OUT/logs/$name.log" 2>&1 \
            || { echo "FAILED: $name, see $OUT/logs/$name.log" >&2; tail -5 "$OUT/logs/$name.log" >&2; exit 1; }
        echo "    $(tail -1 "$OUT/logs/$name.log")  ($(( $(date +%s) - t0 )) s)" >&2
    fi
    echo "$name"
}

echo "A2: N=$N per run, $PAIRS pairs, $PROCS processes, controls $NCTRL per run"
echo "start $(date)"
while IFS='|' read -r label cfg delta off; do
    [ -z "$label" ] && continue
    want "$label" || continue
    case "$label" in c1|c2|c3|baseline_b) n=$NCTRL; grid=$GRID_CTRL ;; *) n=$N; grid=$GRID ;; esac
    for k in $(seq 1 "$PAIRS"); do
        js="$OUT/${label}_pair${k}.json"
        [ -f "$js" ] && continue
        if [ "$(free_gb)" -lt 5 ]; then echo "less than 5 GB free; stopping"; exit 1; fi
        echo "[$(date +%H:%M)] $label pair $k"
        na=$(run_one "$cfg" "A$k" "$n" "$delta")
        nb=$(run_one "$cfg" "B$k" "$n" "$delta")
        python3 -I leakage/detect.py "$CAMP/$na" "$CAMP/$nb" --delta "$off" --grid "$grid" \
            --out "$js.tmp" > "$OUT/logs/${label}_pair${k}_detect.txt"
        mv "$js.tmp" "$js"
        # keep the per-run statistics and summaries, delete the traces
        rm -f "$CAMP/$na"/job*.npy "$CAMP/$nb"/job*.npy "$CAMP/$na"/flags*.npy "$CAMP/$nb"/flags*.npy
        python3 -I -c "import json,sys; d=json.load(open('$js')); print('    first detection:', d['first_detection'])"
    done
    files=$(ls "$OUT/${label}"_pair*.json 2>/dev/null | sort)
    python3 -I leakage/detect_pairs.py "$label" $files --out "$OUT/${label}_summary.json" \
        | tee -a "$OUT/summary.txt.new"
done <<< "$SCHEDULES"
[ -f "$OUT/summary.txt.new" ] && mv "$OUT/summary.txt.new" "$OUT/summary.txt"
echo "end $(date)"
