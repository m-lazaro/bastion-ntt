#!/usr/bin/env python3
# Combined Figure 2: BASTION masked (30k, two shares) + Baseline B positive control.
# Usage:
#   python3 make_fig2_combined.py \
#       tvla_tvalues_s0_RTL30k_v3.csv \
#       tvla_tvalues_s1_RTL30k_v3.csv \
#       <posctrl_s0.csv> \
#       tvla_plot_combined.pdf

import sys, csv
import matplotlib.pyplot as plt

def load(path):
    rows = list(csv.reader(open(path)))
    # skip a header row if the first cell isn't a number
    start = 0
    try:
        float(rows[0][0])
    except ValueError:
        start = 1
    return [float(r[0]) for r in rows[start:] if r]

s0  = load(sys.argv[1])   # BASTION share 0
s1  = load(sys.argv[2])   # BASTION share 1
pc  = load(sys.argv[3])   # Baseline B positive control
out = sys.argv[4] if len(sys.argv) > 4 else "tvla_plot_combined.pdf"

pc_peak = max(abs(v) for v in pc)

fig, ax = plt.subplots(figsize=(7.0, 3.1))

# Baseline B first, so the BASTION curves sit on top and stay readable.
ax.plot(range(len(pc)), pc, color="0.6", linewidth=0.4,
        label=f"Baseline B, unmasked (peaks at {pc_peak:.0f})", zorder=1)
ax.plot(range(len(s0)), s0, color="tab:blue",   linewidth=0.5,
        label="BASTION share 0 (bf0.a_out)", zorder=3)
ax.plot(range(len(s1)), s1, color="tab:red",    linewidth=0.5,
        label="BASTION share 1 (bf2.a_out)", zorder=2)

ax.axhline( 4.5, color="crimson", linestyle="--", linewidth=0.8)
ax.axhline(-4.5, color="crimson", linestyle="--", linewidth=0.8, label=r"$\pm4.5$ threshold")

# Clip to the BASTION range so the two masked curves are legible;
# Baseline B runs far off-scale and is annotated instead.
ax.set_ylim(-10, 10)
ax.set_xlabel("Clock cycle during NTT")
ax.set_ylabel(r"Welch's $t$-statistic")
ax.annotate(f"Baseline B off-scale, max $|t|$ = {pc_peak:.1f}",
            xy=(0.98, 0.04), xycoords="axes fraction",
            ha="right", va="bottom", fontsize=8, color="0.4")
ax.legend(fontsize=7, loc="upper right", framealpha=0.9)
ax.grid(True, alpha=0.3)
fig.tight_layout()
fig.savefig(out)
print(f"[fig] BASTION s0 max|t| = {max(abs(v) for v in s0):.3f}")
print(f"[fig] BASTION s1 max|t| = {max(abs(v) for v in s1):.3f}")
print(f"[fig] Baseline B max|t| = {pc_peak:.3f}")
print(f"[fig] written to {out}")
