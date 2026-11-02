#!/usr/bin/env python3
"""List, for chosen samples, the registers that toggle there and depend on
each share (support view), to explain what the oracle flags.

    python3 leakage/oracle_explain.py <config> <sample> [<sample> ...]
            [--delta D] [--order O]
"""
import argparse
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from oracle import measure  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cfg")
    ap.add_argument("samples", type=int, nargs="+")
    ap.add_argument("--delta", type=int, default=0)
    ap.add_argument("--order", type=int, default=0)
    ap.add_argument("--procs", type=int, default=2)
    a = ap.parse_args()
    F0, F1, S0, S1, act, names = measure(a.cfg, a.delta, a.order, a.procs)
    short = [n.replace("tb_leak.wrap.dut.", "") for n in names]
    for s in a.samples:
        print("sample %d (edge between rows %d and %d)" % (s, s, s + 1))
        for r in np.flatnonzero(act[s]):
            for share, S in ((0, S0), (1, S1)):
                old, new = np.flatnonzero(S[s, r]), np.flatnonzero(S[s + 1, r])
                if len(old) or len(new):
                    print("   %-28s share %d  old support %3d coeffs %s  new support %3d coeffs %s"
                          % (short[r], share, len(old), old[:6].tolist(), len(new), new[:6].tolist()))


if __name__ == "__main__":
    main()
