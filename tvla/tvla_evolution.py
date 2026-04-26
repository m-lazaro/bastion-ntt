#!/usr/bin/env python3
"""
TVLA Evolution Plot v3 — max|t| vs Number of Traces (per share)
=================================================================
Reads tvla_traces.csv with columns:
    trace_id, type, share, c0, c1, c2, ...
Auto-detects trace length from FIRST DATA ROW (not header), and
truncates all traces to that length, matching tvla_analyze.py logic.

Uses Welford's online algorithm: memory-efficient, processes the
536 MB file traceswith only a few MB of RAM.

USAGE:
    python3 tvla_evolution.py [tvla_traces.csv]

OUTPUT:
    tvla_evolution.csv  - n_traces, max_t_s0, max_t_s1
    tvla_evolution.pdf  - publication-ready figure
    tvla_evolution.png  - preview
"""
import sys
import csv
import numpy as np

CHECKPOINT_STEP = 1000
THRESHOLD = 4.5


def welch_ttest_vec(mean_a, var_a, n_a, mean_b, var_b, n_b):
    if n_a < 2 or n_b < 2:
        return np.zeros_like(mean_a)
    denom = np.sqrt(var_a / n_a + var_b / n_b)
    safe = np.where(denom < 1e-12, 1.0, denom)
    t = (mean_a - mean_b) / safe
    return np.where(denom < 1e-12, 0.0, t)


class Welford:
    def __init__(self, length):
        self.n = 0
        self.mean = np.zeros(length, dtype=np.float64)
        self.M2 = np.zeros(length, dtype=np.float64)

    def update(self, values):
        self.n += 1
        delta = values - self.mean
        self.mean += delta / self.n
        delta2 = values - self.mean
        self.M2 += delta * delta2

    def variance(self):
        if self.n < 2:
            return np.zeros_like(self.mean)
        return self.M2 / (self.n - 1)


