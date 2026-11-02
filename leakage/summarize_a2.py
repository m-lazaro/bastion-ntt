#!/usr/bin/env python3
"""Tables of the A2 campaigns and their agreement with the oracle.

Reads leakage/results/a2/<schedule>_pair<k>.json (detect.py),
<schedule>_summary.json (detect_pairs.py) and the oracle results
leakage/results/oracle_<config>.npz, and writes
  leakage/results/a2/agreement.json   detected samples against the flags
  leakage/results/a2/table_schedules.tex   rows of the schedules table
For the agreement, the samples detected by each pair at N_max are pooled
over the five pairs and compared with the samples the oracle flags (both
leading orders pooled for the staggered core). The table has one group of
rows per test: pairs detecting, median and range of N, median and range of
the largest |t| of the ten runs at N_max, samples detected (pooled), and
the samples the form and the support view flag.

    python3 leakage/summarize_a2.py
"""
import glob
import json
import os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
A2 = os.path.join(HERE, "results", "a2")
RES = os.path.join(HERE, "results")
SCHEDULES = [("Lock-step", "lockstep", "oracle_lockstep.npz")] + \
    [("Staggered, $\\delta=%s$" % "{:,}".format(d).replace(",", "{,}"), "staggered_d%d" % d,
      "oracle_staggered_d%d.npz" % d) for d in (1, 4, 9, 18, 576, 4034)] + \
    [("Sequential", "sequential", "oracle_sequential.npz")]


def tex_n(v):
    if isinstance(v, str):
        return "$>10^5$" if v.startswith(">") else v
    return "{:,}".format(v).replace(",", "{,}")


def tex_cells(x, det, frm, sup):
    """Pairs, N median (range), max|t| median (range), detected, flags."""
    lo, hi = x["range_N"]
    if x["pairs_detecting"] == 0:
        n = "$>10^5$"
    else:
        n = "%s (%s--%s)" % (tex_n(x["median_N"]), tex_n(lo), tex_n(hi))
    return "%d/5 & %s & %.1f (%.1f--%.1f) & %s & %s & %s" % (
        x["pairs_detecting"], n, x["median_tmax"], x["range_tmax"][0],
        x["range_tmax"][1], det, frm, sup)


def flags(o, key):
    f = o[key + "_o0"]
    if key + "_o1" in o:
        f = f | o[key + "_o1"]
    return f


def main():
    agree, rows, groups = {}, [], {}
    for label, name, oracle in SCHEDULES:
        sp = os.path.join(A2, name + "_summary.json")
        if not os.path.exists(sp):
            continue
        s = json.load(open(sp))
        pairs = [json.load(open(f)) for f in sorted(glob.glob(os.path.join(A2, name + "_pair*.json")))]
        o = np.load(os.path.join(RES, oracle))
        e = {"pairs": len(pairs), "window": int(len(o["sup_o0"]))}
        for k, key in (("t2u", ""), ("t2b", "b")):
            if k not in s:
                continue
            det = sorted(set(i for p in pairs for i in p[k]["detected"]))
            sup, frm = flags(o, key + "sup"), flags(o, key + "frm")
            det_a = np.array(det, dtype=int)
            e[k] = {"detected_samples_pooled": len(det),
                    "outside_support_view": int((~sup[det_a]).sum()) if len(det) else 0,
                    "outside_form_view": int((~frm[det_a]).sum()) if len(det) else 0,
                    "flagged_support": int(sup.sum()), "flagged_form": int(frm.sum()),
                    "flagged_support_fraction": float(sup.mean()),
                    "flagged_form_fraction": float(frm.mean())}
        agree[name] = e

        for k in ("t1", "t2u", "t2b"):
            if k not in s:
                continue
            if k == "t1":
                det, frm, sup = "0" if s[k]["pairs_detecting"] == 0 else "--", "--", "--"
            else:
                a = e[k]
                det, frm, sup = (tex_n(a["detected_samples_pooled"]), tex_n(a["flagged_form"]),
                                 tex_n(a["flagged_support"]))
            groups.setdefault(k, []).append(
                "%-28s & %s \\\\" % (label, tex_cells(s[k], det, frm, sup)))
    head = {"t1": "First order",
            "t2u": "Second order, univariate",
            "t2b": "Second order, bivariate at the offset of the schedule"}
    for k in ("t1", "t2u", "t2b"):
        if k in groups:
            rows.append("\\midrule\n\\multicolumn{7}{l}{\\emph{%s}} \\\\" % head[k])
            rows.extend(groups[k])
    json.dump(agree, open(os.path.join(A2, "agreement.json"), "w"), indent=1)
    open(os.path.join(A2, "table_schedules.tex"), "w").write("\n".join(rows) + "\n")
    print(json.dumps(agree, indent=1))
    print("\n".join(rows))


if __name__ == "__main__":
    main()
