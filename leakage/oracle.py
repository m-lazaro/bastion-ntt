#!/usr/bin/env python3
"""Cycle-accurate oracle: at which samples can a schedule combine both
shares of the secret (Observation 1 of the paper)?

The forms are measured on the RTL itself rather than on a separate model.
One base execution is followed by 512 executions that each add 1 (mod q) to
one input coefficient of one share; the LFSR is reseeded before every
execution, so all 513 follow the same public schedule. For every register
r and every row c (the window opening, then every clock edge), the
difference to the base execution gives
  * form view: Delta mod q, which for a register whose value is linear in
    the shares modulo q is the coefficient a_j of its form. Every register
    of the datapath is, except m16_s3 (a product modulo 2^16), which is
    loaded at the same edge as t_full_s3 from the same value and so adds no
    form of its own;
  * support view: the set of coefficients j with Delta != 0, for every
    register: the residues on which its integer value depends.

Sample c is the toggle count of edge c, a function of rows c-1 and c. With
R = M0 F0 + M1 F1 the residues it depends on, its distribution is
independent of f = F0 + F1 iff Im(M1) is contained in Im(M0 - M1), i.e. iff
rank([M0 - M1 | M1]) == rank(M0 - M1); for rows that each belong to one
share this is the row-space condition of Observation 1. The bivariate test
at offset Delta uses rows c-1, c, c+Delta-1 and c+Delta.

    python3 leakage/oracle.py <config> [--delta D] [--offset Delta]
"""
import argparse
import os
import shutil
import sys
from multiprocessing import Pool

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import BUILD, CONFIGS, Q, compile_cfg, run_vvp, write_inputs  # noqa: E402

NONLINEAR = ("m16_s3",)


def rank_mod_q(M):
    """Rank of an integer matrix modulo the prime Q (rows inserted one at a
    time into a basis kept in reduced row echelon form)."""
    M = np.asarray(M, dtype=np.int64) % Q
    B = np.zeros((0, M.shape[1]), np.int64)
    piv = []
    for v in M:
        if piv:
            v = (v - v[piv] @ B) % Q
        nz = np.flatnonzero(v)
        if len(nz) == 0:
            continue
        p = nz[0]
        v = (v * pow(int(v[p]), Q - 2, Q)) % Q
        if piv:
            B = (B - np.outer(B[:, p], v)) % Q
        B = np.vstack([B, v])
        piv.append(p)
    return len(piv)


def leaks_forms(V):
    """V: k x 512 integer rows (form w.r.t. share 0 | form w.r.t. share 1)."""
    if len(V) == 0:
        return False
    M0, M1 = V[:, :256], V[:, 256:]
    if not M1.any() or not M0.any():
        return False
    D = (M0 - M1) % Q
    return rank_mod_q(np.hstack([D, M1])) > rank_mod_q(D)


def sim_job(a):
    image, wdir, inputs, extra = a
    os.makedirs(wdir, exist_ok=True)
    flags, s0, s1 = inputs
    write_inputs(os.path.join(wdir, "in.hex"), flags, s0, s1)
    run_vvp(image, ["+in=in.hex", "+n=%d" % len(flags), "+dump=dump.bin",
                    "+names=names.txt"] + extra, wdir)
    return wdir


