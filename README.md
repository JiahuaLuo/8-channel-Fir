# 8ch_FIR

This repository contains a standalone RTL project for an 8-channel FIR equalizer developed in the EE477 flow. The local project directory is named `8ch_FIR`, and the design includes channelized FIR datapaths, top-level wrappers, and testbenches for simulation and implementation experiments.

## Project Overview

The project focuses on an 8-channel FIR equalizer architecture with multiple integration styles:

- A direct 8-channel top-level implementation
- A time-division multiplexed 8-channel top-level implementation
- Supporting 4-channel reference modules used during development and debug

The current active setup is centered around:

- Top module: `fir_equalizer_8ch_tdm_bsg_top`
- Testbench: `tb_fir_equalizer_8ch_tdm_bsg_top`
- Constraints: `cfg/constraints.tcl`

## Input Format

One valid beat on BSG-Link #1 carries a single sample transaction in the form:

```text
{channel_id[2:0], sample_data[7:0]}
```

This packs the target channel and its 8-bit sample value into one transfer.

## Directory Structure

```text
.
├── cfg/        Project configuration, source lists, and constraints
├── v/          RTL source files and testbenches
├── Makefile    Common project entry points
└── README.md   Project summary and usage notes
```

Important files in `v/` include:

- `fir_equalizer_8ch_bsg_top.sv`
- `fir_equalizer_8ch_tdm_bsg_top.sv`
- `tb_fir_equalizer_8ch_bsg_top.sv`
- `tb_fir_equalizer_8ch_tdm_bsg_top.sv`

## Common Commands

Typical flow commands:

```bash
make sim-rtl
make syn
make sim-syn
make par
make sim-par
```

## Notes

- Generated outputs such as build artifacts, logs, and waveform files are excluded from version control.
- This repository is intended to keep the 8-channel project isolated from other coursework directories.
