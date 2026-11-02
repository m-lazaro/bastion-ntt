#!/usr/bin/env python3
"""
Generate non-overlapping LCG seed pairs for parallel TVLA jobs.

The testbench advances each of its two LCG streams 256 times per trace.
Two jobs whose seeds are close together in the sequence would replay the
same numbers and contribute no independent statistical power, so seeds
are placed far apart by jumping ahead in the recurrence.

LCG:  x <- 1103515245*x + 12345  (mod 2^32)

Jump-ahead uses the composition rule for affine maps: if f(x)=Ax+C then
f^2(x) = A^2 x + C(A+1), so f^k is found by binary exponentiation on the
(A, C) pair -- exact, and instant even for k in the hundreds of millions.

Usage:  python3 gen_seeds.py [n_jobs] [traces_per_job]
"""
import sys

A = 1103515245
C = 12345
M = 1 << 32

def compose(f, g):
    """(A1,C1) after (A2,C2): x -> A1*(A2 x + C2) + C1"""
    a1, c1 = f
    a2, c2 = g
    return ((a1 * a2) % M, (a1 * c2 + c1) % M)

def jump(k):
    """Return (A,C) representing k applications of the LCG."""
    result = (1, 0)
    base = (A, C)
    while k:
        if k & 1:
            result = compose(base, result)
        base = compose(base, base)
        k >>= 1
    return result

def apply_n(seed, k):
    a, c = jump(k)
    return (a * seed + c) % M

def main():
    n_jobs = int(sys.argv[1]) if len(sys.argv) > 1 else 8
    per_job = int(sys.argv[2]) if len(sys.argv) > 2 else 125000

    # Each trace advances each stream 256 times.
    consumed = per_job * 256
    # Leave a 25% margin so streams cannot run into each other.
    stride = int(consumed * 1.25)

    base_in = 0xCAFEBABE
    base_sh = 0xDEADBEEF

    print(f"# {n_jobs} jobs x {per_job:,} traces = {n_jobs*per_job:,} traces total")
    print(f"# each stream advances {consumed:,} steps per job; stride {stride:,}")
    print(f"# LCG period is {M:,}; total span "
          f"{n_jobs*stride:,} ({100*n_jobs*stride/M:.1f}% of the period)")
    if n_jobs * stride >= M:
        print("# WARNING: jobs would wrap around the LCG period -- reduce n_jobs "
              "or traces_per_job")
    print()
    for j in range(n_jobs):
        s_in = apply_n(base_in, j * stride)
        s_sh = apply_n(base_sh, j * stride)
        print(f"{j} {s_in:08x} {s_sh:08x}")

if __name__ == "__main__":
    main()