def measure(cfg, delta=0, order=0, procs=4, seed=7):
    """Return (forms0, forms1, support0, support1, names): per row and
    register, the form w.r.t. each share (int16, rows x regs x 256) and the
    support masks (bool)."""
    image = compile_cfg(cfg)
    rng = np.random.default_rng(seed)
    b0 = rng.integers(0, Q - 1, 256)        # +1 stays inside [0, q)
    f = rng.integers(0, Q, 256)
    b1 = (f - b0) % Q
    b1 = np.where(b1 == Q - 1, Q - 2, b1)   # keep share 1 perturbable too
    base = os.path.join(BUILD, "oracle", "%s_d%d_o%d" % (cfg, delta, order))
    shutil.rmtree(base, ignore_errors=True)
    extra = ["+delta=%d" % delta] if cfg == "staggered" else []
    jobs = []
    pert = [(s, j) for s in (0, 1) for j in range(256)]
    chunks = np.array_split(np.arange(512), procs * 2)
    # The banks are not reset between executions, and during loading their
    # output latches read what the previous execution left. Every dumped
    # execution is therefore preceded by an undumped execution on the base
    # input (flag bit 2), so that all start from the same memory state.
    for ci, idx in enumerate(chunks):
        n = 2 * (1 + len(idx))
        s0 = np.tile(b0, (n, 1)); s1 = np.tile(b1, (n, 1))
        for row, p in enumerate(idx, start=1):
            s, j = pert[p]
            (s0 if s == 0 else s1)[2 * row + 1, j] += 1
        flags = np.full(n, order << 1)
        flags[0::2] |= 4
        jobs.append((image, os.path.join(base, "j%02d" % ci), (flags, s0, s1), extra))
    with Pool(procs) as pool:
        dirs = pool.map(sim_job, jobs)
    names = [l.split()[3] for l in open(os.path.join(dirs[0], "names.txt"))]
    R = len(names)
    lin = np.array([not any(k in nm for k in NONLINEAR) for nm in names])
    forms = [None, None]
    supp = [None, None]
    act = None
    for ci, (idx, d) in enumerate(zip(chunks, dirs)):
        dump = np.fromfile(os.path.join(d, "dump.bin"), dtype=np.int32)
        dump = dump.reshape(1 + len(idx), -1, R).astype(np.int64)
        rows = dump.shape[1]
        if forms[0] is None:
            forms = [np.zeros((rows, R, 256), np.int16) for _ in (0, 1)]
            supp = [np.zeros((rows, R, 256), bool) for _ in (0, 1)]
            act = np.zeros((rows - 1, R), bool)
        # a register enters the sample of edge c only if it toggles there
        act |= (dump[:, 1:, :] != dump[:, :-1, :]).any(axis=0)
        for k, p in enumerate(idx, start=1):
            s, j = pert[p]
            dlt = dump[k] - dump[0]
            supp[s][:, :, j] = dlt != 0
            forms[s][:, :, j] = np.where(lin[None, :], dlt % Q, 0)
    shutil.rmtree(base)
    return forms[0], forms[1], supp[0], supp[1], act, names


def flag_cycles(F0, F1, S0, S1, act, offset=0):
    """Per sample: (support view flagged, form view flagged). Sample c
    (edge c, 0-based index c-1) depends on rows c-1 and c of the registers
    that toggle at edge c. With offset, the pair (c, c + offset) of the
    bivariate test."""
    L = act.shape[0]                               # samples
    nsamp = L - offset if offset else L
    # support of each sample: registers toggling at the edge, both rows
    m = act[:, :, None]
    u0 = ((S0[:-1] | S0[1:]) & m).any(axis=1)      # L x 256
    u1 = ((S1[:-1] | S1[1:]) & m).any(axis=1)
    sup = np.zeros(nsamp, bool)
    frm = np.zeros(nsamp, bool)
    for c in range(nsamp):
        ss = [c] + ([c + offset] if offset else [])
        a = np.logical_or.reduce([u0[s] for s in ss])
        b = np.logical_or.reduce([u1[s] for s in ss])
        if not (a & b).any():
            continue
        sup[c] = True
        parts = []
        for s in ss:
            r = np.flatnonzero(act[s])
            for row in (s, s + 1):
                parts.append(np.hstack([F0[row, r], F1[row, r]]))
        V = np.concatenate(parts).astype(np.int64)
        V = V[V.any(axis=1)]
        if len(V):
            V = np.unique(V, axis=0)
        frm[c] = leaks_forms(V)
    return sup, frm


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cfg", choices=sorted(CONFIGS))
    ap.add_argument("--delta", type=int, default=0)
    ap.add_argument("--offset", type=int, default=0)
    ap.add_argument("--procs", type=int, default=4)
    ap.add_argument("--orders", default="0",
                    help="staggered core: leading domains to evaluate, e.g. 0,1")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    orders = tuple(int(x) for x in a.orders.split(",")) if a.cfg == "staggered" else (0,)
    res = {}
    for o in orders:
        F0, F1, S0, S1, act, names = measure(a.cfg, a.delta, o, a.procs)
        sup1, frm1 = flag_cycles(F0, F1, S0, S1, act)
        res["sup_o%d" % o], res["frm_o%d" % o] = sup1, frm1
        if a.offset:
            sup2, frm2 = flag_cycles(F0, F1, S0, S1, act, a.offset)
            res["bsup_o%d" % o], res["bfrm_o%d" % o] = sup2, frm2
        print("order %d: %d samples; univariate flagged: forms %d, supports %d"
              % (o, len(sup1), frm1.sum(), sup1.sum()), flush=True)
        if a.offset:
            print("order %d: bivariate (offset %d) flagged: forms %d, supports %d"
                  % (o, a.offset, frm2.sum(), sup2.sum()), flush=True)
    if a.out:
        np.savez_compressed(a.out, **res)


if __name__ == "__main__":
    main()
