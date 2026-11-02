#!/usr/bin/env python3
"""Welch t-tests of one run at every point of a grid, in one pass.

The traces are integers (toggle counts), so the raw moments that the three
tests need are accumulated exactly in int64, per group and as running sums
over the executions in index order:
  first order        S1 = sum x, S2 = sum x^2
  univariate 2nd     S3 = sum x^3, S4 = sum x^4
  bivariate 2nd      sums of x y, x^2 y, x y^2, x^2 y^2 with y = x[c + delta]
At each grid point N (the first N executions of the run) the centred
statistics are formed from them with exact integer arithmetic (Python
integers), centring on the group means of those N executions, as
ttest.py does in two passes. A sample whose groups both have zero variance
gets t = 0 if the means are equal and t = inf otherwise.

    python3 leakage/moments.py <campaign dir> [--delta D] [--grid 500,1000,...]

writes <campaign dir>/tstats.npz: grid, n (traces per group at each grid
point), t1, t2u and, with --delta, t2b (one row per grid point).
"""
import argparse
import glob
import os

import numpy as np

GRID_A2 = [500, 1000, 2000, 3000, 5000, 7500, 10000, 20000, 30000, 40000,
           50000, 60000, 70000, 80000, 90000, 100000]
GRID_CONTROLS = [25, 50, 100, 150, 200, 300, 400, 500, 750, 1000, 1500, 2000]


def _obj(a):
    return np.asarray(a, dtype=np.int64).astype(object)


def _t_from_exact(mean_num, mean_den, var_num, var_den, n):
    """Welch t from exact group means mean_num[g] / mean_den[g] and
    variances var_num[g] / var_den[g] (object arrays of Python ints over
    the samples, int denominators) and group sizes n."""
    eq = np.array([a * mean_den[1] == b * mean_den[0]
                   for a, b in zip(mean_num[0], mean_num[1])])
    both_zero = np.array([u == 0 and v == 0 for u, v in zip(var_num[0], var_num[1])])
    m = [np.array([float(x) for x in mean_num[g]]) / mean_den[g] for g in (0, 1)]
    v = [np.array([float(x) for x in var_num[g]]) / var_den[g] for g in (0, 1)]
    den = np.sqrt(v[0] / n[0] + v[1] / n[1])
    with np.errstate(divide="ignore", invalid="ignore"):
        t = np.where(den > 0, (m[0] - m[1]) / den, 0.0)
    return np.where(both_zero, np.where(eq, 0.0, np.inf), t)


class Acc:
    """Running exact sums for one group."""

    def __init__(self, L, delta):
        self.n = 0
        self.S = [np.zeros(L, np.int64) for _ in range(4)]       # x^1..x^4
        self.delta = delta
        if delta:
            self.P = [np.zeros(L - delta, np.int64) for _ in range(4)]  # xy, x2y, xy2, x2y2

    def add(self, x):
        """x: rows of one group, int64."""
        self.n += len(x)
        x2 = x * x
        self.S[0] += x.sum(0)
        self.S[1] += x2.sum(0)
        self.S[2] += (x2 * x).sum(0)
        self.S[3] += (x2 * x2).sum(0)
        if self.delta:
            d = self.delta
            a, b = x[:, :-d], x[:, d:]
            a2, b2 = x2[:, :-d], x2[:, d:]
            self.P[0] += (a * b).sum(0)
            self.P[1] += (a2 * b).sum(0)
            self.P[2] += (a * b2).sum(0)
            self.P[3] += (a2 * b2).sum(0)

    def snapshot(self):
        out = {"n": self.n, "S": [_obj(s) for s in self.S]}
        if self.delta:
            out["P"] = [_obj(p) for p in self.P]
        return out


