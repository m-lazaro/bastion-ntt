#!/usr/bin/env python3
"""Detection with a pair of independent runs: leakage is declared at N
traces when both runs, each on its first N traces, exceed |t| > 4.5 at the
same sample. Prints, for each test, the smallest N of the grid at which
this happens, and the statistics at the largest grid point.

    python3 leakage/detect.py <run A dir> <run B dir> [--delta D]
            [--grid 500,1000,...] [--out f.json]

The t statistics of each run come from moments.py (one exact pass over the
traces, kept in <run dir>/tstats.npz), so the traces can be deleted once
both runs of a pair have been analysed.
"""
import argparse
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from moments import GRID_A2, run_tstats  # noqa: E402

TH = 4.5


def tstats(cdir, delta, grid):
    p = os.path.join(cdir, "tstats.npz")
    if os.path.exists(p):
        r = dict(np.load(p))
        if list(r["grid"]) == list(grid) and (("t2b" in r) == bool(delta)):
            return r
    return run_tstats(cdir, delta, grid)


def detect(dir_a, dir_b, delta=0, grid=None):
    grid = sorted(grid or GRID_A2)
    ra, rb = tstats(dir_a, delta, grid), tstats(dir_b, delta, grid)
    tests = ["t1", "t2u"] + (["t2b"] if delta else [])
    m = min(len(ra["grid"]), len(rb["grid"]))
    out = {"grid": [int(x) for x in ra["grid"][:m]],
           "traces": [int(ra["total"]), int(rb["total"])],
           "first_detection": {}, "per_grid": {}}
    for k in tests:
        first = None
        per = []
        for i in range(m):
            ta, tb = np.abs(ra[k][i]), np.abs(rb[k][i])
            det = (ta > TH) & (tb > TH)
            per.append({"N": int(ra["grid"][i]), "max_abs_t": [float(ta.max()), float(tb.max())],
                        "samples_detected": int(det.sum())})
            if first is None and det.any():
                first = int(ra["grid"][i])
        out["first_detection"][k] = first
        out["per_grid"][k] = per
        ta, tb = np.abs(ra[k][m - 1]), np.abs(rb[k][m - 1])
        det = (ta > TH) & (tb > TH)
        out[k] = {"N": int(ra["grid"][m - 1]),
                  "max_abs_t": [float(ta.max()), float(tb.max())],
                  "min_of_max": float(min(ta.max(), tb.max())),
                  "samples_detected": int(det.sum()),
                  "detected": np.flatnonzero(det).tolist()}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("--delta", type=int, default=0)
    ap.add_argument("--grid", default="")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    grid = [int(x) for x in a.grid.split(",") if x] or GRID_A2
    out = detect(a.a, a.b, a.delta, grid)
    show = {k: v for k, v in out.items() if k not in ("per_grid",)}
    for k in ("t1", "t2u", "t2b"):
        if k in show:
            show[k] = {kk: vv for kk, vv in show[k].items() if kk != "detected"}
    print(json.dumps(show, indent=1))
    if a.out:
        with open(a.out, "w") as fh:
            json.dump(out, fh)


if __name__ == "__main__":
    main()
