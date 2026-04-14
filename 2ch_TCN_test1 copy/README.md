# 2ch_TCN_test1

`2ch_TCN_test1` is a first-pass 2-channel ASIC-oriented TDM equalizer that
keeps the existing chip-top/config shell style while replacing the FIR-style
datapath with a small fixed-weight TCN.

## Overview

This version combines:

- the 2-channel shell and debug/config interface style from the earlier
  `2ch_TCN` flow
- the TCN datapath direction derived from `uLED_pre`
- per-channel history/state with shared compute hardware across channels

The intent of this step is to prove that two logical channels can share the
same TCN compute pipeline without corrupting each other's temporal context.

## Implemented Architecture

- 2 independent input contexts: `ctx0`, `ctx1`
- shared TCN weights
- shared compute per layer
- per-context history state inside `v/conv_1d_ctx.sv`
- 2-layer TCN with shape `1 -> 4 -> 1`
- ReLU after each convolution block
- no residual path
- fixed compile-time weights from `v/tcn_cfg_pkg.sv`
- existing chip-top / cfg / probe structure preserved
- threshold register interpreted as a signed 8-bit TCN score threshold

## Directory Layout

- `v/tcn_cfg_pkg.sv`: compile-time TCN parameters and weights
- `v/conv_1d_ctx.sv`: context-aware 1D convolution with per-channel history
- `v/tcn_block_ctx.sv`: TCN block wrapper around the context-aware convolution
- `v/tcn_top_ctx.sv`: top-level 2-layer TCN datapath
- `v/tcn_equalizer_2ch_tdm.sv`: 2-channel TDM equalizer core
- `v/tcn_equalizer_2ch_tdm_bsg_top.sv`: BSG-style wrapper/top integration
- `v/tcn_equalizer_2ch_tdm_chip_top.sv`: chip-top wrapper
- `v/cfg_debug_ctrl.sv`: config/debug register block
- `v/cfg_nibble_adapter.sv`: nibble-based config transport adapter
- `v/probe_mux_4ch.sv`: debug probe mux
- `v/tb_tcn_equalizer_2ch_tdm_chip_top.sv`: RTL testbench
- `cfg/`: Hammer/simulation configuration files

## Testbench Coverage

The testbench is intended to cover:

- basic smoke/config readback behavior
- channel isolation under shared-compute execution
- signed threshold semantics
- debug probe visibility for input and score paths

## Build and Run

From this directory:

```bash
make sim-rtl
```

The generated simulation artifacts are placed under `build/sim-rtl-rundir/`.

## Current Limitations

- runtime TCN weight programming is not enabled yet
- `ADDR_WREAD` is still a placeholder path
- weights come from compile-time constants in `v/tcn_cfg_pkg.sv`
- the flow depends on a working Synopsys VCS license server for `make sim-rtl`

## What You Still Need For uLED Signal Restoration

Right now this directory is a fixed-weight RTL prototype, not yet a full
uLED restoration workflow. The main missing pieces are:

- a Python-side TCN training/reference model for your `rx -> clean/target` data
- a repeatable export step that converts trained/quantized weights into
  `v/tcn_cfg_pkg.sv`
- a golden-reference path that can run the same samples in software before
  comparing them against RTL
- a dataset format for interleaved 2-channel TDM stimuli from the uLED receiver
- a stronger regression that checks expected scores/decisions, not only smoke
  behavior and channel isolation

## Recommended Next Steps

1. Freeze the target problem.
   Decide exactly what one RTL sample means: raw ADC byte, centered signed
   value, or already normalized receiver feature. Also decide whether the TCN
   output should be a restored analog-like sample, a score, or a hard bit.

2. Train a software reference model first.
   Start with the same structure as this RTL (`1 -> 4 -> 1`, kernel `4`,
   8-bit data, 4 fractional bits), then only scale up after the fixed-point
   flow is stable.

3. Quantize and export the model.
   Use `tools/tcn_codegen.py` plus a JSON model spec to generate
   `v/tcn_cfg_pkg.sv`. A starter spec matching the current RTL lives at
   `model_specs/tcn_test1_example.json`.

4. Generate golden outputs from real receiver traces.
   Feed an interleaved `ctx,sample` trace into the same JSON spec with
   `tools/tcn_codegen.py run-ref ...` so you get expected scores before RTL
   simulation.

5. Upgrade the RTL only after the data path is closed.
   Once you can show `Python reference -> exported SV config -> RTL output`
   agree, then add deeper layers, dilation, residual paths, or runtime weight
   loading.

## Training Data Format

For the first pass, use a CSV with:

```text
ctx,sample,target
```

where:

- `ctx` is the logical TDM channel ID (`0` or `1`)
- `sample` is the received sample used as TCN input
- `target` is the desired restored output or score for that sample

Optional columns:

- `split`: `train`, `val`, or `test`
- `time`: explicit per-context ordering key

If `split` is omitted, the training script keeps the temporal order inside
each context and uses the last `--val-fraction` of each context sequence for
validation.

A tiny example file lives at `data/uled_supervised_example.csv`.

## Training And Export Flow

Train a float model with the same high-level structure as the RTL:

```bash
python3 tools/train_uled_tcn.py \
  --csv data/uled_supervised_example.csv \
  --outdir build/train_example \
  --kernel-sizes 4,4 \
  --channel-sizes 1,4,1 \
  --dilations 1,1 \
  --epochs 200 \
  --frac-bits 4 \
  --data-width 8
```

This writes:

- `build/train_example/checkpoint_float.npz`
- `build/train_example/metrics.json`
- `build/train_example/history.json`

Convert the trained float checkpoint into a quantized JSON spec:

```bash
python3 tools/export_uled_weights.py \
  --checkpoint build/train_example/checkpoint_float.npz \
  --out build/train_example/tcn_spec.json
```

Then emit the RTL package from that quantized spec:

```bash
python3 tools/tcn_codegen.py emit-sv \
  --spec build/train_example/tcn_spec.json \
  --out v/tcn_cfg_pkg.sv
```

Important note:

- `train_uled_tcn.py` currently needs PyTorch
- this machine did not have `torch` installed when the scaffold was added
- the closest existing dependency reference in this repo is `../uLED_TCN/environment.yml`
- the export and codegen scripts are dependency-light and were syntax-checked
- the current RTL matches stride `1`, no residual path, and fixed compile-time weights

## New Helper Flow

Export a JSON model spec into the RTL config package:

```bash
python3 tools/tcn_codegen.py emit-sv \
  --spec model_specs/tcn_test1_example.json \
  --out v/tcn_cfg_pkg.sv
```

Run a functional reference model on an interleaved TDM stimulus file:

```bash
python3 tools/tcn_codegen.py run-ref \
  --spec model_specs/tcn_test1_example.json \
  --stim path/to/uled_trace.csv \
  --out build/reference_scores.csv
```

Stimulus CSV format:

```text
ctx,sample
0,12
1,97
0,15
1,103
```

The reference output CSV contains one row per accepted sample with:

```text
index,ctx,sample,score,bit
```

Current scope of `run-ref`:

- models the fixed-weight TCN datapath and per-context history
- useful for weight export and sample-by-sample functional checking
- does not yet model config-register side effects such as bypass/offset modes
- does not yet model exact RTL cycle latency or probe timing

## Recent Debug Note

If you previously saw `Identifier 'rdata' has not been declared yet` in
`v/tb_tcn_equalizer_2ch_tdm_chip_top.sv`, that issue was caused by `rdata`
being declared after tasks that referenced it. The declaration has been moved
up into the main module signal section.
