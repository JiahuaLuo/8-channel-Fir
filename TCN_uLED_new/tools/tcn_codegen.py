#!/usr/bin/env python3
"""Helper flow for the fixed-weight 2-channel TCN prototype.

This script does two jobs:
1. Emit `v/tcn_cfg_pkg.sv` from a JSON model specification.
2. Run a functional reference model on an interleaved TDM stimulus trace.

The JSON spec is intentionally simple so a trained Python model can export
weights into it without needing to understand the RTL package format.
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Iterable


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    emit_sv = subparsers.add_parser("emit-sv", help="Emit tcn_cfg_pkg.sv from JSON spec")
    emit_sv.add_argument("--spec", type=Path, required=True, help="Path to model JSON spec")
    emit_sv.add_argument("--out", type=Path, required=True, help="Output SystemVerilog package path")

    run_ref = subparsers.add_parser("run-ref", help="Run functional reference model on TDM stimulus")
    run_ref.add_argument("--spec", type=Path, required=True, help="Path to model JSON spec")
    run_ref.add_argument("--stim", type=Path, required=True, help="CSV with ctx,sample columns")
    run_ref.add_argument("--out", type=Path, required=True, help="Output CSV with reference scores")
    run_ref.add_argument("--threshold", type=int, default=0, help="Decision threshold in signed score domain")

    return parser.parse_args()


def load_spec(path: Path) -> dict:
    spec = json.loads(path.read_text())

    required_keys = [
        "n_ctx",
        "data_width",
        "frac_bits",
        "kernel_sizes",
        "dilations",
        "strides",
        "channel_sizes",
        "weights",
    ]
    for key in required_keys:
        if key not in spec:
            raise ValueError(f"Missing required key '{key}' in {path}")

    n_layers = len(spec["kernel_sizes"])
    if len(spec["dilations"]) != n_layers or len(spec["strides"]) != n_layers:
        raise ValueError("kernel_sizes/dilations/strides must have the same length")
    if len(spec["channel_sizes"]) != n_layers + 1:
        raise ValueError("channel_sizes must contain input size plus one entry per layer output")
    if len(spec["weights"]) != n_layers:
        raise ValueError("weights must contain one 3D tensor per layer")

    for layer_idx, layer in enumerate(spec["weights"]):
        c_out = spec["channel_sizes"][layer_idx + 1]
        c_in = spec["channel_sizes"][layer_idx]
        ksz = spec["kernel_sizes"][layer_idx]
        if len(layer) != c_out:
            raise ValueError(f"Layer {layer_idx} expected {c_out} output channels, got {len(layer)}")
        for co, channel_weights in enumerate(layer):
            if len(channel_weights) != c_in:
                raise ValueError(
                    f"Layer {layer_idx} output {co} expected {c_in} input channels, got {len(channel_weights)}"
                )
            for ci, taps in enumerate(channel_weights):
                if len(taps) != ksz:
                    raise ValueError(
                        f"Layer {layer_idx} output {co} input {ci} expected {ksz} taps, got {len(taps)}"
                    )

    spec.setdefault("latency", n_layers)
    return spec


def format_sv_signed(value: int, width: int) -> str:
    if value < 0:
        return f"-{width}'sd{abs(value)}"
    return f"{width}'sd{value}"


def emit_case_function(name: str, values: Iterable[int]) -> str:
    lines = [f"function automatic int {name}(int idx);", "  case (idx)"]
    for idx, value in enumerate(values):
        lines.append(f"    {idx}: return {value};")
    lines.extend(["    default: return 0;", "  endcase", "endfunction", ""])
    return "\n".join(lines)


def emit_sv_package(spec: dict) -> str:
    data_width = spec["data_width"]
    n_layers = len(spec["kernel_sizes"])
    max_ch = max(spec["channel_sizes"])

    lines = [
        "package tcn_cfg_pkg;",
        "",
        f"localparam int TCN_N_CTX = {spec['n_ctx']};",
        f"localparam int TCN_LAYERS = {n_layers};",
        f"localparam int TCN_DATA_WIDTH = {data_width};",
        f"localparam int TCN_FRAC_BITS = {spec['frac_bits']};",
        f"localparam int TCN_KERNEL_SIZE = {max(spec['kernel_sizes'])};",
        f"localparam int TCN_MAX_CH = {max_ch};",
        f"localparam int TCN_LATENCY = {spec['latency']};",
        "",
        emit_case_function("get_kernel_size", spec["kernel_sizes"]),
        emit_case_function("get_dilation", spec["dilations"]),
        emit_case_function("get_stride", spec["strides"]),
        emit_case_function("get_channel_size", spec["channel_sizes"]),
        (
            "function automatic logic signed [TCN_DATA_WIDTH-1:0] get_weight(\n"
            "  int l,\n"
            "  int co,\n"
            "  int ci,\n"
            "  int k\n"
            ");\n"
            "  logic signed [TCN_DATA_WIDTH-1:0] w;\n"
            "  begin\n"
            "    w = '0;\n\n"
            "    case (l)"
        ),
    ]

    for layer_idx, layer in enumerate(spec["weights"]):
        lines.append(f"      {layer_idx}: begin")
        emitted_any = False
        for co, channel_weights in enumerate(layer):
            for ci, taps in enumerate(channel_weights):
                for k, weight in enumerate(taps):
                    if weight == 0:
                        continue
                    prefix = "        if" if not emitted_any else "        else if"
                    lines.append(
                        f"{prefix} ((co == {co}) && (ci == {ci}) && (k == {k})) "
                        f"w = {format_sv_signed(weight, data_width)};"
                    )
                    emitted_any = True
        if not emitted_any:
            lines.append("        w = '0;")
        else:
            lines.append("        else w = '0;")
        lines.append("      end")
        lines.append("")

    lines.extend(
        [
            "      default: w = '0;",
            "    endcase",
            "",
            "    return w;",
            "  end",
            "endfunction",
            "",
            "endpackage",
            "",
        ]
    )

    return "\n".join(lines)


def saturate(value: int, data_width: int) -> int:
    minimum = -(1 << (data_width - 1))
    maximum = (1 << (data_width - 1)) - 1
    return max(minimum, min(maximum, value))


def relu(value: int) -> int:
    return 0 if value < 0 else value


def simulate_events(spec: dict, events: list[tuple[int, int]], threshold: int) -> list[dict]:
    n_layers = len(spec["kernel_sizes"])
    histories: list[list[list[list[int]]]] = []

    for layer_idx in range(n_layers):
        c_in = spec["channel_sizes"][layer_idx]
        hist_len = max(spec["kernel_sizes"][layer_idx] - 1, 1)
        histories.append(
            [[[0 for _ in range(hist_len)] for _ in range(c_in)] for _ in range(spec["n_ctx"])]
        )

    results = []
    for index, (ctx, sample) in enumerate(events):
        if ctx < 0 or ctx >= spec["n_ctx"]:
            raise ValueError(f"Stimulus row {index} uses ctx={ctx}, outside valid range 0..{spec['n_ctx'] - 1}")

        features = [saturate(sample, spec["data_width"])]
        for layer_idx in range(n_layers):
            c_in = spec["channel_sizes"][layer_idx]
            c_out = spec["channel_sizes"][layer_idx + 1]
            ksz = spec["kernel_sizes"][layer_idx]
            frac_bits = spec["frac_bits"]
            history = histories[layer_idx][ctx]
            next_features = []

            for co in range(c_out):
                acc = 0
                for ci in range(c_in):
                    for k in range(ksz):
                        tap_value = features[ci] if k == 0 else history[ci][k - 1]
                        acc += tap_value * spec["weights"][layer_idx][co][ci][k]

                if frac_bits > 0:
                    acc = (acc + (1 << (frac_bits - 1))) >> frac_bits
                next_features.append(relu(saturate(acc, spec["data_width"])))

            if ksz > 1:
                for ci in range(c_in):
                    history[ci] = [features[ci]] + history[ci][:ksz - 2]

            features = next_features

        score = features[0]
        results.append(
            {
                "index": index,
                "ctx": ctx,
                "sample": sample,
                "score": score,
                "bit": int(score > threshold),
            }
        )

    return results


def load_stimulus(path: Path) -> list[tuple[int, int]]:
    rows = []
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError(f"{path} is empty")
        if "ctx" not in reader.fieldnames or "sample" not in reader.fieldnames:
            raise ValueError(f"{path} must contain 'ctx' and 'sample' columns")
        for row in reader:
            rows.append((int(row["ctx"]), int(row["sample"])))
    return rows


def write_reference_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["index", "ctx", "sample", "score", "bit"])
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    args = parse_args()
    spec = load_spec(args.spec)

    if args.command == "emit-sv":
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(emit_sv_package(spec))
        print(f"[emit-sv] Wrote {args.out}")
        return

    if args.command == "run-ref":
        events = load_stimulus(args.stim)
        rows = simulate_events(spec, events, args.threshold)
        write_reference_csv(args.out, rows)
        print(f"[run-ref] Processed {len(events)} events from {args.stim}")
        print(f"[run-ref] Wrote {args.out}")
        return

    raise RuntimeError(f"Unsupported command {args.command}")


if __name__ == "__main__":
    main()
