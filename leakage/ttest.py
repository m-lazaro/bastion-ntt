#!/usr/bin/env python3
"""Fixed-versus-random Welch t-tests on the toggle traces of a campaign.

Three tests on the same traces:
  first order       the samples as they are
  univariate 2nd    each sample centred on its group mean, squared
  bivariate 2nd     product of the centred samples at c and c + Delta

Centring uses the group means of the whole campaign (two passes over the
job files), as in Schneider and Moradi (CHES 2015). A sample whose two
groups both have zero variance, which happens on public cycles in a
noiseless simulation, gets t = 0 if the means agree and is reported as a
detection otherwise.

    python3 leakage/ttest.py <campaign dir> [--delta D] [--n N] [--out f.npz]
"""
import argparse
import glob
import os

import numpy as np


def load_jobs(cdir, n_max=None):
    jobs = sorted(glob.glob(os.path.join(cdir, "job*.npy")))
    used = 0
    for jf in jobs:
        if n_max is not None and used >= n_max:
            break
        tr = np.load(jf, mmap_mode="r")
        g = np.load(jf.replace("job", "flags")) & 1
        if n_max is not None and used + len(tr) > n_max:
            tr, g = tr[: n_max - used], g[: n_max - used]
        used += len(tr)
        yield np.asarray(tr, dtype=np.float64), g.astype(bool)


def welch_mv(m, v, n):
    """t from per-group means m and variances v (shape 2 x L), counts n."""
    v = np.maximum(v, 0.0)
    den = np.sqrt(v[0] / n[0] + v[1] / n[1])
    diff = m[0] - m[1]
    with np.errstate(divide="ignore", invalid="ignore"):
        t = np.where(den > 0, diff / den, np.where(np.abs(diff) > 1e-9, np.inf, 0.0))
    return t


def welch(s1, s2, n):
    """t from per-group sums s1, s2 of a statistic and its square."""
    m = s1 / n[:, None]
    return welch_mv(m, s2 / n[:, None] - m ** 2, n)


def ttests(cdir, delta=0, n_max=None):
    # pass 1: group means
    S = None
    n = np.zeros(2)
    for tr, g in load_jobs(cdir, n_max):
        if S is None:
            S = np.zeros((2, tr.shape[1]))
        for k in (0, 1):
            sel = tr[g == bool(k)]
            S[k] += sel.sum(axis=0)
            n[k] += len(sel)
    mu = S / n[:, None]
    L = mu.shape[1]
    # pass 2: centred moments
    a1 = np.zeros((2, L)); a2 = np.zeros((2, L))
    b1 = np.zeros((2, L)); b2 = np.zeros((2, L))
    if delta:
        c1 = np.zeros((2, L - delta)); c2 = np.zeros((2, L - delta))
    for tr, g in load_jobs(cdir, n_max):
        for k in (0, 1):
            sel = tr[g == bool(k)]
            x = sel - mu[k]
            a1[k] += x.sum(axis=0)
            a2[k] += (x * x).sum(axis=0)
            y = x * x
            b1[k] += y.sum(axis=0)
            b2[k] += (y * y).sum(axis=0)
            if delta:
                z = x[:, :-delta] * x[:, delta:]
                c1[k] += z.sum(axis=0)
                c2[k] += (z * z).sum(axis=0)
    # first order: group means of pass 1, variances from the centred
    # second moments of pass 2 (a1 is zero up to rounding)
    var = a2 / n[:, None] - (a1 / n[:, None]) ** 2
    res = {"n": n, "t1": welch_mv(mu, var, n), "t2u": welch(b1, b2, n)}
    if delta:
        res["t2b"] = welch(c1, c2, n)
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cdir")
    ap.add_argument("--delta", type=int, default=0)
    ap.add_argument("--n", type=int, default=None)
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    r = ttests(a.cdir, a.delta, a.n)
    print("traces fixed/random: %d / %d" % (r["n"][0], r["n"][1]))
    for k in ("t1", "t2u", "t2b"):
        if k in r:
            t = np.abs(r[k])
            print("%-4s max|t| = %8.2f at sample %d, %d samples above 4.5"
                  % (k, t.max(), t.argmax(), (t > 4.5).sum()))
    if a.out:
        np.savez_compressed(a.out, **r)


if __name__ == "__main__":
    main()
