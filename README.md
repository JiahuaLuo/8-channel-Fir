8-channel standalone project copy

This directory is a self-contained copy of the 8-channel FIR project setup.

Key active configuration:
- Top module: `fir_equalizer_8ch_tdm_bsg_top`
- Testbench: `tb_fir_equalizer_8ch_tdm_bsg_top`
- Constraints source: `cfg/constraints.tcl`

Input interface note:
- BSG-Link #1 now carries one sample transaction per valid beat:
  `{channel_id[2:0], sample_data[7:0]}`.

Typical commands:

```bash
make sim-rtl
make syn
make sim-syn
make par
make sim-par
```

Notes:
- `build/` under this directory is separate from the parent project.
- The original `fir_test_copy_real` project remains unchanged as a fallback workspace.
