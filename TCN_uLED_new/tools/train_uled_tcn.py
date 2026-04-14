#!/usr/bin/env python3
"""Train a small causal TCN for the 2-channel uLED restoration prototype.

Expected CSV columns:
  ctx,sample,target

Optional columns:
  split   : train / val / test
  time    : sortable per-context timestamp

The script groups rows by context, preserves temporal order within each
context, and trains a causal TCN whose shape is intended to match the current
RTL-friendly prototype: no residual path, ReLU after every layer, stride=1,
and dilation defaults to 1.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from collections import defaultdict
from pathlib import Path

import numpy as np

try:
    import torch
    import torch.nn as nn
    import torch.nn.functional as F
except ImportError:  # pragma: no cover - runtime guard for missing dependency
    torch = None
    nn = None
    F = None


def require_torch() -> None:
    if torch is None:
        raise SystemExit(
            "PyTorch is required for training but is not installed in this environment.\n"
            "Install the repo's recommended environment first, then rerun this script."
        )


def parse_int_list(text: str) -> list[int]:
    return [int(part.strip()) for part in text.split(",") if part.strip()]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv", type=Path, required=True, help="Training CSV with ctx,sample,target columns")
    parser.add_argument("--outdir", type=Path, required=True, help="Directory for checkpoints and metrics")
    parser.add_argument("--n-ctx", type=int, default=2, help="Number of logical TDM contexts")
    parser.add_argument("--kernel-sizes", default="4,4", help="Comma-separated kernel sizes")
    parser.add_argument("--channel-sizes", default="1,4,1", help="Comma-separated channel sizes")
    parser.add_argument("--dilations", default="1,1", help="Comma-separated dilations")
    parser.add_argument("--epochs", type=int, default=200, help="Training epochs")
    parser.add_argument("--lr", type=float, default=1e-2, help="Adam learning rate")
    parser.add_argument("--seed", type=int, default=7, help="Random seed")
    parser.add_argument("--val-fraction", type=float, default=0.2, help="Per-context tail fraction for validation if split column is absent")
    parser.add_argument("--sample-scale", type=float, default=1.0, help="Divide samples by this value before training")
    parser.add_argument("--target-scale", type=float, default=1.0, help="Divide targets by this value before training")
    parser.add_argument("--center-input-u8", action="store_true", help="Subtract 128 from input samples before scaling")
    parser.add_argument("--data-width", type=int, default=8, help="Target fixed-point data width for later export")
    parser.add_argument("--frac-bits", type=int, default=4, help="Target fixed-point fractional bits for later export")
    return parser.parse_args()


def receptive_field(kernel_sizes: list[int], dilations: list[int]) -> int:
    field = 1
    for ksz, dil in zip(kernel_sizes, dilations):
        field += (ksz - 1) * dil
    return field


def load_rows(path: Path) -> list[dict]:
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise ValueError(f"{path} is empty")

        required = {"ctx", "sample", "target"}
        missing = required - set(reader.fieldnames)
        if missing:
            raise ValueError(f"{path} is missing required columns: {sorted(missing)}")

        rows = []
        for order_idx, row in enumerate(reader):
            rows.append(
                {
                    "ctx": int(row["ctx"]),
                    "sample": float(row["sample"]),
                    "target": float(row["target"]),
                    "split": (row.get("split") or "").strip().lower(),
                    "time": float(row["time"]) if row.get("time") not in (None, "") else None,
                    "order": order_idx,
                }
            )
    return rows


def group_sequences(
    rows: list[dict],
    n_ctx: int,
    val_fraction: float,
    sample_scale: float,
    target_scale: float,
    center_input_u8: bool,
) -> tuple[dict[str, list[tuple[np.ndarray, np.ndarray]]], dict]:
    split_buckets: dict[str, dict[int, list[dict]]] = {
        "train": defaultdict(list),
        "val": defaultdict(list),
        "test": defaultdict(list),
    }

    has_explicit_split = any(row["split"] for row in rows)

    for row in rows:
        ctx = row["ctx"]
        if ctx < 0 or ctx >= n_ctx:
            raise ValueError(f"Row with ctx={ctx} falls outside valid range 0..{n_ctx - 1}")

        key = row["split"] if row["split"] in split_buckets else ""
        if has_explicit_split and key == "":
            raise ValueError("When any row uses split, every row must use train/val/test")

        bucket = key if has_explicit_split else "train"
        split_buckets[bucket][ctx].append(row)

    if not has_explicit_split:
        for ctx in range(n_ctx):
            seq_rows = split_buckets["train"][ctx]
            seq_rows.sort(key=lambda item: (item["time"] is None, item["time"], item["order"]))
            if not seq_rows:
                continue
            cut = max(1, int(math.floor(len(seq_rows) * (1.0 - val_fraction))))
            cut = min(cut, len(seq_rows))
            split_buckets["train"][ctx] = seq_rows[:cut]
            split_buckets["val"][ctx] = seq_rows[cut:]

    sequences: dict[str, list[tuple[np.ndarray, np.ndarray]]] = {"train": [], "val": [], "test": []}
    counts = {"train_rows": 0, "val_rows": 0, "test_rows": 0}

    for split_name, per_ctx in split_buckets.items():
        for ctx in range(n_ctx):
            seq_rows = list(per_ctx[ctx])
            seq_rows.sort(key=lambda item: (item["time"] is None, item["time"], item["order"]))
            if not seq_rows:
                continue

            samples = np.array([row["sample"] for row in seq_rows], dtype=np.float32)
            targets = np.array([row["target"] for row in seq_rows], dtype=np.float32)
            if center_input_u8:
                samples = samples - 128.0
            samples = samples / sample_scale
            targets = targets / target_scale
            sequences[split_name].append((samples, targets))
            counts[f"{split_name}_rows"] += len(seq_rows)

    if not sequences["train"]:
        raise ValueError("No training sequences found in the CSV")

    return sequences, counts


if torch is not None:
    class CausalConvBlock(nn.Module):
        def __init__(self, c_in: int, c_out: int, kernel_size: int, dilation: int) -> None:
            super().__init__()
            self.pad = (kernel_size - 1) * dilation
            self.conv = nn.Conv1d(
                in_channels=c_in,
                out_channels=c_out,
                kernel_size=kernel_size,
                stride=1,
                dilation=dilation,
                bias=False,
            )

        def forward(self, x: torch.Tensor) -> torch.Tensor:
            x = F.pad(x, (self.pad, 0))
            x = self.conv(x)
            return F.relu(x)


    class TinyCausalTcn(nn.Module):
        def __init__(self, channel_sizes: list[int], kernel_sizes: list[int], dilations: list[int]) -> None:
            super().__init__()
            layers = []
            for idx, (ksz, dil) in enumerate(zip(kernel_sizes, dilations)):
                layers.append(
                    CausalConvBlock(
                        c_in=channel_sizes[idx],
                        c_out=channel_sizes[idx + 1],
                        kernel_size=ksz,
                        dilation=dil,
                    )
                )
            self.layers = nn.ModuleList(layers)

        def forward(self, x: torch.Tensor) -> torch.Tensor:
            for layer in self.layers:
                x = layer(x)
            return x
else:
    class CausalConvBlock:  # pragma: no cover - placeholder when torch is unavailable
        pass


    class TinyCausalTcn:  # pragma: no cover - placeholder when torch is unavailable
        pass


def sequence_tensor(values: np.ndarray, device: torch.device) -> torch.Tensor:
    return torch.tensor(values, dtype=torch.float32, device=device).view(1, 1, -1)


def evaluate(model: TinyCausalTcn, sequences: list[tuple[np.ndarray, np.ndarray]], device: torch.device) -> float:
    model.eval()
    if not sequences:
        return float("nan")

    total_loss = 0.0
    total_points = 0
    with torch.no_grad():
        for samples, targets in sequences:
            x = sequence_tensor(samples, device)
            y = sequence_tensor(targets, device)
            pred = model(x)
            total_loss += F.mse_loss(pred, y, reduction="sum").item()
            total_points += targets.size
    return total_loss / max(total_points, 1)


def train_model(args: argparse.Namespace) -> None:
    require_torch()

    torch.manual_seed(args.seed)
    np.random.seed(args.seed)

    kernel_sizes = parse_int_list(args.kernel_sizes)
    channel_sizes = parse_int_list(args.channel_sizes)
    dilations = parse_int_list(args.dilations)

    if len(channel_sizes) != len(kernel_sizes) + 1:
        raise ValueError("channel_sizes must provide one more entry than kernel_sizes")
    if len(dilations) != len(kernel_sizes):
        raise ValueError("dilations must match kernel_sizes length")
    if channel_sizes[0] != 1 or channel_sizes[-1] != 1:
        raise ValueError("Current training scaffold assumes 1 input channel and 1 output channel")

    rows = load_rows(args.csv)
    sequences, counts = group_sequences(
        rows=rows,
        n_ctx=args.n_ctx,
        val_fraction=args.val_fraction,
        sample_scale=args.sample_scale,
        target_scale=args.target_scale,
        center_input_u8=args.center_input_u8,
    )

    device = torch.device("cpu")
    model = TinyCausalTcn(channel_sizes, kernel_sizes, dilations).to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)

    history = []
    best_state = None
    best_val = float("inf")
    best_epoch = -1

    for epoch in range(1, args.epochs + 1):
        model.train()
        total_loss = 0.0
        total_points = 0

        for samples, targets in sequences["train"]:
            x = sequence_tensor(samples, device)
            y = sequence_tensor(targets, device)

            optimizer.zero_grad(set_to_none=True)
            pred = model(x)
            loss = F.mse_loss(pred, y)
            loss.backward()
            optimizer.step()

            total_loss += loss.item() * targets.size
            total_points += targets.size

        train_loss = total_loss / max(total_points, 1)
        val_loss = evaluate(model, sequences["val"], device)
        history.append({"epoch": epoch, "train_mse": train_loss, "val_mse": val_loss})

        score_for_selection = train_loss if math.isnan(val_loss) else val_loss
        if score_for_selection < best_val:
            best_val = score_for_selection
            best_epoch = epoch
            best_state = {key: value.detach().cpu().clone() for key, value in model.state_dict().items()}

        if epoch == 1 or epoch == args.epochs or epoch % max(1, args.epochs // 10) == 0:
            val_text = "nan" if math.isnan(val_loss) else f"{val_loss:.6f}"
            print(f"[train] epoch={epoch:4d} train_mse={train_loss:.6f} val_mse={val_text}")

    if best_state is None:
        raise RuntimeError("Training did not produce a checkpoint")

    model.load_state_dict(best_state)
    final_train = evaluate(model, sequences["train"], device)
    final_val = evaluate(model, sequences["val"], device)
    final_test = evaluate(model, sequences["test"], device)

    args.outdir.mkdir(parents=True, exist_ok=True)

    npz_payload = {
        "kernel_sizes": np.array(kernel_sizes, dtype=np.int32),
        "channel_sizes": np.array(channel_sizes, dtype=np.int32),
        "dilations": np.array(dilations, dtype=np.int32),
        "n_ctx": np.array([args.n_ctx], dtype=np.int32),
        "data_width": np.array([args.data_width], dtype=np.int32),
        "frac_bits": np.array([args.frac_bits], dtype=np.int32),
        "latency": np.array([len(kernel_sizes)], dtype=np.int32),
        "sample_scale": np.array([args.sample_scale], dtype=np.float32),
        "target_scale": np.array([args.target_scale], dtype=np.float32),
        "center_input_u8": np.array([1 if args.center_input_u8 else 0], dtype=np.int32),
    }

    for idx, layer in enumerate(model.layers):
        npz_payload[f"layer{idx}_weight"] = layer.conv.weight.detach().cpu().numpy()

    checkpoint_path = args.outdir / "checkpoint_float.npz"
    np.savez(checkpoint_path, **npz_payload)

    metrics = {
        "best_epoch": best_epoch,
        "best_objective": best_val,
        "final_train_mse": final_train,
        "final_val_mse": final_val,
        "final_test_mse": final_test,
        "rows": counts,
        "receptive_field": receptive_field(kernel_sizes, dilations),
        "kernel_sizes": kernel_sizes,
        "channel_sizes": channel_sizes,
        "dilations": dilations,
        "epochs": args.epochs,
        "lr": args.lr,
        "csv": str(args.csv),
    }
    (args.outdir / "metrics.json").write_text(json.dumps(metrics, indent=2))
    (args.outdir / "history.json").write_text(json.dumps(history, indent=2))

    print(f"[train] wrote checkpoint {checkpoint_path}")
    print(f"[train] wrote metrics   {args.outdir / 'metrics.json'}")


def main() -> None:
    args = parse_args()
    train_model(args)


if __name__ == "__main__":
    main()
