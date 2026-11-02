# Leakage harness

Pre-silicon leakage evaluation of the three share schedules (paper,
Section 6). Everything runs from the repository root.

## Model

One sample per clock cycle: the number of bits that toggle at that rising
edge in every register and every BRAM output latch of the design, both
share domains and the shared control summed. The model is defined by
`vpi/toggle.c`, a VPI module for Icarus Verilog that reads every `reg`
below the DUT after each edge (memories excluded; the RTL has no
combinational `always`, so every `reg` is a flip-flop or a BRAM output
latch). `tb_leak.v` drives the protocol of the top-level README: load share
0, load share 1, transform, read back both shares; the window covers all
of it. Stimulus changes on the falling edge.

Campaigns run on Verilator. `verilator.py` takes the register list from the
VPI module and generates `tg_regs.vh`, the same registers concatenated by
hierarchical reference, so both simulators compute the same sample:

```
python3 -c "import sys; sys.path.insert(0,'leakage'); import verilator as V; print(V.cross_check('lockstep', n=20)[:3])"
```

`results/crosscheck.txt` lists the cross-check of every configuration:
identical traces and read-backs, except the loading phase of the first
execution of C1 (Icarus propagates the unknown contents of uninitialised
memories through the adder that C1 injects; Verilator, two-state, sees
zeros).

## Configurations (`common.py`)

| key | RTL | notes |
|---|---|---|
| `lockstep` | `rtl/bastion` | |
| `staggered` | `rtl/bastion_stag` | `--delta D`; order bit drawn per execution |
| `sequential` | `rtl/bastion_seq` | |
| `baseline_b` | `rtl/baseline_b` | unmasked, toolchain check |
| `c1` | `rtl/bastion` + register loading `s0e_da + s1e_da` | positive control |
| `c2` | `rtl/bastion` + register loading `s0e_da`, `s1e_da` in alternate cycles | positive control |
| `c3` | `rtl/bastion`, share 0 drawn from {0..255} | positive control |

## Running

```
python3 leakage/run_campaign.py lockstep A1 100000 --procs 6
python3 leakage/run_campaign.py lockstep B1 100000 --procs 6
python3 leakage/detect.py leakage/build/campaigns/lockstep_A1 leakage/build/campaigns/lockstep_B1
python3 leakage/run_campaign.py staggered A1 100000 --delta 9
python3 leakage/detect.py leakage/build/campaigns/staggered_d9_A1 \
        leakage/build/campaigns/staggered_d9_B1 --delta 9
```

`scripts/run_a2.sh` runs the whole A2 protocol (five pairs per schedule and
control, detection, summaries) and deletes the traces of each pair once it
is analysed.

Each execution joins the fixed or the random group by a coin flip; share 0
is uniform in Z_q and fresh, share 1 completes the sharing. Every execution
draws its inputs from its own generator, seeded by the run name and the
index of the execution, so runs are independent and a run is the same
whatever `--job` is. The memories are not reset between executions, and an
execution starts from what the previous one left, which depends only on
the previous inputs; each job therefore first replays, without recording
it, the execution before its first one. Every execution is checked: its
read-back shares must recombine to `common.ntt_ref` of its input, and its
window must have the same length as every other execution of the
configuration.

`moments.py` computes, in one pass and with exact integer arithmetic, the
first-order, univariate second-order and (with `--delta`) bivariate
second-order Welch tests at every point of a grid, centring on the group
means of the first N traces, and keeps them in `<run>/tstats.npz`.
`detect.py` declares leakage at N traces when both runs of a pair exceed
|t| = 4.5 at a common sample. `detect_pairs.py` summarises five pairs: in
how many leakage is detected, median and range of the first N, median and
range of the largest |t| of the ten runs. `ttest.py` is the plain two-pass
version of the same tests.

## Oracle

```
python3 leakage/oracle.py lockstep --out leakage/results/oracle_lockstep.npz
python3 leakage/oracle.py staggered --delta 9 --offset 9 --orders 0,1
python3 leakage/oracle.py sequential --offset 4035
python3 leakage/oracle_explain.py staggered 1002 1003 --delta 9
```

The oracle measures, on the RTL, the linear form and the support of every
register at every cycle: one base execution and 512 executions that each
add 1 mod q to one input coefficient of one share, every one preceded by an
undumped base execution so that all start from the same memory contents.
A sample is flagged when the residues of the registers toggling at it can
determine a non-zero combination of the secret (form view: rank over Z_q;
support view: intersection of supports).

`summarize_a2.py` combines the A2 campaigns with the oracle into
`results/a2/agreement.json` and the rows of the schedules table.
