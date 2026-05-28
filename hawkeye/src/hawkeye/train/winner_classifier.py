"""Train a tiny rally-winner classifier from trajectories + annotations.

Inputs:
  data/processed/trajectories/<video>.json     (extract_rallies.py output)
  data/processed/annotations.jsonl              (annotate_rallies.py output)

Output:
  data/processed/RallyWinnerClassifier.mlpackage  (Core ML, FP16, mlprogram, iOS17)
  data/processed/RallyWinnerClassifier_meta.json  (feature schema)

Feature vector (38 floats):
  - 16 evenly-spaced (x, y) trajectory samples         -> 32
  - mean (x, y) of last 3 points                       ->  2
  - final velocity magnitude (||p_n - p_{n-3}|| / dt)  ->  1
  - max y (apex)                                       ->  1
  - trajectory length (sum of segment lengths)         ->  1
  - gap-ratio (1 - visible_count / span_frames)        ->  1

Model: MLP 38 -> 32 -> 16 -> 2, ReLU, ~2k params.

Usage:
    python -m hawkeye.train.winner_classifier [--synthetic] [--out-suffix _smoke]
"""
from __future__ import annotations

import argparse
import json
import math
import random
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

import os

REPO_ROOT = Path(__file__).resolve().parents[3]
TRAJ_DIR = REPO_ROOT / "data" / "processed" / "trajectories"
# Override the label source for flywheel retrains (e.g. the cleaned set from
# build_training_set.py): HAWKEYE_ANN_PATH=<file> python -m hawkeye.train.winner_classifier
ANN_PATH = Path(os.environ["HAWKEYE_ANN_PATH"]) if os.environ.get("HAWKEYE_ANN_PATH") \
    else REPO_ROOT / "data" / "processed" / "annotations.jsonl"
OUT_DIR = REPO_ROOT / "data" / "processed"

NUM_SAMPLES = 16
FEATURE_DIM = NUM_SAMPLES * 2 + 2 + 1 + 1 + 1 + 1  # 38


# ---------- Feature engineering ----------

def featurize(trajectory: list[dict]) -> np.ndarray:
    pts = [(float(p["x"]), float(p["y"]), int(p["f"]), bool(p.get("vis", True))) for p in trajectory]
    pts = [p for p in pts if p[3]]
    if len(pts) < 2:
        return np.zeros(FEATURE_DIM, dtype=np.float32)

    xs = np.array([p[0] for p in pts], dtype=np.float32)
    ys = np.array([p[1] for p in pts], dtype=np.float32)
    fs = np.array([p[2] for p in pts], dtype=np.float32)

    # Evenly-spaced 16 samples via linear interpolation along time index.
    idx = np.linspace(0, len(pts) - 1, num=NUM_SAMPLES)
    lo = np.floor(idx).astype(int); hi = np.minimum(lo + 1, len(pts) - 1)
    frac = idx - lo
    sx = xs[lo] * (1 - frac) + xs[hi] * frac
    sy = ys[lo] * (1 - frac) + ys[hi] * frac
    samples = np.stack([sx, sy], axis=1).reshape(-1)  # 32

    last3 = pts[-3:]
    mean_last_x = float(np.mean([p[0] for p in last3]))
    mean_last_y = float(np.mean([p[1] for p in last3]))

    if len(pts) >= 4:
        dx = pts[-1][0] - pts[-4][0]
        dy = pts[-1][1] - pts[-4][1]
        df = max(1.0, pts[-1][2] - pts[-4][2])
        final_v = math.hypot(dx, dy) / df
    else:
        final_v = 0.0

    apex_y = float(ys.min())  # image coord: lower y == higher apex
    seg = np.hypot(np.diff(xs), np.diff(ys)).sum()
    length = float(seg)

    span = max(1.0, float(fs[-1] - fs[0]))
    gap_ratio = float(1.0 - (len(pts) / (span + 1.0)))

    extras = np.array([mean_last_x, mean_last_y, final_v, apex_y, length, gap_ratio],
                      dtype=np.float32)
    return np.concatenate([samples, extras]).astype(np.float32)


