"""Shared definitions for the leakage harness: configurations, inputs and
the reference NTT used to check every simulated execution."""
import os
import subprocess
import numpy as np

Q = 3329
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
RTL = os.path.join(REPO, "rtl")
BUILD = os.path.join(HERE, "build")

# configuration -> (rtl folder, testbench macros, number of shares)
CONFIGS = {
    "lockstep":   ("bastion",      ["CFG_MASKED"], 2),
    "staggered":  ("bastion_stag", ["CFG_STAG"], 2),
    "sequential": ("bastion_seq",  ["CFG_MASKED"], 2),
    "nodt":       ("bastion_nodt", ["CFG_MASKED"], 2),
    "baseline_b": ("baseline_b",   ["CFG_BASE_B"], 1),
    "baseline_c": ("baseline_c",   ["CFG_BASE_C"], 1),
    "c1":         ("bastion",      ["CFG_MASKED", "CTRL_C1"], 2),
    "c2":         ("bastion",      ["CFG_MASKED", "CTRL_C2"], 2),
    "c3":         ("bastion",      ["CFG_MASKED"], 2),   # weak shares, see make_inputs
}

ZETAS = [
    -1044, -758, -359, -1517, 1493, 1422, 287, 202, -171, 622, 1577, 182,
    962, -1202, -1474, 1468, 573, -1325, 264, 383, -829, 1458, -1602, -130,
    -681, 1017, 732, 608, -1542, 411, -205, -1571, 1223, 652, -552, 1015,
    -1293, 1491, -282, -1544, 516, -8, -320, -666, -1618, -1162, 126, 1469,
    -853, -90, -271, 830, 107, -1421, -247, -951, -398, 961, -1508, -725,
    448, -1065, 677, -1275, -1103, 430, 555, 843, -1251, 871, 1550, 105,
    422, 587, 177, -235, -291, -460, 1574, 1653, -246, 778, 1159, -147,
    -777, 1483, -602, 1119, -1590, 644, -872, 349, 418, 329, -156, -75,
    817, 1097, 603, 610, 1322, -1285, -1465, 384, -1215, -136, 1218, -1335,
    -874, 220, -1187, -1659, -1185, -1530, -1278, 794, -1510, -854, -870, 478,
    -108, -308, 996, 991, 958, -1460, 1522, 1628]
RINV = pow(2 ** 16, -1, Q)


def ntt_ref(f):
    """Forward NTT of FIPS 203 as computed by the RTL (Montgomery twiddles),
    reduced to [0, q). f: array of 256 ints."""
    a = [int(x) % Q for x in f]
    k = 1
    length = 128
    while length >= 2:
        start = 0
        while start < 256:
            z = ZETAS[k] * RINV % Q
            k += 1
            for j in range(start, start + length):
                t = z * a[j + length] % Q
                a[j + length] = (a[j] - t) % Q
                a[j] = (a[j] + t) % Q
            start += 2 * length
        length >>= 1
    return np.array(a)


def make_inputs(cfg, n, seed, f_fixed=None, weak_bits=None):
    """Inputs of one job. Each execution joins the fixed or the random group
    by a fresh coin flip; share 0 is fresh and uniform in [0, q) (in
    [0, 2^weak_bits) for C3), share 1 completes the sharing. Returns the
    flag words, share 0 and share 1 (n x 256 each) and the unshared inputs.
    """
    rng = np.random.default_rng(seed)
    if f_fixed is None:
        f_fixed = np.random.default_rng(20261023).integers(0, Q, 256)
    group = rng.integers(0, 2, n)          # 1 = fixed, 0 = random
    order = rng.integers(0, 2, n)          # staggered core: which domain leads
    f = rng.integers(0, Q, (n, 256))
    f[group == 1] = f_fixed
    if weak_bits is None and cfg == "c3":
        weak_bits = 8
    if weak_bits is None:
        s0 = rng.integers(0, Q, (n, 256))
    else:
        s0 = rng.integers(0, 2 ** weak_bits, (n, 256))
    if CONFIGS[cfg][2] == 1:
        s0 = f.copy()
        s1 = np.zeros_like(f)
    else:
        s1 = (f - s0) % Q
    flags = group | (order << 1)
    return flags, s0, s1, f


