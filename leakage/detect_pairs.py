#!/usr/bin/env python3
"""Summarise the five independent pairs of one schedule (A2).

Reads the detect.py JSON of each pair and gives, for each test:
  - in how many pairs leakage is detected;
  - median and range of the "detected at N" of the pairs, a pair without
    detection counting as "> N_max" (the range is then open);
  - median and range of the maximum |t| of the ten runs at N_max.
Writes a JSON and prints a text table.

    python3 leakage/detect_pairs.py <label> pair1.json ... pair5.json
            [--out summary.json]
"""
import argparse
import json

import numpy as np


def summarise(files):
    pairs = [json.load(open(f)) for f in files]
    nmax = min(p["grid"][-1] for p in pairs)
    tests = [k for k in ("t1", "t2u", "t2b") if all(k in p for p in pairs)]
    out = {"pairs": len(pairs), "N_max": nmax, "files": files}
    for k in tests:
        firsts = [p["first_detection"][k] for p in pairs]
        det = [f for f in firsts if f is not None]
        # a pair without detection ranks above every grid point
        key = sorted(firsts, key=lambda f: (f is None, f if f is not None else 0))
        med = key[len(key) // 2]
        tmax = [t for p in pairs for t in p[k]["max_abs_t"]]
        out[k] = {
            "pairs_detecting": len(det),
            "detected_at": firsts,
            "median_N": med if med is not None else "> %d" % nmax,
            "range_N": [key[0] if key[0] is not None else "> %d" % nmax,
                        key[-1] if key[-1] is not None else "> %d" % nmax],
            "tmax_runs": tmax,
            "median_tmax": float(np.median(tmax)),
            "range_tmax": [float(min(tmax)), float(max(tmax))],
        }
    return out


def fmt_n(v):
    return v if isinstance(v, str) else "{:,}".format(v)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("label")
    ap.add_argument("files", nargs="+")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    s = summarise(a.files)
    s["label"] = a.label
    print("%s: %d pairs, N_max = %s" % (a.label, s["pairs"], fmt_n(s["N_max"])))
    for k in ("t1", "t2u", "t2b"):
        if k in s:
            e = s[k]
            print("  %-4s detected in %d/%d pairs | N median %s, range %s to %s | "
                  "max|t| median %.1f, range %.1f to %.1f" % (
                      k, e["pairs_detecting"], s["pairs"], fmt_n(e["median_N"]),
                      fmt_n(e["range_N"][0]), fmt_n(e["range_N"][1]),
                      e["median_tmax"], e["range_tmax"][0], e["range_tmax"][1]))
    if a.out:
        with open(a.out, "w") as fh:
            json.dump(s, fh, indent=1)


if __name__ == "__main__":
    main()
