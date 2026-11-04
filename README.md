# BASTION

**Share schedules for a first-order masked ML-KEM NTT on FPGA**

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23956329.svg)](https://doi.org/10.5281/zenodo.23956329)

This repository is the artifact for **BASTION**, a first-order
arithmetic-masked Number Theoretic Transform (NTT) core for ML-KEM (FIPS 203)
on FPGA, in three share schedules: lock-step, staggered and sequential. In the
two-domain cores every memory bank, butterfly unit and pipeline register
belongs to exactly one share domain, and the controller, twiddle ROM and LFSR
carry only public data.

The repository also contains three unmasked reference configurations used to
separate the cost of masking from that of parallelisation (Baselines A, B
and C).

The version used in the paper, v4.1, is archived on Zenodo:
https://doi.org/10.5281/zenodo.23956329

## Status of this revision

- **Pipeline drain.** The controller raises `done` while the last butterfly
  is still in stages four and five. The interface now asks the reader to
  wait two clock edges after `done` before the first read (protocol below;
  no RTL change), and the sequential core flushes for three cycles between
  its passes instead of one (latency 8,069 cycles, pass offset 4,035). Both
  were found by the oracle (`leakage/oracle.py`).
- **f_max = 1/T**, with T the shortest swept period that closes, in steps of
  0.1 ns; the slack of that implementation does not carry over to a shorter
  period. The sequential core is re-synthesised; the other rows are
  unchanged.
- **Leakage campaigns (A2).** Five independent pairs of runs of 100,000
  traces per schedule, every execution seeded on its own so that the traces
  do not depend on how a run is split into jobs (`scripts/run_a2.sh`).
- **Separation checks.** A negated Vivado filter matched nothing, which made
  Q2 and the classification of Q3 vacuous; the checks take set differences
  in Tcl (reports in `results/separation/`).
- The scripts and CSVs under `tvla/` implement an earlier methodology (two
  share domains recorded separately, first order only) and are kept only for
  reproducibility of that version.

## Repository structure

```
rtl/
  baseline_a/       Single-butterfly baseline (Baseline A)
  baseline_b/       Four-butterfly unmasked datapath with L1/L2 hiding (Baseline B)
  baseline_c/       Iso-architectural unmasked control (Baseline C)
  bastion/          Masked core, lock-step schedule, with preservation attributes
  bastion_nodt/     Masked core without preservation attributes: MEASUREMENT ONLY,
                    not a secure configuration (paper, Section 3.5)
  bastion_stag/     Masked core, staggered schedule (delta and order are inputs)
  bastion_seq/      Masked core, sequential schedule on the Baseline C datapath
kat/                Known-Answer Test vectors (shared across configurations)
leakage/            Leakage harness, oracle and results (see leakage/README.md)
results/            Synthesis results (synthesis.csv) and separation reports
tvla/               Earlier TVLA scripts and CSVs (superseded, see above)
scripts/            Build, period-sweep, simulation and separation-check scripts
paper/figures/      Architecture figure source
```

## Interface protocol of the masked cores

The security argument relies on the following protocol. The testbenches
follow it.

**Load.** Set `ext_share_sel = 0` and `ext_we = 1`, and write the 256 words of
share 0 through `ext_addr_w` / `ext_data_w`. Drop `ext_we`. Then set
`ext_share_sel = 1` and write share 1 in the same way. After the last word of
each share, drive `ext_data_w` and `ext_addr_w` to zero. In the two-domain
cores the input bus reaches the write multiplexers of both domains, so no
share word may remain on it while the transform runs.

**Run.** Pulse `start` and wait for `done`. The staggered core also samples
`delta` (offset between the domains, at least 1) and `order_rand` (a fresh
random bit: which domain leads) at `start`.

**Read back.** Only after `done`, and not before two further clock edges:
`done` rises while the last butterfly is still in the pipeline, and those
edges let it drain before any share word reaches a latch or a read
register. Then assert `ext_re`, keep `ext_share_sel = 0` and present
`ext_addr_r`; each word appears on `ext_data_r` two clock edges after its
address (one edge for the BRAM, one for the read register). After the last
word of share 0, hold `ext_re` low for two cycles, then set
`ext_share_sel = 1` and read share 1. While `ext_re` is low, or before
`done`, the read registers are held at zero, so the output never goes
directly from a word of one share to a word of the other.

Baseline C has the same `ext_re` port and the same two-edge read latency,
with a single read register.

## Requirements

- Icarus Verilog >= 11.0 (`apt install iverilog`), with `iverilog-vpi`
- Python >= 3.8 with `numpy`
- For the leakage campaigns: Verilator 5 (we used 5.037 from OSS CAD
  Suite 2025-06-01); Icarus alone works, about 30 times slower
- For synthesis: Xilinx Vivado 2022.1 (Artix-7 XC7A200T-FBG676-2)

## Functional simulation

```
scripts/run_sim_baseline_a.sh
scripts/run_sim_baseline_b.sh
scripts/run_sim_baseline_c.sh
scripts/run_sim_bastion.sh
scripts/run_sim_bastion_stag.sh
scripts/run_sim_bastion_seq.sh
```

Each script compiles the RTL with Icarus Verilog and runs the KAT testbench on
six ML-KEM-512 test vectors. Latency is counted from the cycle in which
`start` is high to the edge that raises `done`.

| Configuration | KAT runs | Latency (cycles) | Simulation monitors |
|---|---:|---:|---|
| Baseline A | 6 | 8,066 | none |
| Baseline B | 6 | 2,306 | none |
| Baseline C | 6 | 4,034 | none |
| Lock-step (`bastion`) | 6 | 4,034 | read-back: no cycle with both read registers loaded, none before `done`, no direct switch between shares at the output |
| Staggered (`bastion_stag`) | 72: six vectors, delta in {1, 4, 9, 18, 576, 4034}, both orders | 4,034 + delta | read-back as above; the lagging domain repeats the leading domain's addresses, enables, twiddles and dummies exactly delta cycles later |
| Sequential (`bastion_seq`) | 6 | 8,069 | pass 1 repeats pass 0 exactly 4,035 cycles later; no bank output latch or read register goes directly from a word of one share to a word of the other |

All configurations report every KAT as PASS and every monitor count as zero.

## Synthesis and separation checks

```
vivado -mode batch -source scripts/build_config.tcl -tclargs bastion 5.100
scripts/sweep_period.sh bastion 5.200
python3 scripts/collect_synthesis.py
```

`build_config.tcl` implements one configuration at one clock period (the
first argument is a folder under `rtl/`). It writes utilisation (including
slices), hierarchical utilisation and timing reports to `build/reports/`.
`sweep_period.sh` steps the period by 0.1 ns from a starting point and keeps
the shortest period with WNS >= 0; `collect_synthesis.py` gathers the
results into `results/synthesis.csv`. For the two-domain cores (`bastion`,
`bastion_nodt`, `bastion_stag`) the run ends with
`scripts/separation_checks.tcl` on the routed netlist, report
`build/reports/sep_<cfg>_<period>.rpt`; `recheck_separation.tcl` reruns
them on a routed checkpoint:

- Q1: timing paths from domain 0 to domain 1 and back. Must be 0.
- Q2: timing paths from either domain to sequential cells outside both
  (controller, LFSR, ROM, read enables). Must be 0.
- Q3: primitives whose combinational input cone holds cells of both
  domains. Only the output multiplexer and its output buffers may appear,
  with the read registers as their only domain inputs. Must report 0
  UNEXPECTED.
- Q4: `check_timing`: no combinational or latch loops, no unconstrained
  internal endpoints, no register without a clock.

The routed netlist and its SDF are also written to `build/timesim/`. We do
not use them: in a single-corner timing simulation with maximum delays the
paths with the least hold slack (into BRAM inputs, 50 to 120 ps in static
timing) are not reproduced faithfully, and the simulated netlist computes a
wrong transform even at a 20 ns clock. Timing closure rests on static
timing analysis.

## Synthesis results

Artix-7 XC7A200T-FBG676-2, Vivado 2022.1, post-route, shortest period with
WNS >= 0 in steps of 0.1 ns; the next shorter period fails for every row,
and f_max = 1/T (the slack of an implementation does not carry over to a
shorter period, which Vivado places and routes again).

| Configuration | T (ns) | f_max (MHz) | Cycles | LUTs (logic + SRL) | FFs | Slices | DSPs | BRAM | Q1/Q2/Q3 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Baseline A | 4.6 | 217.4 | 8,066 | 150 (142 + 8) | 145 | 58 | 3 | 1.0 | |
| Baseline B | 4.5 | 222.2 | 2,306 | 624 (592 + 32) | 479 | 198 | 12 | 2.5 | |
| Baseline C | 4.4 | 227.3 | 4,034 | 329 (313 + 16) | 319 | 105 | 6 | 1.5 | |
| Lock-step, no attributes | 4.4 | 227.3 | 4,034 | 578 (546 + 32) | 496 | 195 | 12 | 2.5 | 32 / 64 / 64 unexpected: FAIL |
| Lock-step (`bastion`) | 5.1 | 196.1 | 4,034 | 514 | 1,037 | 245 | 12 | 2.5 | 0 / 0 / 0: PASS |
| Staggered | 5.3 | 188.7 | 4,034 + delta | 710 | 1,160 | 310 | 12 | 2.5 | 0 / 0 / 0: PASS |
| Sequential | 5.0 | 200.0 | 8,069 | 338 | 595 | 163 | 6 | 1.5 | single domain |

Without the preservation attributes, synthesis merges the reset-tracking
register of the SRL16E packing of BFU1 into BFU2 and BFU3 (Q1, Q3), and the
physical optimiser moves the product registers of BFU0 and BFU3 out of their
DSP48E1 blocks into flip-flops in the controller hierarchy (Q2).

## Leakage results

Whole-design toggle model (`leakage/README.md`), Verilator, every execution
checked against the reference NTT. Five independent pairs of runs per
schedule: 100,000 traces per run for the schedules, 2,000 for the controls.

```
nohup scripts/run_a2.sh --procs 6 > leakage/results/a2/run.log 2>&1 &
python3 leakage/summarize_a2.py
```

Results in `leakage/results/a2/`: one `detect.py` JSON per pair, one
`detect_pairs.py` summary per schedule, `summary.txt` and `agreement.json`
(detected samples against the oracle).

Schedules (100,000 traces per run). A pair detects at N when both runs
exceed |t| = 4.5 at the same sample on their first N traces; grid 500,
1,000, 2,000, 3,000, 5,000, 7,500, 10,000, then steps of 10,000 to 100,000.
"Detected" pools the samples (bivariate: sample pairs) detected at 100,000
by the five pairs; every one lies in the support view of the oracle, and
13 univariate detections (5 at delta = 9, 8 at delta = 18) lie outside the
form view. The bivariate test pairs samples c and c + delta (c + 4,035 for
the sequential core).

| Schedule | Test | Pairs | N, median (range) | max abs t at N_max, median (range) | Detected (pooled) | Flagged forms / supports |
|---|---|---:|---:|---:|---:|---:|
| Lock-step | 1st order | 0/5 | > 100,000 | 3.9 (3.6 to 4.4) | 0 | n/a |
| Staggered, delta = 1 | 1st order | 0/5 | > 100,000 | 3.7 (3.3 to 4.2) | 0 | n/a |
| Staggered, delta = 4 | 1st order | 0/5 | > 100,000 | 3.8 (3.3 to 4.2) | 0 | n/a |
| Staggered, delta = 9 | 1st order | 0/5 | > 100,000 | 3.7 (3.5 to 4.6) | 0 | n/a |
| Staggered, delta = 18 | 1st order | 0/5 | > 100,000 | 4.0 (3.3 to 4.5) | 0 | n/a |
| Staggered, delta = 576 | 1st order | 0/5 | > 100,000 | 3.9 (3.3 to 4.3) | 0 | n/a |
| Staggered, delta = 4,034 | 1st order | 0/5 | > 100,000 | 3.8 (3.4 to 4.3) | 0 | n/a |
| Sequential | 1st order | 0/5 | > 100,000 | 3.9 (3.6 to 4.3) | 0 | n/a |
| Lock-step | 2nd, univariate | 5/5 | 2,000 (2,000 to 3,000) | 31.8 (29.8 to 32.7) | 1,522 | 4,034 / 4,034 |
| Staggered, delta = 1 | 2nd, univariate | 5/5 | 5,000 (3,000 to 5,000) | 25.8 (25.2 to 27.6) | 667 | 4,033 / 4,033 |
| Staggered, delta = 4 | 2nd, univariate | 5/5 | 20,000 (10,000 to 20,000) | 14.8 (13.8 to 15.9) | 112 | 4,030 / 4,030 |
| Staggered, delta = 9 | 2nd, univariate | 5/5 | 60,000 (60,000 to 60,000) | 6.5 (5.6 to 7.0) | 11 | 2,684 / 2,939 |
| Staggered, delta = 18 | 2nd, univariate | 5/5 | 40,000 (40,000 to 60,000) | 7.7 (7.1 to 8.7) | 8 | 0 / 1,262 |
| Staggered, delta = 576 | 2nd, univariate | 5/5 | 7,500 (5,000 to 20,000) | 13.7 (12.1 to 14.5) | 48 | 1,814 / 1,838 |
| Staggered, delta = 4,034 | 2nd, univariate | 0/5 | > 100,000 | 3.9 (3.6 to 4.5) | 0 | 0 / 0 |
| Sequential | 2nd, univariate | 0/5 | > 100,000 | 4.1 (3.7 to 5.1) | 0 | 0 / 0 |
| Staggered, delta = 1 | 2nd, bivariate | 5/5 | 5,000 (3,000 to 5,000) | 24.5 (23.5 to 26.3) | 1,031 | 4,034 / 4,034 |
| Staggered, delta = 4 | 2nd, bivariate | 5/5 | 3,000 (1,000 to 5,000) | 34.6 (32.2 to 35.4) | 914 | 4,042 / 4,044 |
| Staggered, delta = 9 | 2nd, bivariate | 5/5 | 3,000 (2,000 to 5,000) | 29.1 (27.3 to 30.6) | 1,008 | 4,062 / 4,063 |
| Staggered, delta = 18 | 2nd, bivariate | 5/5 | 5,000 (3,000 to 5,000) | 26.2 (24.2 to 27.2) | 1,004 | 4,083 / 4,090 |
| Staggered, delta = 576 | 2nd, bivariate | 5/5 | 3,000 (2,000 to 5,000) | 34.7 (32.8 to 36.1) | 1,176 | 4,067 / 4,557 |
| Staggered, delta = 4,034 | 2nd, bivariate | 5/5 | 1,000 (500 to 2,000) | 46.6 (44.8 to 47.9) | 2,077 | 4,034 / 5,062 |
| Sequential | 2nd, bivariate | 5/5 | 1,000 (1,000 to 2,000) | 46.9 (45.6 to 47.4) | 2,075 | 4,035 / 4,293 |

Controls (2,000 traces per run, grid 25, 50, 100, 150, 200, 300, 400, 500,
750, 1,000, 1,500, 2,000):

| Control | Test | Pairs | N, median (range) | max abs t at 2,000, median (range) |
|---|---|---:|---:|---:|
| C1 | 1st order | 5/5 | 400 (300 to 750) | 10.5 (9.3 to 11.7) |
| C1 | 2nd, univariate | 5/5 | 1,500 (1,500 to 2,000) | 5.9 (5.5 to 6.4) |
| C2 | 1st order | 5/5 | 300 (200 to 300) | 13.9 (13.1 to 14.7) |
| C2 | 2nd, univariate | 5/5 | 1,500 (1,000 to 2,000) | 6.3 (5.6 to 7.3) |
| C3 | 1st order | 5/5 | 100 (100 to 150) | 20.6 (19.6 to 22.0) |
| C3 | 2nd, univariate | 5/5 | 750 (750 to 750) | 9.1 (8.5 to 10.5) |
| Baseline B | 1st order | 5/5 | 25 (25 to 25) | 100.4 (94.5 to 102.4) |
| Baseline B | 2nd, univariate | 5/5 | 25 (25 to 25) | 26.5 (25.7 to 27.0) |

All 8,080,000 executions recombine to the reference transform (0 bad
read-backs in `leakage/results/a2/run.log`).

## Licence

Apache License 2.0, see [LICENSE](LICENSE).
