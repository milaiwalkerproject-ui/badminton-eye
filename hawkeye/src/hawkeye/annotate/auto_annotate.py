"""Heuristic auto-annotator for rally winners.

For each trajectory JSON in data/processed/trajectories/:
- For each rally, look at the last 3-5 visible (x,y) points before the rally
  ends and project them onto the canonical side axis (hawkeye.orientation):
  side_on (default) uses image-X (mean_x < 0.5 -> sideA = left), end_on uses
  1 - image-Y (sideA = near/bottom). If we don't have enough visible points or
  the last point looks like a tracking jump, we record "skip" so the human
  annotator (bin/annotate.sh) can revisit it.

Output: appended lines to data/processed/annotations.jsonl, one per rally.
Idempotent on (video, rally_id) — re-running won't duplicate heuristic
entries, and human-annotated rallies are never overwritten.

Usage:
    python -m hawkeye.annotate.auto_annotate [--force] [--trajectories DIR]
                                             [--out FILE]
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from ..orientation import (
    SIDE_ON, load_orientation_map, resolve_orientation,
    tail_side_mean, winner_from_side_axis,
)

ANNOTATOR_ID = "heuristic_v1"
DEFAULT_TRAJ_DIR = Path("data/processed/trajectories")
DEFAULT_OUT = Path("data/processed/annotations.jsonl")
JUMP_THRESHOLD = 0.25  # normalized distance — tracking error filter
TAIL_POINTS = 5
MIN_POINTS = 2


def _iter_visible(rally: dict) -> Iterable[dict]:
    for p in rally.get("trajectory", []):
        if p.get("vis") and p.get("x") is not None and p.get("y") is not None:
            yield p


def classify_rally(rally: dict, orientation: str = SIDE_ON) -> tuple[str, dict]:
    """Return (winner, evidence). winner ∈ {sideA, sideB, skip}.

    Side decision goes through the shared canonical-side-axis helper
    (hawkeye.orientation) — side_on is the historical mean_x<0.5 rule.
    """
    visible = list(_iter_visible(rally))
    if len(visible) < MIN_POINTS:
        return "skip", {
            "reason": "insufficient_visible_points",
            "n_points_used": len(visible),
        }

    tail = visible[-TAIL_POINTS:]
    if len(tail) >= 2:
        a, b = tail[-2], tail[-1]
        dist = math.hypot(b["x"] - a["x"], b["y"] - a["y"])  # raw image coords
        if dist > JUMP_THRESHOLD:
            return "skip", {
                "reason": "tracking_jump",
                "jump_distance": round(dist, 4),
                "n_points_used": len(tail),
            }

    mean_side, _ = tail_side_mean(tail, orientation, tail=TAIL_POINTS)
    mean_x = sum(p["x"] for p in tail) / len(tail)
    mean_y = sum(p["y"] for p in tail) / len(tail)
    winner = winner_from_side_axis(mean_side)
    return winner, {
        "mean_x": round(mean_x, 4),
        "mean_y": round(mean_y, 4),
        "mean_side": round(mean_side, 4),
        "orientation": orientation,
        "n_points_used": len(tail),
    }


def _load_existing(out_path: Path) -> dict[tuple[str, int], dict]:
    """Map (video, rally_id) -> existing annotation dict."""
    existing: dict[tuple[str, int], dict] = {}
    if not out_path.exists():
        return existing
    with out_path.open("r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            video = row.get("video")
            rid = row.get("rally_id")
            if video is None or rid is None:
                continue
            existing[(video, int(rid))] = row
    return existing


def _iter_trajectory_files(traj_dir: Path) -> list[Path]:
    if not traj_dir.exists():
        return []
    return sorted(p for p in traj_dir.iterdir() if p.suffix == ".json")


def run(traj_dir: Path, out_path: Path, force: bool) -> dict:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    existing = _load_existing(out_path)
    written = 0
    skipped_human = 0
    skipped_existing = 0
    counter: Counter[str] = Counter()
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")

    files = _iter_trajectory_files(traj_dir)
    if not files:
        print(f"[auto_annotate] no trajectory files in {traj_dir}", file=sys.stderr)

    sidecar = load_orientation_map()
    with out_path.open("a", encoding="utf-8") as out_fh:
        for traj_file in files:
            try:
                data = json.loads(traj_file.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as exc:
                print(f"[auto_annotate] skipping {traj_file}: {exc}", file=sys.stderr)
                continue
            video = data.get("video") or traj_file.stem
            orientation = resolve_orientation(video, traj_payload=data, sidecar=sidecar)
            rallies = data.get("rallies", [])
            for rally in rallies:
                rid = int(rally.get("rally_id", -1))
                if rid < 0:
                    continue
                key = (video, rid)
                if key in existing:
                    prior = existing[key]
                    if prior.get("annotator") != ANNOTATOR_ID:
                        skipped_human += 1
                        continue
                    if not force:
                        skipped_existing += 1
                        continue
                winner, evidence = classify_rally(rally, orientation)
                row = {
                    "video": video,
                    "rally_id": rid,
                    "winner": winner,
                    "orientation": orientation,
                    "annotator": ANNOTATOR_ID,
                    "timestamp": now,
                    "evidence": evidence,
                }
                out_fh.write(json.dumps(row) + "\n")
                existing[key] = row
                written += 1
                counter[winner] += 1

    summary = {
        "written": written,
        "skipped_human": skipped_human,
        "skipped_existing": skipped_existing,
        "distribution": dict(counter),
    }
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--trajectories",
        type=Path,
        default=DEFAULT_TRAJ_DIR,
        help="Directory of trajectory JSON files (default: %(default)s)",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=DEFAULT_OUT,
        help="Annotations JSONL file (default: %(default)s)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-annotate even rallies already labeled by heuristic_v1",
    )
    args = parser.parse_args(argv)

    summary = run(args.trajectories, args.out, args.force)
    print(
        "[auto_annotate] wrote={written} skipped_existing={skipped_existing} "
        "skipped_human={skipped_human} dist={distribution}".format(**summary)
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