def _stats(sn0, sn1, delta):
    """t1, t2u, t2b from two group snapshots, exact."""
    res = {}
    n = (sn0["n"], sn1["n"])
    A, B, S1 = [], [], []
    for sn in (sn0, sn1):
        k = sn["n"]
        s1, s2, s3, s4 = sn["S"]
        a = k * s2 - s1 * s1                                           # k^2 m2
        b = k ** 3 * s4 - 4 * k * k * s3 * s1 + 6 * k * s2 * s1 * s1 - 3 * s1 ** 4   # k^4 m4
        A.append(a); B.append(b); S1.append(s1)
    # first order: mean S1/n, variance A/n^2
    res["t1"] = _t_from_exact(S1, (n[0], n[1]), A, (n[0] ** 2, n[1] ** 2), n)
    # univariate 2nd order: y = (x - mu)^2, mean A/n^2, variance (B - A^2)/n^4
    res["t2u"] = _t_from_exact(A, (n[0] ** 2, n[1] ** 2),
                               [B[0] - A[0] * A[0], B[1] - A[1] * A[1]],
                               (n[0] ** 4, n[1] ** 4), n)
    if delta:
        C, D = [], []
        for sn in (sn0, sn1):
            k = sn["n"]
            sx, sx2 = sn["S"][0][:-delta], sn["S"][1][:-delta]
            sy, sy2 = sn["S"][0][delta:], sn["S"][1][delta:]
            p11, p21, p12, p22 = sn["P"]
            c = k * p11 - sx * sy                                      # k^2 E[z]
            d = (k ** 3 * p22 - 2 * k * k * sy * p21 - 2 * k * k * sx * p12
                 + k * sy * sy * sx2 + k * sx * sx * sy2 + 4 * k * sx * sy * p11
                 - 3 * sx * sx * sy * sy)                              # k^4 E[z^2]
            C.append(c); D.append(d)
        res["t2b"] = _t_from_exact(C, (n[0] ** 2, n[1] ** 2),
                                   [D[0] - C[0] * C[0], D[1] - C[1] * C[1]],
                                   (n[0] ** 4, n[1] ** 4), n)
    return res


def run_tstats(cdir, delta=0, grid=None, save=True):
    grid = sorted(grid or GRID_A2)
    jobs = sorted(glob.glob(os.path.join(cdir, "job*.npy")))
    accs = None
    out = {"grid": [], "n": [], "t1": [], "t2u": []}
    if delta:
        out["t2b"] = []
    seen = 0
    gi = 0
    for jf in jobs:
        tr = np.load(jf).astype(np.int64)
        g = np.load(jf.replace("job", "flags")) & 1
        if accs is None:
            L = tr.shape[1]
            accs = (Acc(L, delta), Acc(L, delta))     # group 0 random, 1 fixed
        pos = 0
        while pos < len(tr):
            if gi < len(grid):
                take = min(len(tr) - pos, grid[gi] - seen)
            else:
                take = len(tr) - pos
            seg, gs = tr[pos:pos + take], g[pos:pos + take]
            for k in (0, 1):
                sel = seg[gs == k]
                if len(sel):
                    accs[k].add(sel)
            pos += take
            seen += take
            if gi < len(grid) and seen == grid[gi]:
                r = _stats(accs[0].snapshot(), accs[1].snapshot(), delta)
                out["grid"].append(grid[gi])
                out["n"].append((accs[0].n, accs[1].n))
                for key in r:
                    out[key].append(r[key].astype(np.float32))
                gi += 1
        if gi >= len(grid):
            break
    res = {k: np.array(v) for k, v in out.items()}
    res["total"] = seen
    if save:
        np.savez_compressed(os.path.join(cdir, "tstats.npz"), **res)
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cdir")
    ap.add_argument("--delta", type=int, default=0)
    ap.add_argument("--grid", default="")
    a = ap.parse_args()
    grid = [int(x) for x in a.grid.split(",") if x] or GRID_A2
    r = run_tstats(a.cdir, a.delta, grid)
    for i, n in enumerate(r["grid"]):
        line = "N=%6d" % n
        for k in ("t1", "t2u", "t2b"):
            if k in r:
                line += "  %s max|t| %7.2f" % (k, np.nanmax(np.abs(r[k][i])))
        print(line)


if __name__ == "__main__":
    main()
