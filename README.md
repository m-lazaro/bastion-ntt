# BASTION

**A Side-Channel Hardened NTT Accelerator for ML-KEM on FPGA**

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

This repository contains the RTL, testbenches, KAT vectors, and TVLA
analysis scripts for **BASTION**, a first-order arithmetic-masked
Number Theoretic Transform (NTT) accelerator for ML-KEM (FIPS 203)
on FPGA. BASTION partitions the NTT datapath into two spatially
separated share domains so that no combinational wire of the
synthesised netlist crosses the share boundary during computation.

The repository also includes two unmasked baselines (Cara A and
Cara B) used in the paper to characterise the cost of masking.

## Repository structure

```
bastion-ntt/
├── rtl/
│   ├── caraA/             Single-BFU baseline (Cara A)
│   ├── caraB_unmasked/    4-BFU hardened-unmasked baseline (Cara B)
│   └── bastion/           Masked core with spatial share separation
├── kat/                   Known-Answer Test vectors per configuration
├── tvla/                  Trace generation and TVLA analysis scripts
├── scripts/               Build and run helpers
└── paper/figures/         Architecture figures
```

## Requirements

- Icarus Verilog ≥ 11.0 (`apt install iverilog`)
- Python ≥ 3.8 with `numpy`, `matplotlib`
- For synthesis: Xilinx Vivado 2022.1 (Artix-7 XC7A200T-FBG676-2)

## Quick start

### Functional simulation (Cara A)
cd rtl/caraA
iverilog -o sim_ntt tb_ntt_top.v *.v
./sim_ntt

Repeat for `rtl/caraB_unmasked/` and `rtl/bastion/`.

### TVLA simulation (BASTION only)
cd rtl/bastion
iverilog -o sim_tvla tb_tvla.v butterfly.v memory.v memory_bank.v 
lfsr16.v ntt_controller.v ntt_top.v twiddle_rom.v
./sim_tvla
Generates tvla_traces.csv (~536 MB)
cd ../../tvla
python3 tvla_analyze.py ../rtl/bastion/tvla_traces.csv
python3 tvla_evolution.py ../rtl/bastion/tvla_traces.csv

The expected output is **max|t| = 3.961 < 4.5** (PASS) at 30,000 traces.

## Headline results (Artix-7 XC7A200T-FBG676-2, Vivado 2022.1)

| Configuration       | Cycles | f_max   | LUTs | DSPs | BRAM | TVLA              |
|--------------------|-------:|--------:|-----:|-----:|-----:|-------------------|
| Cara A             | 8,068  | 77 MHz  | 173  | 3    | 1.0  | —                 |
| Cara B unmasked    | 2,308  | 77 MHz  | 665  | 12   | 2.5  | L1 + L2 (hiding)  |
| **BASTION masked** | 4,036  | 74 MHz  | 498  | 12   | 2.5  | **PASS @ 30k**    |

## Citation

If you use BASTION in academic work, please cite the paper:
@article{Bastion2026,
author  = {Lázaro Díaz, Marcos},
title   = {BASTION: A Side-Channel Hardened NTT Accelerator for ML-KEM on FPGA},
journal = {IACR Transactions on Cryptographic Hardware and Embedded Systems},
year    = {2026},
note    = {Available at https://github.com/m-lazaro/bastion-ntt}
}

(BibTeX entry will be updated upon acceptance with the official TCHES reference and IACR ePrint identifier.)

## Licence

Apache License 2.0 — see [LICENSE](LICENSE).

## Contact

Marcos Lázaro Díaz — marcoslazarodiaz@gmail.com  
Polytechnical University of Madrid