# ---------- Dataset loading ----------

def load_dataset() -> tuple[np.ndarray, np.ndarray]:
    if not ANN_PATH.exists():
        return np.zeros((0, FEATURE_DIM), dtype=np.float32), np.zeros((0,), dtype=np.int64)
    anns: dict[tuple[str, int], str] = {}
    n_not_rally = 0
    for line in ANN_PATH.read_text().splitlines():
        line = line.strip()
        if not line: continue
        rec = json.loads(line)
        # EXCLUDE not_rally rows from winner training: non-play footage must never
        # be coerced into a sideA/sideB label. The (sideA, sideB) gate already
        # drops them; count them explicitly so the exclusion is intentional.
        if rec.get("not_rally") is True or rec.get("winner") == "not_rally" \
                or rec.get("split") == "not_rally":
            n_not_rally += 1
            continue
        if rec.get("winner") in ("sideA", "sideB"):
            anns[(rec["video"], int(rec["rally_id"]))] = rec["winner"]
    if n_not_rally:
        print(f"[train] excluded {n_not_rally} not_rally rows from training set")

    X, y = [], []
    for jp in sorted(TRAJ_DIR.glob("*.json")):
        data = json.loads(jp.read_text())
        vid = data["video"]
        for rally in data.get("rallies", []):
            key = (vid, int(rally["rally_id"]))
            if key not in anns: continue
            X.append(featurize(rally["trajectory"]))
            y.append(0 if anns[key] == "sideA" else 1)
    if not X:
        return np.zeros((0, FEATURE_DIM), dtype=np.float32), np.zeros((0,), dtype=np.int64)
    return np.stack(X), np.array(y, dtype=np.int64)


def synthetic_dataset(n: int = 50, seed: int = 0) -> tuple[np.ndarray, np.ndarray]:
    rng = np.random.default_rng(seed)
    X, y = [], []
    for _ in range(n):
        label = int(rng.integers(0, 2))
        # sideA winners: trajectory ends on right (x large); sideB: ends left.
        # Add noise so it's not trivially separable.
        end_x = 0.7 + rng.normal(0, 0.1) if label == 0 else 0.3 + rng.normal(0, 0.1)
        traj = []
        npts = int(rng.integers(20, 60))
        start_x = 1 - end_x
        for i in range(npts):
            t = i / (npts - 1)
            x = start_x * (1 - t) + end_x * t + rng.normal(0, 0.02)
            y_p = 0.5 - 0.4 * math.sin(math.pi * t) + rng.normal(0, 0.02)
            traj.append({"f": i, "x": float(x), "y": float(y_p), "conf": 0.9, "vis": True})
        X.append(featurize(traj)); y.append(label)
    return np.stack(X), np.array(y, dtype=np.int64)


# ---------- Model ----------

class WinnerMLP(nn.Module):
    def __init__(self, in_dim: int = FEATURE_DIM):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(in_dim, 32), nn.ReLU(),
            nn.Linear(32, 16), nn.ReLU(),
            nn.Linear(16, 2),
        )
    def forward(self, x): return self.net(x)


