# Logs of this revision (v4)

- `kat_<config>.log`: functional testbench of every core (six ML-KEM-512
  test vectors, latency, and for the sequential core the replay monitor
  `chk_seq.v` with T = 4,035).
- `oracle_<schedule>.log`: oracle runs that produced
  `leakage/results/oracle_*.npz`.
- `crosscheck_v4.txt`: Icarus (VPI) against Verilator, 10 executions per
  configuration (also in `leakage/results/crosscheck.txt`).
- `seed_independence.txt`: the same 2,000 traces with `--job` 500, 1,000
  and 2,000 (per-execution seeds).
- `a2_smoke_test/`: `scripts/run_a2.sh` end to end with small N.
- `vivado_bastion_seq/`: period sweep of the revised sequential core
  (Vivado 2022.1; 5.000 ns closes, 4.900 ns fails), with the timing and
  utilisation reports of the closing run. Host names and absolute paths
  are removed.

The logs of the A2 campaigns are in `leakage/results/a2/logs/` and
`leakage/results/a2/run.log`.
