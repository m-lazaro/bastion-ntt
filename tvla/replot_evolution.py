#!/usr/bin/env python3
"""
Replot the TVLA evolution figure directly from tvla_evolution.csv
(which now includes the N=200,000 point). No raw traces needed.

Usage:
    python3 replot_evolution.py [tvla_evolution.csv]
Output:
    tvla_evolution.pdf / .png
"""
import sys, csv
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

THRESHOLD = 4.5
fname = sys.argv[1] if len(sys.argv) > 1 else "tvla_evolution.csv"

n, t0, t1 = [], [], []
with open(fname) as f:
    r = csv.reader(f)
    next(r)  # header
    for row in r:
        if not row:
            continue
        n.append(int(row[0]))
        t0.append(float(row[1]))
        t1.append(float(row[2]))

n = np.array(n)
t0 = np.array(t0)
t1 = np.array(t1)

# sqrt(N) prediction anchored at the first checkpoint
n_anchor = n[0]
t_anchor = max(t0[0], t1[0])
theoretical = t_anchor * np.sqrt(n / n_anchor)

fig, ax = plt.subplots(figsize=(8, 4.5))
ax.plot(n, t0, "o-", color="#1f6feb", linewidth=1.6, markersize=4,
        label=r"observed $\max|t|$ — Share 0 (bf0.a_out)")
ax.plot(n, t1, "s-", color="#d63384", linewidth=1.6, markersize=4,
        label=r"observed $\max|t|$ — Share 1 (bf2.a_out)")
ax.plot(n, theoretical, "--", color="#888", linewidth=1.5, alpha=0.9,
        label=r"predicted under leakage hypothesis ($\propto\sqrt{N}$)")
ax.axhline(y=THRESHOLD, color="#c00000", linestyle=":", linewidth=1.5,
           label=fr"TVLA threshold ($\pm{THRESHOLD}$)")

ax.set_xlabel(r"Number of traces $N$", fontsize=11)
ax.set_ylabel(r"$\max\,|t|$  (over all NTT cycles)", fontsize=11)
ax.set_title(r"Evolution of $\max|t|$ vs trace count — BASTION L3 masked NTT",
             fontsize=11)

y_top = max(THRESHOLD * 1.3, float(np.max(theoretical)) * 1.05)
ax.set_ylim(0, y_top)
ax.set_xlim(0, n[-1] * 1.05)
ax.legend(fontsize=9, loc="upper left")
ax.grid(True, alpha=0.3)
fig.tight_layout()
fig.savefig("tvla_evolution.pdf")
fig.savefig("tvla_evolution.png", dpi=200)
print(f"[replot] points: {len(n)}  (N from {n[0]:,} to {n[-1]:,})")
print(f"[replot] sqrt(N) prediction at N={n[-1]:,}: {theoretical[-1]:.1f}")
print(f"[replot] observed at N={n[-1]:,}: s0={t0[-1]:.3f} s1={t1[-1]:.3f}")
print("[replot] written tvla_evolution.pdf / .png")