def train(X: np.ndarray, y: np.ndarray, epochs: int = 100, bs: int = 32, seed: int = 0):
    torch.manual_seed(seed); np.random.seed(seed); random.seed(seed)
    n = len(X)
    perm = np.random.permutation(n)
    split = max(1, int(0.8 * n))
    tr, va = perm[:split], perm[split:]
    Xtr = torch.from_numpy(X[tr]).float(); ytr = torch.from_numpy(y[tr]).long()
    Xva = torch.from_numpy(X[va]).float(); yva = torch.from_numpy(y[va]).long()

    model = WinnerMLP()
    n_params = sum(p.numel() for p in model.parameters())
    print(f"[train] params={n_params}, train={len(tr)} val={len(va)}")
    opt = torch.optim.Adam(model.parameters(), lr=1e-3)
    loss_fn = nn.CrossEntropyLoss()

    for ep in range(epochs):
        model.train()
        idx = torch.randperm(len(Xtr))
        total = 0.0
        for i in range(0, len(Xtr), bs):
            b = idx[i:i+bs]
            logits = model(Xtr[b])
            loss = loss_fn(logits, ytr[b])
            opt.zero_grad(); loss.backward(); opt.step()
            total += loss.item() * len(b)
        if (ep + 1) % 20 == 0 or ep == 0:
            model.eval()
            with torch.no_grad():
                tr_acc = (model(Xtr).argmax(1) == ytr).float().mean().item()
                va_acc = (model(Xva).argmax(1) == yva).float().mean().item() if len(va) else float("nan")
            print(f"[train] ep {ep+1:3d}  loss={total/max(1,len(Xtr)):.4f}  tr_acc={tr_acc:.3f}  va_acc={va_acc:.3f}")

    # Final eval + confusion matrix.
    model.eval()
    with torch.no_grad():
        preds = model(Xva).argmax(1).numpy() if len(va) else np.array([])
    if len(va):
        truth = y[va]
        cm = np.zeros((2, 2), dtype=int)
        for t, p in zip(truth, preds):
            cm[t, p] += 1
        acc = float((preds == truth).mean())
        print(f"[train] val acc={acc:.3f}")
        print(f"[train] confusion matrix (rows=truth A/B, cols=pred A/B):\n{cm}")
    return model


# ---------- Core ML export ----------

def export_coreml(model: nn.Module, out_path: Path) -> None:
    import coremltools as ct
    model.eval()
    example = torch.zeros(1, FEATURE_DIM)
    traced = torch.jit.trace(model, example)
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="trajectory_features", shape=(1, FEATURE_DIM), dtype=np.float32)],
        outputs=[ct.TensorType(name="winner_logits", dtype=np.float32)],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
    )
    mlmodel.short_description = "Badminton rally winner classifier (sideA=0, sideB=1)"
    mlmodel.author = "badminton-eye hawkeye pipeline"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        import shutil; shutil.rmtree(out_path)
    mlmodel.save(str(out_path))
    print(f"[export] wrote {out_path}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--synthetic", action="store_true", help="Force synthetic dataset")
    ap.add_argument("--out-suffix", default="", help="Suffix for output mlpackage (e.g. _smoke)")
    ap.add_argument("--epochs", type=int, default=100)
    args = ap.parse_args()

    X, y = load_dataset()
    used_synthetic = False
    if args.synthetic or len(X) < 8:
        print(f"[train] only {len(X)} real samples; using synthetic dataset")
        X, y = synthetic_dataset(50)
        used_synthetic = True

    print(f"[train] dataset: X={X.shape} y={y.shape} class0={(y==0).sum()} class1={(y==1).sum()}")
    model = train(X, y, epochs=args.epochs)

    suffix = args.out_suffix or ("_smoke" if used_synthetic else "")
    out_path = OUT_DIR / f"RallyWinnerClassifier{suffix}.mlpackage"
    export_coreml(model, out_path)

    meta = {
        "feature_dim": FEATURE_DIM,
        "feature_schema": [
            *[f"sample_{i}_{c}" for i in range(NUM_SAMPLES) for c in ("x", "y")],
            "mean_last_x", "mean_last_y", "final_velocity",
            "apex_y", "length", "gap_ratio",
        ],
        "labels": {"0": "sideA", "1": "sideB"},
        "synthetic": used_synthetic,
        "num_samples": int(len(X)),
    }
    (OUT_DIR / f"RallyWinnerClassifier{suffix}_meta.json").write_text(json.dumps(meta, indent=2))
    print(f"[train] meta written; synthetic={used_synthetic}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
