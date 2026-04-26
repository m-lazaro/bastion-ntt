#!/usr/bin/env python3
"""
TVLA Analysis — Fixed-vs-Random Welch t-test  (dual-share variant)
===================================================================
Methodology: Schneider & Moradi (J. Cryptographic Engineering, 2016)

Reads Hamming-weight traces from BOTH share butterflies (s0, s1) and
runs Welch's t-test independently on each channel. The paper reports
the maximum |t| across both observed wires: if either wire shows
leakage, the masking is broken.

Threshold: |t| > 4.5  ->  false-positive probability < 1e-5 under
multiple-testing correction for thousands of sample points.

Usage:
    python3 tvla_analyze.py [tvla_traces.csv]
"""
import sys
import numpy as np

THRESHOLD = 4.5

# -------------------------------------------------------------------
def welch_ttest(group_a, group_b):
    """Welch's t-test (unequal variance, unequal sample size)."""
    na, nb = len(group_a), len(group_b)
    if na < 2 or nb < 2:
        return 0.0
    mean_a, mean_b = np.mean(group_a), np.mean(group_b)
    var_a, var_b = np.var(group_a, ddof=1), np.var(group_b, ddof=1)
    denom = np.sqrt(var_a / na + var_b / nb)
    if denom < 1e-12:
        return 0.0
    return (mean_a - mean_b) / denom

# -------------------------------------------------------------------
def analyze_channel(fixed_traces, random_traces, name):
    n_fixed, n_random = len(fixed_traces), len(random_traces)
    if n_fixed == 0 or n_random == 0:
        print(f"[TVLA] WARN: no traces for channel {name}")
        return None
    trace_len = min(
        min(len(t) for t in fixed_traces),
        min(len(t) for t in random_traces),
    )
    fixed_arr  = np.asarray([t[:trace_len] for t in fixed_traces],
                            dtype=np.float64)
    random_arr = np.asarray([t[:trace_len] for t in random_traces],
                            dtype=np.float64)
    t_values = np.zeros(trace_len)
    for i in range(trace_len):
        t_values[i] = welch_ttest(fixed_arr[:, i], random_arr[:, i])
    return t_values

# -------------------------------------------------------------------
def main():
    fname = sys.argv[1] if len(sys.argv) > 1 else "tvla_traces.csv"
    print(f"[TVLA] Loading traces from {fname}...")

    # CSV layout: trace_id, type (F/R), share (s0/s1), c0, c1, ...
    channels = {"s0": {"F": [], "R": []},
                "s1": {"F": [], "R": []}}

    with open(fname, "r") as f:
        _ = f.readline()  # skip header
        for line in f:
            parts = line.strip().split(",")
            if len(parts) < 4:
                continue
            t_type, share = parts[1], parts[2]
            if share not in channels or t_type not in channels[share]:
                continue
            hw_values = [int(x) for x in parts[3:] if x != ""]
            channels[share][t_type].append(hw_values)

    # Summary of what we loaded
    for s in ("s0", "s1"):
        print(f"[TVLA]   {s}: {len(channels[s]['F'])} fixed, "
              f"{len(channels[s]['R'])} random")

    # Run the t-test on each share channel
    results = {}
    for s in ("s0", "s1"):
        t_vals = analyze_channel(channels[s]["F"],
                                 channels[s]["R"], s)
        if t_vals is not None:
            results[s] = t_vals

    if not results:
        print("[TVLA] ERROR: no usable traces found")
        sys.exit(1)

    # -----------------------------------------------------------------
    # Report
    # -----------------------------------------------------------------
    all_max = max(float(np.max(np.abs(v))) for v in results.values())
    total_traces = sum(len(channels["s0"][k]) for k in ("F", "R"))

    print()
    print("=" * 68)
    print("  TVLA RESULTS — Non-specific Fixed-vs-Random (dual-share)")
    print("  Methodology: Schneider & Moradi (JCE 2016)")
    print("  Leakage model: Hamming weight of share butterfly output")
    print("=" * 68)
    for s, t_vals in results.items():
        max_t   = float(np.max(np.abs(t_vals)))
        idx_max = int(np.argmax(np.abs(t_vals)))
        n_over  = int(np.sum(np.abs(t_vals) > THRESHOLD))
        print(f"  {s}: max|t| = {max_t:7.4f} at cycle {idx_max:4d}   "
              f"points > {THRESHOLD}: {n_over}")
    print("  " + "-" * 64)
    print(f"  GLOBAL max |t|:  {all_max:.4f}")
    print(f"  Threshold:       {THRESHOLD}")
    if all_max < THRESHOLD:
        print("  RESULT: PASS — no detectable first-order leakage on either share")
    else:
        print("  RESULT: FAIL — leakage detected on at least one channel")
    print("=" * 68)

    # Persist per-channel t-values (for paper plot reproducibility)
    for s, t_vals in results.items():
        np.savetxt(f"tvla_tvalues_{s}.csv", t_vals,
                   delimiter=",", header="t_statistic", comments="")
    print(f"\n[TVLA] Per-channel t-values saved to tvla_tvalues_s0.csv / _s1.csv")

    # -----------------------------------------------------------------
    # Plot: both shares on one figure
    # -----------------------------------------------------------------
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt

        fig, ax = plt.subplots(figsize=(12, 4.5))
        if "s0" in results:
            ax.plot(results["s0"], linewidth=0.6, color="#2563EB",
                    alpha=0.75, label="Share 0 (bf0.a_out)")
        if "s1" in results:
            ax.plot(results["s1"], linewidth=0.6, color="#DB2777",
                    alpha=0.75, label="Share 1 (bf1.a_out)")
        ax.axhline(y= THRESHOLD, color="red", linestyle="--", linewidth=1,
                   label=f"±{THRESHOLD} threshold")
        ax.axhline(y=-THRESHOLD, color="red", linestyle="--", linewidth=1)
        ax.axhline(y=0, color="gray", linestyle="-", linewidth=0.5, alpha=0.4)
        ax.set_xlabel("Clock cycle during NTT", fontsize=11)
        ax.set_ylabel("Welch's t-statistic", fontsize=11)
        ax.set_title(
            f"TVLA Non-specific Fixed-vs-Random: BASTION L3 masked NTT "
            f"({total_traces:,} traces, max |t| = {all_max:.2f})",
            fontsize=12,
        )
        ax.legend(fontsize=10, loc="upper right")
        ax.set_ylim(-2 * THRESHOLD, 2 * THRESHOLD)
        ax.grid(True, alpha=0.3)
        fig.tight_layout()
        fig.savefig("tvla_plot.png", dpi=200)
        plt.close()
        print("[TVLA] Plot saved to tvla_plot.png")
    except ImportError:
        print("[TVLA] matplotlib not available — skipping plot")
        print("       pip3 install matplotlib")

    return 0 if all_max < THRESHOLD else 1


if __name__ == "__main__":
    sys.exit(main())
