"""Offline F2 eval: rally-winner accuracy of LAST-HIT attribution vs baselines.

Measures, on the human-labeled holdout, how often each method picks the correct
rally winner:
  - last_hit : the FK SideAxisTurningPoint approach — winner = side that made the
               last stroke (turning point of the canonical side axis over time).
               This is the offline mirror of Swift `HitDetector` (it runs on the
               IMAGE-space canonical side axis since YouTube clips have no court
               homography; on-device the Swift version runs on rectified court y).
  - tail_mean: the app's existing heuristic lineage (mean side of the last 5
               visible points; auto_annotate.tail_side_mean).
  - full_mean: a naive whole-trajectory mean-side baseline.

Convention (matches winner_classifier/orientation): canonical side axis < 0.5 ->
sideA, >= 0.5 -> sideB. side_on -> axis = image x; end_on -> axis = 1 - image_y.
A last hit while the shuttle heads toward the HIGH axis (>0) is struck by the
high-side (sideB) player, and vice-versa.

NOTE: this is a measurement tool, not the on-device source of truth. Keep it in
loose parity with Swift `HitDetector`; a golden-fixture parity test (cf.
FeaturizeGoldenTests) is the eventual home for exact agreement.

Usage:
    python -m hawkeye.train.hit_attribution_eval --data-dir <dir with
        trajectories/, annotations_human_holdout.jsonl, orientation.json>
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def side_axis(p: dict, orientation: str) -> float:
    return float(p["x"]) if orientation == "side_on" else (1.0 - float(p["y"]))


def _smooth(ys: list[float], w: int) -> list[float]:
    h = w // 2
    out = []
    for i in range(len(ys)):
        lo, hi = max(0, i - h), min(len(ys) - 1, i + h)
        out.append(sum(ys[lo:hi + 1]) / (hi - lo + 1))
    return out


def last_hit_winner(traj: list[dict], orientation: str, fps: float, eps: float = 0.05) -> str | None:
    pts = [side_axis(p, orientation) for p in traj if p.get("vis", True)]
    if len(pts) < 3:
        return None
    fps = max(24.0, min(240.0, fps or 30.0))
    w = max(3, (round(0.10 * fps) | 1))
    ys = _smooth(pts, w)
    last_dir = 0
    rev_dirs: list[int] = []
    for i in range(len(ys)):
        v = ys[min(i + 1, len(ys) - 1)] - ys[max(i - 1, 0)]
        s = 1 if v > eps else (-1 if v < -eps else 0)
        if s == 0:
            continue
        if last_dir != 0 and s != last_dir:
            rev_dirs.append(last_dir)   # direction INTO the reversal
        last_dir = s
    if not rev_dirs:                    # no reversal: serve only -> server's side
        return "sideB" if ys[0] >= 0.5 else "sideA"
    return "sideB" if rev_dirs[-1] > 0 else "sideA"


def tail_mean_winner(traj: list[dict], orientation: str, k: int = 5) -> str | None:
    vis = [side_axis(p, orientation) for p in traj if p.get("vis", True)]
    if not vis:
        return None
    tail = vis[-k:]
    return "sideA" if (sum(tail) / len(tail)) < 0.5 else "sideB"


def full_mean_winner(traj: list[dict], orientation: str) -> str | None:
    vis = [side_axis(p, orientation) for p in traj if p.get("vis", True)]
    if not vis:
        return None
    return "sideA" if (sum(vis) / len(vis)) < 0.5 else "sideB"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-dir", required=True,
                    help="dir with trajectories/, annotations_human_holdout.jsonl, orientation.json")
    args = ap.parse_args()
    d = Path(args.data_dir)

    orient = json.loads((d / "orientation.json").read_text()) if (d / "orientation.json").exists() else {}
    labels = [json.loads(l) for l in (d / "annotations_human_holdout.jsonl").read_text().splitlines() if l.strip()]

    methods = {"last_hit": last_hit_winner, "tail_mean": tail_mean_winner, "full_mean": full_mean_winner}
    correct = {m: 0 for m in methods}
    n = 0
    print(f"{'video':16} {'rally':>5} {'pts':>5} {'truth':>6} " + " ".join(f"{m:>9}" for m in methods))
    for lab in labels:
        vid, rid, truth = lab["video"], lab["rally_id"], lab["winner"]
        tf = d / "trajectories" / f"{vid}.json"
        if not tf.exists():
            print(f"{vid:16} {rid:>5}  (no trajectory)")
            continue
        data = json.loads(tf.read_text())
        rally = next((r for r in data.get("rallies", []) if r["rally_id"] == rid), None)
        if not rally:
            print(f"{vid:16} {rid:>5}  (rally not found)")
            continue
        o = orient.get(vid, "side_on")
        fps = data.get("fps", 30)
        traj = rally["trajectory"]
        npts = sum(1 for p in traj if p.get("vis", True))
        picks = {m: f(traj, o, fps) if m == "last_hit" else f(traj, o) for m, f in methods.items()}
        n += 1
        for m, pk in picks.items():
            correct[m] += (pk == truth)
        print(f"{vid:16} {rid:>5} {npts:>5} {truth:>6} " + " ".join(f"{picks[m]:>9}" for m in methods))

    print(f"\nN={n} labeled rallies")
    for m in methods:
        acc = correct[m] / n if n else 0
        print(f"  {m:10} {correct[m]}/{n}  ({acc:.0%})")
    if n < 30:
        print("\n[warn] N is small — directional only. Label more rallies (annotations_human_holdout.jsonl)")
        print("       to reach a statistically meaningful number (~250 target).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
