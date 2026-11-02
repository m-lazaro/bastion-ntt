#!/usr/bin/env python3
"""Collect the post-implementation figures of every configuration from
build/logs and build/reports into results/synthesis.csv: for each
configuration, the shortest swept period T with WNS >= 0 and its
utilisation, hold slack and separation checks. f_max = 1/T: the slack of
that implementation is not carried over to shorter periods, since Vivado
places and routes again for every target and the next shorter period of
the sweep fails.

    python3 scripts/collect_synthesis.py
"""
import csv
import glob
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGS = os.path.join(ROOT, "build", "logs")
REPORTS = os.path.join(ROOT, "build", "reports")
CYCLES = {"baseline_a": 8066, "baseline_b": 2306, "baseline_c": 4034, "bastion": 4034,
          "bastion_nodt": 4034, "bastion_stag": None, "bastion_seq": 8069}
# The separation reports are read from build/reports; reports written by a
# version of separation_checks.tcl before the set-difference fix must be
# regenerated with scripts/recheck_separation.tcl first.


def util(cfg, per):
    txt = open(os.path.join(REPORTS, "util_%s_%s.rpt" % (cfg, per))).read()

    def cell(name):
        m = re.search(r"\|\s*%s\s*\|\s*([\d.]+)\s*\|" % re.escape(name), txt)
        return float(m.group(1)) if m else None
    return {"luts": cell("Slice LUTs"), "lut_logic": cell("LUT as Logic"),
            "lut_mem": cell("LUT as Memory"), "ffs": cell("Slice Registers"),
            "slices": cell("Slice"), "dsp": cell("DSPs"), "bram": cell("Block RAM Tile")}


def separation(cfg, per):
    """Q1-Q3 counts from the separation report (two-domain cores only)."""
    p = os.path.join(REPORTS, "sep_%s_%s.rpt" % (cfg, per))
    if not os.path.exists(p):
        return ""
    txt = open(p).read()
    cells = re.search(r"sequential cells: (.*)", txt).group(1)
    q1 = sum(int(x) for x in re.findall(r"Q1 paths domain \d to domain \d: (\d+)", txt))
    q2 = int(re.search(r"Q2 paths from a domain to cells outside both: (\d+)", txt).group(1))
    q3 = re.search(r"EXPECTED \(read registers only\) = (\d+), UNEXPECTED = (\d+)", txt)
    return "%s; Q1 %d paths; Q2 %d paths; Q3 %s expected, %s unexpected" % (
        cells, q1, q2, q3.group(1), q3.group(2))


def whs(cfg, per):
    txt = open(os.path.join(REPORTS, "timing_%s_%s.rpt" % (cfg, per))).read()
    i = txt.find("WNS(ns)")
    vals = txt[i:].splitlines()[2].split()
    return float(vals[4])


def main():
    runs = {}
    for out in glob.glob(os.path.join(LOGS, "*.out")):
        m = re.match(r"(.+)_(\d+\.\d+)\.out$", os.path.basename(out))
        if not m:
            continue
        cfg, per = m.group(1), m.group(2)
        txt = open(out).read()
        w = re.search(r"^ WNS +: (-?[\d.]+) ns", txt, re.M)
        if not w:
            continue
        runs.setdefault(cfg, []).append((float(per), float(w.group(1)), None))
    rows = []
    for cfg, lst in sorted(runs.items()):
        met = [r for r in lst if r[1] >= 0]
        if not met:
            continue
        per, wns, sep = min(met)
        p = "%.3f" % per
        u = util(cfg, p)
        fmax = 1000.0 / per
        row = {"config": cfg, "period_ns": p, "wns_ns": wns, "whs_ns": whs(cfg, p),
               "fmax_mhz": round(fmax, 1), **u,
               "separation": separation(cfg, p),
               "swept": " ".join("%.3f:%+.3f" % (a, b) for a, b, _ in sorted(lst))}
        c = CYCLES.get(cfg)
        if c:
            lat = c / fmax
            row.update({"cycles": c, "latency_us": round(lat, 2),
                        "atp_lut_us": round(u["luts"] * lat), "atp_slice_us": round(u["slices"] * lat)})
        rows.append(row)
    os.makedirs(os.path.join(ROOT, "results"), exist_ok=True)
    keys = ["config", "period_ns", "wns_ns", "whs_ns", "fmax_mhz", "cycles", "latency_us",
            "luts", "lut_logic", "lut_mem", "ffs", "slices", "dsp", "bram",
            "atp_lut_us", "atp_slice_us", "separation", "swept"]
    with open(os.path.join(ROOT, "results", "synthesis.csv"), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=keys)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in keys})
    for r in rows:
        print(", ".join("%s=%s" % (k, r.get(k, "")) for k in keys if k != "swept"))
        print("    swept:", r["swept"])


if __name__ == "__main__":
    main()
