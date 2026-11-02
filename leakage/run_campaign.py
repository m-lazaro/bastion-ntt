#!/usr/bin/env python3
"""Run one leakage campaign: N executions of one configuration, in jobs,
on several processes. Every execution is checked: its read-back shares
must recombine to the reference NTT of its input.

    python3 leakage/run_campaign.py <config> <run> <N> [--delta D]
            [--job 1000] [--procs 6] [--sim verilator|icarus]

<run> names an independent run (A1, B1, ...): it seeds the inputs, so two
runs never share a trace. Each execution has its own seed, derived from the
campaign and its index, so the traces do not depend on --job. Traces go to
leakage/build/campaigns/<name>/.
The default simulator is Verilator; leakage/verilator.py checks that it
gives traces identical to the Icarus VPI model.
"""
import argparse
import hashlib
import os
import shutil
import sys
import time
from multiprocessing import Pool

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import (BUILD, CONFIGS, check_outputs, compile_cfg,  # noqa: E402
                    make_inputs_indexed, run_vvp, write_inputs)
import verilator  # noqa: E402


def campaign_name(cfg, run, delta):
    return "%s%s_%s" % (cfg, "_d%d" % delta if cfg == "staggered" else "", run)


def seed_of(cfg, run, delta):
    h = hashlib.sha256(("%s|%s|%s" % (cfg, run, delta)).encode()).digest()
    return int.from_bytes(h[:8], "little")


def one_job(a):
    cfg, run, delta, job, first, n, image, cdir, sim = a
    out = os.path.join(cdir, "job%04d.npy" % job)
    if os.path.exists(out):
        return job, 0, 0.0
    t0 = time.time()
    wdir = os.path.join(cdir, "tmp%04d" % job)
    os.makedirs(wdir, exist_ok=True)
    # The coefficient memories are not reset between executions, and an
    # execution starts from what the previous one left in them, which
    # depends only on the previous execution's inputs (loading and the
    # transform overwrite every address). A job therefore first runs, without
    # recording it, the execution before its first one, so that every
    # execution sees the same memory state whatever the job size.
    lead = 1 if first > 0 else 0
    flags, s0, s1, f = make_inputs_indexed(cfg, seed_of(cfg, run, delta), first - lead, n + lead)
    fl_in = flags.copy()
    fl_in[:lead] |= 4
    write_inputs(os.path.join(wdir, "in.hex"), fl_in, s0, s1)
    flags, f = flags[lead:], f[lead:]
    args = ["+in=in.hex", "+n=%d" % (n + lead), "+out=tr.bin", "+chk=chk.hex"]
    if cfg == "staggered":
        args.append("+delta=%d" % delta)
    if sim == "verilator":
        verilator.run(image, args, wdir)
    else:
        run_vvp(image, args, wdir)
    bad = check_outputs(os.path.join(wdir, "chk.hex"), f, CONFIGS[cfg][2])
    tr = np.fromfile(os.path.join(wdir, "tr.bin"), dtype=np.uint16).reshape(n, -1)
    np.save(os.path.join(cdir, "flags%04d.npy" % job), flags.astype(np.uint8))
    np.save(out + ".tmp.npy", tr)
    os.replace(out + ".tmp.npy", out)
    shutil.rmtree(wdir)
    return job, bad, time.time() - t0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cfg", choices=sorted(CONFIGS))
    ap.add_argument("run")
    ap.add_argument("n", type=int)
    ap.add_argument("--delta", type=int, default=0)
    ap.add_argument("--job", type=int, default=1000)
    ap.add_argument("--procs", type=int, default=6)
    ap.add_argument("--sim", choices=["verilator", "icarus"], default="verilator")
    a = ap.parse_args()
    name = campaign_name(a.cfg, a.run, a.delta)
    cdir = os.path.join(BUILD, "campaigns", name)
    os.makedirs(cdir, exist_ok=True)
    image = verilator.build(a.cfg) if a.sim == "verilator" else compile_cfg(a.cfg)
    njobs = (a.n + a.job - 1) // a.job
    jobs = [(a.cfg, a.run, a.delta, j, j * a.job, min(a.job, a.n - j * a.job), image, cdir,
             a.sim) for j in range(njobs)]
    bad_total = 0
    t0 = time.time()
    with Pool(a.procs) as pool:
        for job, bad, dt in pool.imap_unordered(one_job, jobs):
            bad_total += bad
            print("%s job %d done in %.0f s, %d bad read-backs" % (name, job, dt, bad),
                  flush=True)
    with open(os.path.join(cdir, "summary.txt"), "w") as fh:
        fh.write("campaign %s\nsimulator %s\nexecutions %d\nbad_readbacks %d\nwall_s %.0f\n"
                 % (name, a.sim, a.n, bad_total, time.time() - t0))
    print("%s: %d executions, %d bad read-backs" % (name, a.n, bad_total))
    if bad_total:
        sys.exit(1)


if __name__ == "__main__":
    main()
