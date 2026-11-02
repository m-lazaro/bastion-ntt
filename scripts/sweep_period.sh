#!/usr/bin/env bash
# Sweep the clock period of one configuration in steps of 0.1 ns and keep
# the shortest period that closes with WNS >= 0.
#
#   scripts/sweep_period.sh <config> <initial period in ns>
#
# From the initial period: if timing fails, raise the period until it
# closes; if it closes, lower it until it fails. Each run is a full
# build_config.tcl run (reports in build/reports/). The chosen period and
# its headline numbers are written to results/<config>.txt. A period whose
# run already completed (build/logs/<config>_<period>.out) is not rerun.
set -euo pipefail
export LC_ALL=C      # decimal point, not comma, whatever the user's locale
cfg="$1"; p="$2"
root="$(cd "$(dirname "$0")/.." && pwd)"
logs="$root/build/logs"; mkdir -p "$logs" "$root/results"

wns_of() {   # run one period, print its WNS (empty if the run failed)
    local per="$1"
    local out="$logs/${cfg}_${per}.out"
    if ! grep -qE '^ WNS +:' "$out" 2>/dev/null; then
        ( cd "$logs" && vivado -mode batch -nojournal -log "${cfg}_${per}.log" \
            -source "$root/scripts/build_config.tcl" -tclargs "$cfg" "$per" \
            > "${cfg}_${per}.out" 2>&1 ) || true
    fi
    { grep -E '^ WNS +:' "$out" || true; } | awk '{print $3}'
}
met()  { awk -v w="$1" 'BEGIN{exit !(w != "" && w >= 0)}'; }
step() { awk -v a="$1" -v d="$2" 'BEGIN{printf "%.3f", a + d}'; }

best=""
w=$(wns_of "$p"); echo "$cfg $p WNS=$w"
if met "$w"; then
    best="$p"
    while :; do
        q=$(step "$p" -0.1); w=$(wns_of "$q"); echo "$cfg $q WNS=$w"
        if met "$w"; then best="$q"; p="$q"; else break; fi
    done
else
    while :; do
        p=$(step "$p" 0.1); w=$(wns_of "$p"); echo "$cfg $p WNS=$w"
        if met "$w"; then best="$p"; break; fi
    done
fi

out="$logs/${cfg}_${best}.out"
{
    echo "config $cfg"
    echo "period $best"
    grep -E '^ (CONFIG|Tclk|WNS|fmax|\||SEPARATION) |^ {15}Q[0-9]' "$out"
} > "$root/results/${cfg}.txt"
cat "$root/results/${cfg}.txt"
