#!/usr/bin/env python3
"""
Merge partial TVLA statistics from parallel jobs and compute Welch's t.

Each job emits per-cycle sums and sums-of-squares for the fixed and random
groups. Those are sufficient statistics: merging is exact addition, and the
resulting t-statistic is identical to what a single run over all traces
would have produced. Nothing is approximated.

Matches tvla_analyze.py: sample variance with ddof=1, statistic computed as
(fixed - random), threshold 4.5.

Usage:
    python3 merge_tvla.py tvla_partial_*.csv
"""
import sys, glob, math

THRESHOLD = 4.5

def load(path):
    n_F = n_R = cycles = None
    rows = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("#"):
                for tok in line.lstrip("#").split():
                    if "=" in tok:
                        k, v = tok.split("=", 1)
                        if k == "n_F":    n_F = int(v)
                        elif k == "n_R":  n_R = int(v)
                        elif k == "cycles": cycles = int(v)
                continue
            if line.startswith("cycle,"):
                continue
            parts = line.split(",")
            rows.append([int(x) for x in parts])
    if n_F is None or n_R is None:
        raise ValueError(f"{path}: missing n_F/n_R header")
    return n_F, n_R, cycles, rows

def welch(n_a, s_a, q_a, n_b, s_b, q_b):
    """Welch t from sufficient statistics, ddof=1, computed as a-b."""
    if n_a < 2 or n_b < 2:
        return 0.0
    mean_a = s_a / n_a
    mean_b = s_b / n_b
    # n*sumsq - sum^2 is exact in integer arithmetic; divide last.
    var_a = (n_a * q_a - s_a * s_a) / (n_a * (n_a - 1))
    var_b = (n_b * q_b - s_b * s_b) / (n_b * (n_b - 1))
    denom = math.sqrt(var_a / n_a + var_b / n_b)
    if denom < 1e-12:
        return 0.0
    return (mean_a - mean_b) / denom

def main():
    paths = []
    for a in sys.argv[1:]:
        paths.extend(sorted(glob.glob(a)))
    if not paths:
        print("usage: python3 merge_tvla.py tvla_partial_*.csv")
        sys.exit(1)

    tot_F = tot_R = 0
    n_cycles = None
    acc = None   # per cycle: [s0F, q0F, s1F, q1F, s0R, q0R, s1R, q1R]

    for p in paths:
        n_F, n_R, cycles, rows = load(p)
        print(f"[merge] {p}: n_F={n_F:,} n_R={n_R:,} cycles={len(rows)}")
        if n_cycles is None:
            n_cycles = len(rows)
            acc = [[0]*8 for _ in range(n_cycles)]
        elif len(rows) != n_cycles:
            n_cycles = min(n_cycles, len(rows))
            print(f"[merge] WARN: cycle-count mismatch, truncating to {n_cycles}")
        tot_F += n_F
        tot_R += n_R
        for r in rows[:n_cycles]:
            c = r[0]
            for k in range(8):
                acc[c][k] += r[1 + k]

    print(f"[merge] total: {tot_F:,} fixed + {tot_R:,} random "
          f"= {tot_F + tot_R:,} traces over {n_cycles} cycles")

    t0 = [0.0] * n_cycles
    t1 = [0.0] * n_cycles
    for c in range(n_cycles):
        s0F, q0F, s1F, q1F, s0R, q0R, s1R, q1R = acc[c]
        t0[c] = welch(tot_F, s0F, q0F, tot_R, s0R, q0R)
        t1[c] = welch(tot_F, s1F, q1F, tot_R, s1R, q1R)

    def report(name, t):
        mx = max(abs(v) for v in t)
        idx = max(range(len(t)), key=lambda i: abs(t[i]))
        over = sum(1 for v in t if abs(v) > THRESHOLD)
        print(f"  {name}: max|t| = {mx:7.4f} at cycle {idx:4d}   "
              f"points > {THRESHOLD}: {over}")
        return mx

    print()
    print("=" * 68)
    print("  TVLA RESULTS — Non-specific Fixed-vs-Random (merged, dual-share)")
    print("  Methodology: Schneider & Moradi (JCE 2016)")
    print("  Leakage model: Hamming weight of share butterfly output")
    print("=" * 68)
    m0 = report("s0", t0)
    m1 = report("s1", t1)
    allmax = max(m0, m1)
    print("  " + "-" * 64)
    print(f"  GLOBAL max |t|:  {allmax:.4f}")
    print(f"  Threshold:       {THRESHOLD}")
    if allmax < THRESHOLD:
        print("  RESULT: PASS — no detectable first-order leakage on either share")
    else:
        print("  RESULT: FAIL — leakage detected on at least one channel")
    print("=" * 68)

    for name, t in (("s0", t0), ("s1", t1)):
        out = f"tvla_tvalues_{name}_merged.csv"
        with open(out, "w") as f:
            f.write("t_statistic\n")
            for v in t:
                f.write(f"{v:.10f}\n")
        print(f"[merge] t-values written to {out}")

    return 0 if allmax < THRESHOLD else 1

if __name__ == "__main__":
    sys.exit(main())
