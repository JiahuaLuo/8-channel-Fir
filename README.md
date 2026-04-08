# 8ch_FIR

This repository contains a standalone RTL project for an 8-channel FIR equalizer developed in the EE477 flow. The local project directory is named `8ch_FIR`, and the design includes channelized FIR datapaths, top-level wrappers, and testbenches for simulation and implementation experiments.

## Project Overview

The project focuses on an 8-channel FIR equalizer architecture with multiple integration styles:

- A direct 8-channel top-level implementation
- A time-division multiplexed 8-channel top-level implementation
- Supporting 4-channel reference modules used during development and debug

The current active setup is centered around:

- Top module: `fir_equalizer_8ch_tdm_chip_top`
- Testbench: `tb_fir_equalizer_8ch_tdm_chip_top`
- Constraints: `cfg/constraints.tcl`

The internal verified system-level wrapper `fir_equalizer_8ch_tdm_bsg_top` is still kept in the repo. The new chip-level wrapper compresses the external interface while preserving the existing internal control and data paths.

## External Interface

The chip-level wrapper exposes:

- Real-time input path: `sample_valid`, `sample_ready`, `sample_channel_id[2:0]`, `sample_data[7:0]`
- Narrow config/debug path: `cfg_valid`, `cfg_write`, `cfg_ready`, `cfg_data[3:0]`, `cfg_resp_valid`, `cfg_resp_data[3:0]`
- Real-time output path: `out_bit[7:0]`, `out_frame_valid`, `out_channel_id[2:0]`

One valid sample beat carries a single transaction in the form:

```text
{channel_id[2:0], sample_data[7:0]}
```

This packs the target channel and its 8-bit sample value into one transfer.

The narrow config/debug path is translated back into the original internal wide control interface by `cfg_nibble_adapter.sv`.

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
- `fir_equalizer_8ch_tdm_chip_top.sv`
- `cfg_nibble_adapter.sv`
- `tb_fir_equalizer_8ch_bsg_top.sv`
- `tb_fir_equalizer_8ch_tdm_bsg_top.sv`
- `tb_fir_equalizer_8ch_tdm_chip_top.sv`

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