def make_inputs_indexed(cfg, base_seed, first, n, f_fixed=None, weak_bits=None):
    """Inputs of executions first .. first+n-1 of a campaign. Execution e
    draws everything it needs (group, order bit, input, share 0) from its
    own generator, seeded by (base_seed, e), so the inputs of an execution
    do not depend on how the campaign is split into jobs."""
    if f_fixed is None:
        f_fixed = np.random.default_rng(20261023).integers(0, Q, 256)
    if weak_bits is None and cfg == "c3":
        weak_bits = 8
    flags = np.empty(n, dtype=np.int64)
    s0 = np.empty((n, 256), dtype=np.int64)
    f = np.empty((n, 256), dtype=np.int64)
    for i in range(n):
        rng = np.random.default_rng([base_seed, first + i])
        group = int(rng.integers(0, 2))     # 1 = fixed, 0 = random
        order = int(rng.integers(0, 2))     # staggered core: which domain leads
        f[i] = f_fixed if group == 1 else rng.integers(0, Q, 256)
        s0[i] = rng.integers(0, Q if weak_bits is None else 2 ** weak_bits, 256)
        flags[i] = group | (order << 1)
    if CONFIGS[cfg][2] == 1:
        s0 = f.copy()
        s1 = np.zeros_like(f)
    else:
        s1 = (f - s0) % Q
    return flags, s0, s1, f


def write_inputs(path, flags, s0, s1):
    n = len(flags)
    words = np.empty((n, 513), dtype=np.int64)
    words[:, 0] = flags
    words[:, 1:257] = s0
    words[:, 257:] = s1
    with open(path, "w") as fh:
        fh.write("\n".join("%04x" % (w & 0xFFFF) for w in words.ravel()))
        fh.write("\n")


def compile_cfg(cfg):
    """Compile the testbench for one configuration; returns the vvp image."""
    folder, macros, _ = CONFIGS[cfg]
    os.makedirs(BUILD, exist_ok=True)
    vpi = os.path.join(BUILD, "toggle.vpi")
    if not os.path.exists(vpi) or os.path.getmtime(vpi) < os.path.getmtime(
            os.path.join(HERE, "vpi", "toggle.c")):
        subprocess.run(["iverilog-vpi", "--name=" + os.path.join(BUILD, "toggle"),
                        os.path.join(HERE, "vpi", "toggle.c")],
                       check=True, cwd=BUILD, capture_output=True)
    src_dir = os.path.join(RTL, folder)
    srcs = sorted(os.path.join(src_dir, f) for f in os.listdir(src_dir)
                  if f.endswith(".v") and not f.startswith("tb_")
                  and not f.startswith("chk_"))
    out = os.path.join(BUILD, "tb_%s.vvp" % cfg)
    tmp = "%s.%d" % (out, os.getpid())
    cmd = ["iverilog", "-g2012", "-o", tmp] + ["-D" + m for m in macros] + \
          [os.path.join(HERE, "tb_leak.v")] + srcs
    subprocess.run(cmd, check=True)
    os.replace(tmp, out)      # a running simulation keeps its own image
    return out


def run_vvp(image, args, cwd):
    cmd = ["vvp", "-n", "-M", BUILD, "-m", "toggle", image] + args
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if "[DONE]" not in r.stdout:
        raise RuntimeError("simulation failed:\n" + r.stdout[-3000:] + r.stderr[-3000:])
    return r.stdout


def check_outputs(chk_path, f, nsh):
    """Every read-back must recombine to the reference NTT of its input."""
    words = np.loadtxt(chk_path, dtype=str)
    vals = np.array([int(w, 16) for w in words], dtype=np.int64)
    vals = np.where(vals >= 0x8000, vals - 0x10000, vals).reshape(len(f), nsh, 256)
    rec = vals.sum(axis=1) % Q
    bad = 0
    for t in range(len(f)):
        if not np.array_equal(rec[t], ntt_ref(f[t])):
            bad += 1
    return bad