def main():
    fname = sys.argv[1] if len(sys.argv) > 1 else "tvla_traces.csv"

    print(f"[TVLA-Evolution] Loading {fname}")
    print(f"[TVLA-Evolution] Auto-detecting trace length from data...")

    # ============================================================
    # PASS 1: discover the COMMON minimum length across ALL traces
    # ============================================================
    min_len = None
    max_len = None
    n_data_rows = 0

    with open(fname, 'r') as f:
        f.readline()  # header
        for line in f:
            parts = line.strip().split(',')
            if len(parts) < 4:
                continue
            # Count valid integer samples after metadata (trace_id, type, share)
            data_part = parts[3:]
            valid_samples = 0
            for x in data_part:
                if x == '':
                    continue
                try:
                    int(x)
                    valid_samples += 1
                except ValueError:
                    break
            if valid_samples == 0:
                continue
            if min_len is None or valid_samples < min_len:
                min_len = valid_samples
            if max_len is None or valid_samples > max_len:
                max_len = valid_samples
            n_data_rows += 1

    if min_len is None:
        print("[ERROR] No valid data rows found")
        sys.exit(1)

    trace_len = min_len
    print(f"[TVLA-Evolution] Data rows: {n_data_rows}")
    print(f"[TVLA-Evolution] Sample range: {min_len} - {max_len}")
    print(f"[TVLA-Evolution] Using trace_len = {trace_len} (truncate to min)")

    # ============================================================
    # PASS 2: process traces with Welford accumulators
    # ============================================================
    acc_s0_F = Welford(trace_len)
    acc_s0_R = Welford(trace_len)
    acc_s1_F = Welford(trace_len)
    acc_s1_R = Welford(trace_len)

    last_id = -1
    unique_traces = 0
    next_ckpt = CHECKPOINT_STEP
    skipped = 0
    evolution = []

    print(f"[TVLA-Evolution] Processing — checkpoint every "
          f"{CHECKPOINT_STEP} unique traces...")

    with open(fname, 'r') as f:
        f.readline()  # header
        for line in f:
            parts = line.strip().split(',')
            if len(parts) < 4:
                skipped += 1
                continue

            try:
                trace_id = int(parts[0])
            except ValueError:
                skipped += 1
                continue

            ttype = parts[1].strip()
            share = parts[2].strip().lower()

            # Truncate to trace_len, matching tvla_analyze.py behavior
            try:
                values_raw = parts[3:3 + trace_len]
                values = np.array(
                    [int(x) for x in values_raw if x != ''][:trace_len],
                    dtype=np.float64
                )
                if len(values) < trace_len:
                    skipped += 1
                    continue
            except ValueError:
                skipped += 1
                continue

            # Route to correct accumulator
            if share in ('s0', '0'):
                if ttype == 'F':
                    acc_s0_F.update(values)
                elif ttype == 'R':
                    acc_s0_R.update(values)
                else:
                    skipped += 1
                    continue
            elif share in ('s1', '1'):
                if ttype == 'F':
                    acc_s1_F.update(values)
                elif ttype == 'R':
                    acc_s1_R.update(values)
                else:
                    skipped += 1
                    continue
            else:
                skipped += 1
                continue

            # Track unique trace count
            if trace_id != last_id:
                unique_traces += 1
                last_id = trace_id

                if unique_traces >= next_ckpt:
                    if (acc_s0_F.n >= 2 and acc_s0_R.n >= 2 and
                            acc_s1_F.n >= 2 and acc_s1_R.n >= 2):
                        t_s0 = welch_ttest_vec(
                            acc_s0_F.mean, acc_s0_F.variance(), acc_s0_F.n,
                            acc_s0_R.mean, acc_s0_R.variance(), acc_s0_R.n
                        )
                        t_s1 = welch_ttest_vec(
                            acc_s1_F.mean, acc_s1_F.variance(), acc_s1_F.n,
                            acc_s1_R.mean, acc_s1_R.variance(), acc_s1_R.n
                        )
                        m0 = float(np.max(np.abs(t_s0)))
                        m1 = float(np.max(np.abs(t_s1)))
                        evolution.append((unique_traces, m0, m1))
                        print(f"  [{unique_traces:6d} traces] "
                              f"max|t|_s0={m0:.3f}  max|t|_s1={m1:.3f}  "
                              f"(F={acc_s0_F.n}, R={acc_s0_R.n})")
                    next_ckpt += CHECKPOINT_STEP

    # Final
    if (acc_s0_F.n >= 2 and acc_s0_R.n >= 2 and
            acc_s1_F.n >= 2 and acc_s1_R.n >= 2):
        t_s0 = welch_ttest_vec(
            acc_s0_F.mean, acc_s0_F.variance(), acc_s0_F.n,
            acc_s0_R.mean, acc_s0_R.variance(), acc_s0_R.n
        )
        t_s1 = welch_ttest_vec(
            acc_s1_F.mean, acc_s1_F.variance(), acc_s1_F.n,
            acc_s1_R.mean, acc_s1_R.variance(), acc_s1_R.n
        )
        m0 = float(np.max(np.abs(t_s0)))
        m1 = float(np.max(np.abs(t_s1)))
        if not evolution or evolution[-1][0] < unique_traces:
            evolution.append((unique_traces, m0, m1))
    else:
        m0 = m1 = 0.0

    print()
    print(f"[TVLA-Evolution] Total unique traces: {unique_traces}")
    print(f"[TVLA-Evolution] Share 0: F={acc_s0_F.n} R={acc_s0_R.n}")
    print(f"[TVLA-Evolution] Share 1: F={acc_s1_F.n} R={acc_s1_R.n}")
    print(f"[TVLA-Evolution] Skipped rows: {skipped}")
    print(f"[TVLA-Evolution] Final max|t|_s0 = {m0:.4f}")
    print(f"[TVLA-Evolution] Final max|t|_s1 = {m1:.4f}")
    print(f"[TVLA-Evolution] Final max|t| both = {max(m0, m1):.4f}")

    if not evolution:
        print("[ERROR] No data points")
        sys.exit(1)

    with open('tvla_evolution.csv', 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['n_traces', 'max_t_s0', 'max_t_s1'])
        for n, t0, t1 in evolution:
            w.writerow([n, f'{t0:.6f}', f'{t1:.6f}'])
    print(f"[TVLA-Evolution] Saved tvla_evolution.csv")

    # Plot
    try:
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt

        n_arr = np.array([e[0] for e in evolution])
        t0_arr = np.array([e[1] for e in evolution])
        t1_arr = np.array([e[2] for e in evolution])

        # sqrt(N) prediction anchored at first checkpoint
        n_anchor = n_arr[0]
        t_anchor = max(t0_arr[0], t1_arr[0])
        theoretical = t_anchor * np.sqrt(n_arr / n_anchor)

        fig, ax = plt.subplots(figsize=(8, 4.5))
        ax.plot(n_arr, t0_arr, 'o-', color='#1f6feb', linewidth=1.6,
                markersize=5,
                label=r'observed $\max|t|$ — Share 0 (bf0.a\_out)')
        ax.plot(n_arr, t1_arr, 's-', color='#d63384', linewidth=1.6,
                markersize=5,
                label=r'observed $\max|t|$ — Share 1 (bf1.a\_out)')
        ax.plot(n_arr, theoretical, '--', color='#888', linewidth=1.5,
                alpha=0.9,
                label=r'predicted under leakage hypothesis ($\propto\sqrt{N}$)')
        ax.axhline(y=THRESHOLD, color='#c00000', linestyle=':',
                   linewidth=1.5, label=f'TVLA threshold ($\\pm{THRESHOLD}$)')

        ax.set_xlabel('Number of traces $N$', fontsize=11)
        ax.set_ylabel(r'$\max\,|t|$  (over all NTT cycles)', fontsize=11)
        ax.set_title(
            r'Evolution of $\max|t|$ vs trace count — '
            r'BASTION L3 masked NTT',
            fontsize=11
        )
        y_top = max(THRESHOLD * 1.3, np.max(theoretical) * 1.05)
        ax.set_ylim(0, y_top)
        ax.set_xlim(0, unique_traces * 1.05)
        ax.legend(fontsize=9, loc='upper left')
        ax.grid(True, alpha=0.3)
        fig.tight_layout()
        fig.savefig('tvla_evolution.pdf')
        fig.savefig('tvla_evolution.png', dpi=200)
        plt.close()
        print(f"[TVLA-Evolution] Saved tvla_evolution.pdf and .png")
    except ImportError:
        print("[TVLA-Evolution] matplotlib not available")

    return 0


if __name__ == "__main__":
    sys.exit(main())
