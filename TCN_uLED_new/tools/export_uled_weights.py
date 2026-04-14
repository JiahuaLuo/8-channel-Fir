#!/usr/bin/env python3
"""Export a trained floating-point checkpoint into an RTL-friendly JSON spec."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", type=Path, required=True, help="checkpoint_float.npz from train_uled_tcn.py")
    parser.add_argument("--out", type=Path, required=True, help="Output quantized JSON spec")
    parser.add_argument("--override-frac-bits", type=int, default=None, help="Optional export-time frac bits override")
    parser.add_argument("--override-data-width", type=int, default=None, help="Optional export-time data width override")
    return parser.parse_args()


def quantize_array(array: np.ndarray, frac_bits: int, data_width: int) -> np.ndarray:
    scale = 1 << frac_bits
    q = np.round(array * scale)
    min_val = -(1 << (data_width - 1))
    max_val = (1 << (data_width - 1)) - 1
    return np.clip(q, min_val, max_val).astype(np.int32)


def main() -> None:
    args = parse_args()
    ckpt = np.load(args.checkpoint, allow_pickle=False)

    kernel_sizes = ckpt["kernel_sizes"].astype(np.int32).tolist()
    channel_sizes = ckpt["channel_sizes"].astype(np.int32).tolist()
    dilations = ckpt["dilations"].astype(np.int32).tolist()
    frac_bits = int(args.override_frac_bits if args.override_frac_bits is not None else ckpt["frac_bits"][0])
    data_width = int(args.override_data_width if args.override_data_width is not None else ckpt["data_width"][0])
    n_ctx = int(ckpt["n_ctx"][0])
    latency = int(ckpt["latency"][0])

    weights = []
    quant_report = {"layers": []}

    for idx, _ in enumerate(kernel_sizes):
        weight = ckpt[f"layer{idx}_weight"]
        q_weight = quantize_array(weight, frac_bits, data_width)
        q_weight = q_weight[:, :, ::-1]
        weights.append(q_weight.astype(int).tolist())

        quant_report["layers"].append(
            {
                "layer": idx,
                "float_min": float(weight.min()),
                "float_max": float(weight.max()),
                "quant_min": int(q_weight.min()),
                "quant_max": int(q_weight.max()),
            }
        )

    spec = {
        "n_ctx": n_ctx,
        "data_width": data_width,
        "frac_bits": frac_bits,
        "latency": latency,
        "kernel_sizes": kernel_sizes,
        "dilations": dilations,
        "strides": [1 for _ in kernel_sizes],
        "channel_sizes": channel_sizes,
        "weights": weights,
        "export_metadata": {
            "checkpoint": str(args.checkpoint),
            "sample_scale": float(ckpt["sample_scale"][0]),
            "target_scale": float(ckpt["target_scale"][0]),
            "center_input_u8": bool(int(ckpt["center_input_u8"][0])),
        },
    }

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(spec, indent=2))
    report_path = args.out.with_suffix(".report.json")
    report_path.write_text(json.dumps(quant_report, indent=2))

    print(f"[export] wrote spec   {args.out}")
    print(f"[export] wrote report {report_path}")


if __name__ == "__main__":
    main()
