"""Measure System-2's REAL accuracy against a human ground-truth holdout.

Run this AFTER `python -m hawkeye.annotate.holdout_label` has collected labels.
It loads the trained RallyWinnerClassifier.mlpackage, predicts the winner for
each human-labeled rally, and reports:
  - System-2 (classifier) accuracy vs human truth   <- the number we actually want
  - heuristic auto_annotate (mean_x<0.5) accuracy vs human truth   <- the baseline
  - classifier-vs-heuristic agreement on this set    <- confirms (or refutes) the
    "0.954 is circular" finding: if agreement is ~95% but accuracy-vs-human is much
    lower, the classifier learned the heuristic's bias rather than truth.

Usage:
    python -m hawkeye.train.holdout_eval
    python -m hawkeye.train.holdout_eval --labels data/processed/annotations_human_holdout.jsonl
"""
from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

import numpy as np

from .winner_classifier import featurize, FEATURE_DIM

REPO_ROOT = Path(__file__).resolve().parents[3]
TRAJ_DIR = REPO_ROOT / "data" / "processed" / "trajectories"
MODEL_PATH = REPO_ROOT / "data" / "processed" / "RallyWinnerClassifier.mlpackage"
HOLDOUT_PATH = REPO_ROOT / "data" / "processed" / "annotations_human_holdout.jsonl"


def _heuristic_winner(trajectory: list[dict]) -> str | None:
    """Mirror auto_annotate: mean_x of last 3-5 visible points < 0.5 -> sideA."""
    vis = [p for p in trajectory if p.get("vis", True)]
    if len(vis) < 3:
        return None
    last = vis[-5:]
    mean_x = sum(float(p["x"]) for p in last) / len(last)
    return "sideA" if mean_x < 0.5 else "sideB"


def _load_labels(path: Path) -> dict[tuple[str, int], str]:
    out: dict[tuple[str, int], str] = {}
    n_not_rally = 0
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        rec = json.loads(line)
        # EXCLUDE not_rally rows from accuracy eval: non-play footage has no
        # sideA/sideB truth and must never count toward (or against) accuracy.
        if rec.get("not_rally") is True or rec.get("winner") == "not_rally" \
                or rec.get("split") == "not_rally":
            n_not_rally += 1
            continue
        if rec.get("winner") in ("sideA", "sideB"):
            out[(rec["video"], int(rec["rally_id"]))] = rec["winner"]
    if n_not_rally:
        print(f"[eval] excluded {n_not_rally} not_rally rows from accuracy eval")
    return out


def _index_trajectories() -> dict[tuple[str, int], list[dict]]:
    idx: dict[tuple[str, int], list[dict]] = {}
    for jp in sorted(TRAJ_DIR.glob("*.json")):
        data = json.loads(jp.read_text())
        vid = data["video"]
        for rally in data.get("rallies", []):
            idx[(vid, int(rally["rally_id"]))] = rally["trajectory"]
    return idx


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--labels", default=str(HOLDOUT_PATH),
                    help="ground-truth labels jsonl (default: the human holdout)")
    args = ap.parse_args()

    labels_path = Path(args.labels)
    if not labels_path.exists() or labels_path.stat().st_size == 0:
        print(f"[eval] no labels at {labels_path}.")
        print("       Collect them first:  python -m hawkeye.annotate.holdout_label --n 200")
        return 2
    if not MODEL_PATH.exists():
        print(f"[eval] model not found at {MODEL_PATH}"); return 2

    labels = _load_labels(labels_path)
    traj = _index_trajectories()
    import coremltools as ct
    model = ct.models.MLModel(str(MODEL_PATH))

    n = clf_correct = heur_correct = clf_vs_heur = both = 0
    conf = Counter()  # (truth, pred) for classifier
    for (vid, rid), truth in labels.items():
        t = traj.get((vid, rid))
        if t is None:
            continue
        feats = featurize(t).astype(np.float32).reshape(1, FEATURE_DIM)
        out = model.predict({"trajectory_features": feats})
        logits = np.asarray(next(iter(out.values()))).reshape(-1)
        clf = "sideA" if int(np.argmax(logits)) == 0 else "sideB"
        heur = _heuristic_winner(t)
        n += 1
        clf_correct += (clf == truth)
        conf[(truth, clf)] += 1
        if heur is not None:
            both += 1
            heur_correct += (heur == truth)
            clf_vs_heur += (clf == heur)

    if n == 0:
        print("[eval] no holdout rallies matched a trajectory."); return 2

    print("=" * 60)
    print(f"  GROUND-TRUTH HOLDOUT EVAL  (n={n} human-labeled rallies)")
    print("=" * 60)
    print(f"  System-2 (classifier) accuracy vs human:  {clf_correct/n:.1%}  <- REAL accuracy")
    if both:
        print(f"  heuristic (mean_x<0.5) accuracy vs human: {heur_correct/both:.1%}  (baseline)")
        print(f"  classifier-vs-heuristic agreement:        {clf_vs_heur/both:.1%}")
        print(f"    (if agreement >> accuracy → classifier learned the heuristic's bias, not truth)")
    print(f"  confusion (truth→pred): "
          f"A→A {conf[('sideA','sideA')]}  A→B {conf[('sideA','sideB')]}  "
          f"B→A {conf[('sideB','sideA')]}  B→B {conf[('sideB','sideB')]}")
    print("=" * 60)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
