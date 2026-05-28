"""Close the flywheel: build a CLEANED training set from human labels.

The v2 retrain path. Two realities drive the design:
  - The original 0.954 classifier trained on 5,493 HEURISTIC labels (circular).
  - A human session yields ~150-300 ground-truth labels — too few to train a
    fresh MLP from scratch, but enough to CORRECT the heuristic's systematic
    errors and MEASURE accuracy.

So the default ("clean") mode merges: heuristic labels, with HUMAN labels
overriding wherever they exist (human wins; human-vs-heuristic disagreements are
the corrected errors — the whole point of the flywheel). As human labels
accumulate, `--strict` switches to human-ONLY training.

Outputs `annotations_cleaned.jsonl` and prints the exact retrain command.
Retrain reads it via:  HAWKEYE_ANN_PATH=<cleaned> python -m hawkeye.train.winner_classifier

Usage:
    python -m hawkeye.train.build_training_set            # cleaned merge (heuristic + human overrides)
    python -m hawkeye.train.build_training_set --strict   # human labels only
    python -m hawkeye.train.build_training_set --report   # stats only, write nothing
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Optional

REPO_ROOT = Path(__file__).resolve().parents[3]
HEURISTIC_ANN = REPO_ROOT / "data" / "processed" / "annotations_heuristic_v1.jsonl"
HUMAN_ANN = REPO_ROOT / "data" / "processed" / "annotations.jsonl"
HUMAN_HOLDOUT = REPO_ROOT / "data" / "processed" / "annotations_human_holdout.jsonl"
CLEANED_OUT = REPO_ROOT / "data" / "processed" / "annotations_cleaned.jsonl"


def _is_not_rally(rec: dict) -> bool:
    """A non-play row (warm-up/junk) marked by the labeler's N key.

    Stored but segregated: never a sideA/sideB winner, never trained or evaluated.
    """
    return (rec.get("not_rally") is True
            or rec.get("winner") == "not_rally"
            or rec.get("split") == "not_rally")


def _load(path: Path) -> dict[tuple[str, int], str]:
    out: dict[tuple[str, int], str] = {}
    if not path.exists():
        return out
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except Exception:
            continue
        if _is_not_rally(rec):
            continue  # EXCLUDE from the trainable winner set (segregated below)
        if rec.get("winner") in ("sideA", "sideB"):
            out[(rec["video"], int(rec["rally_id"]))] = rec["winner"]
    return out


def _load_not_rally(path: Path) -> set[tuple[str, int]]:
    """Segregated not_rally rows kept for a future rally-vs-not-rally filter."""
    out: set[tuple[str, int]] = set()
    if not path.exists():
        return out
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except Exception:
            continue
        if _is_not_rally(rec):
            out.add((rec["video"], int(rec["rally_id"])))
    return out


def build(strict: bool) -> tuple[dict[tuple[str, int], str], dict]:
    heuristic = _load(HEURISTIC_ANN)
    human = {**_load(HUMAN_ANN), **_load(HUMAN_HOLDOUT)}

    # Segregated (stored, never trained) — for a future rally-vs-not-rally filter.
    not_rally = (_load_not_rally(HUMAN_ANN) | _load_not_rally(HUMAN_HOLDOUT)
                 | _load_not_rally(HEURISTIC_ANN))

    corrections = sum(1 for k, v in human.items() if k in heuristic and heuristic[k] != v)
    new_from_human = sum(1 for k in human if k not in heuristic)

    if strict:
        merged = dict(human)
    else:
        merged = dict(heuristic)
        merged.update(human)  # human overrides heuristic

    stats = {
        "heuristic": len(heuristic),
        "human": len(human),
        "human_corrections_of_heuristic": corrections,
        "human_new": new_from_human,
        "not_rally_excluded": len(not_rally),  # stored & segregated, NOT trained
        "output_total": len(merged),
        "mode": "strict (human-only)" if strict else "cleaned (heuristic + human overrides)",
    }
    # Invariant: the trainable set is winners only — never any not_rally row.
    assert not (set(merged) & not_rally), "not_rally leaked into trainable set"
    return merged, stats


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--strict", action="store_true", help="human labels ONLY (use once labels are plentiful)")
    ap.add_argument("--report", action="store_true", help="print stats, write nothing")
    args = ap.parse_args()

    merged, stats = build(args.strict)
    print("=" * 60)
    print("  TRAINING SET BUILDER — flywheel retrain prep")
    print("=" * 60)
    for k, v in stats.items():
        print(f"  {k}: {v}")
    if stats["human"] == 0:
        print("  ⚠️  no human labels yet → 'cleaned' == heuristic (no improvement).")
        print("      Run the labeling session first: python -m hawkeye.annotate.holdout_label --n 200")
    print("=" * 60)

    if args.report:
        return 0
    if stats["human"] == 0 and not args.strict:
        print("[build] skipping write — nothing to clean until human labels exist.")
        return 0

    CLEANED_OUT.parent.mkdir(parents=True, exist_ok=True)
    with CLEANED_OUT.open("w") as f:
        for (vid, rid), winner in sorted(merged.items()):
            f.write(json.dumps({"video": vid, "rally_id": rid, "winner": winner,
                                "annotator": "cleaned_v2"}) + "\n")
    print(f"[build] wrote {len(merged)} labels → {CLEANED_OUT}")
    print(f"[build] retrain now:  HAWKEYE_ANN_PATH={CLEANED_OUT} \\")
    print(f"                      PYTHONPATH=src ./.venv/bin/python -m hawkeye.train.winner_classifier")
    print(f"[build] then measure: PYTHONPATH=src ./.venv/bin/python -m hawkeye.train.holdout_eval")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
