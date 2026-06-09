"""Ground-truth HOLDOUT labeling launcher (low-friction wrapper).

Purpose: let a human label a small, REPRESENTATIVE sample of rallies in one
~30-90 min session to (1) measure System-2's REAL accuracy and (2) provide one
truly-independent ground-truth signal. The trained classifier's "0.954" is
agreement-with-the-heuristic, NOT truth — this run is how we get the truth.

Why a separate launcher (not annotate_rallies.py directly):
  - annotate_rallies.py walks ALL trajectories alphabetically -> single-video
    bias. We want a STRATIFIED sample across clips (skill tiers / fps / venues).
  - It writes into annotations.jsonl (the classifier's TRAINING file). A holdout
    used to MEASURE accuracy must be kept OUT of training, so we write to a
    dedicated file: data/processed/annotations_human_holdout.jsonl.
  - Adds a target count, live progress (k/N), and resume.

It REUSES annotate_rallies.play_and_prompt (same overlay/keys: A/B/N/S/R/Q), so
the labeling UX is identical and battle-tested. N (not a rally) marks non-play
footage (warm-up/junk) the segmenter mis-surfaced as a rally; those rows are
STORED but segregated (split="not_rally") and excluded from winner train/eval.

Usage (one command):
    python -m hawkeye.annotate.holdout_label --n 200
    python -m hawkeye.annotate.holdout_label --n 200 --dry-run   # show the plan, label nothing
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import random
import sys
from pathlib import Path

from .annotate_rallies import resolve_video
# Usability filter (from P0 spike (b)) lives in the SHARED rally_filter module
# (fix #2): same thresholds as the old local _usable, plus gap-ratio and
# degenerate-collapse rejection. DISPLAY-TIME only — writes nothing.
from .rally_filter import is_plausible_rally

REPO_ROOT = Path(__file__).resolve().parents[3]
TRAJ_DIR = REPO_ROOT / "data" / "processed" / "trajectories"
HOLDOUT_PATH = REPO_ROOT / "data" / "processed" / "annotations_human_holdout.jsonl"


def _load_done() -> set[tuple[str, int]]:
    done: set[tuple[str, int]] = set()
    if HOLDOUT_PATH.exists():
        for line in HOLDOUT_PATH.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
                done.add((rec["video"], int(rec["rally_id"])))
            except Exception:
                pass
    return done


def select_sample(n: int, seed: int = 0) -> list[tuple[str, dict, float]]:
    """Stratified: round-robin across videos that have a resolvable local source
    file (any data/raw/ subdir, any common video extension), taking usable rallies
    until we reach n. Deterministic given seed."""
    rng = random.Random(seed)
    per_video: list[tuple[str, list[dict], float]] = []
    auto_skipped = 0
    for jp in sorted(TRAJ_DIR.glob("*.json")):
        data = json.loads(jp.read_text())
        vid = data["video"]
        if resolve_video(vid) is None:
            continue
        fps = float(data.get("fps", 30.0))
        rallies = data.get("rallies", [])
        usable = [r for r in rallies if is_plausible_rally(r, fps)]
        auto_skipped += len(rallies) - len(usable)
        if not usable:
            continue
        rng.shuffle(usable)
        per_video.append((vid, usable, fps))
    rng.shuffle(per_video)
    if auto_skipped:
        print(f"[holdout] auto-skipped {auto_skipped} implausible segment(s) "
              f"(display-only filter; nothing written)", file=sys.stderr)

    # Round-robin draw → spreads the sample across clips (skill tiers / fps).
    picked: list[tuple[str, dict, float]] = []
    idx = 0
    while len(picked) < n and per_video:
        progressed = False
        for vid, usable, fps in per_video:
            if idx < len(usable):
                picked.append((vid, usable[idx], fps))
                progressed = True
                if len(picked) >= n:
                    break
        if not progressed:
            break
        idx += 1
    return picked


def main() -> int:
    ap = argparse.ArgumentParser(description="Ground-truth holdout labeling")
    ap.add_argument("--n", type=int, default=200, help="target rallies to label (150-300 recommended)")
    ap.add_argument("--seed", type=int, default=0, help="sampling seed (keep fixed for reproducibility)")
    ap.add_argument("--annotator", default="human_holdout")
    ap.add_argument("--dry-run", action="store_true", help="print the selection plan and exit (label nothing)")
    args = ap.parse_args()

    if not TRAJ_DIR.exists():
        print(f"[holdout] no trajectories at {TRAJ_DIR}"); return 2

    sample = select_sample(args.n, args.seed)
    done = _load_done()
    todo = [s for s in sample if (s[0], int(s[1]["rally_id"])) not in done]

    from collections import Counter
    by_vid = Counter(s[0] for s in sample)
    print("=" * 64)
    print(f"  GROUND-TRUTH HOLDOUT — target {args.n} rallies, seed {args.seed}")
    print(f"  selected {len(sample)} rallies across {len(by_vid)} videos")
    print(f"  already labeled: {len(done)}   remaining this session: {len(todo)}")
    print(f"  writing to: {HOLDOUT_PATH}")
    print(f"  keys: A=left wins  B=right wins  N=not a rally (warm-up/junk)  S=skip unclear  R=replay  Q=quit&save")
    print("=" * 64)
    if args.dry_run:
        print("[dry-run] per-video rally counts:")
        for vid, c in by_vid.most_common():
            print(f"    {vid}: {c}")
        print("[dry-run] no labeling performed.")
        return 0

    # Real labeling reuses the existing, battle-tested overlay/prompt loop.
    import cv2
    from .annotate_rallies import play_and_prompt

    HOLDOUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    labeled = 0
    with HOLDOUT_PATH.open("a") as f:
        for i, (vid, rally, fps) in enumerate(todo, 1):
            video_path = resolve_video(vid)
            if video_path is None:
                print(f"[holdout] no video for {vid}, skipping")
                continue
            print(f"[holdout] {i}/{len(todo)}  {vid} rally {rally['rally_id']}")
            while True:
                res = play_and_prompt(video_path, rally, fps)
                if res is None:
                    continue
                break
            if res == "quit":
                print(f"[holdout] saved {labeled} this session ({len(done)+labeled} total). Bye.")
                cv2.destroyAllWindows(); return 0
            if res == "skip":
                continue
            rec = {
                "video": vid, "rally_id": int(rally["rally_id"]),
                "winner": res, "annotator": args.annotator,
                "split": "holdout",
                "timestamp": dt.datetime.utcnow().isoformat() + "Z",
            }
            # 'not_rally' is non-play footage: STORE it (future rally-vs-not
            # filter data) but segregate it (split="not_rally", not "holdout")
            # so it never counts as a sideA/sideB winner in train OR eval.
            if res == "not_rally":
                rec["not_rally"] = True
                rec["split"] = "not_rally"
            f.write(json.dumps(rec) + "\n"); f.flush()
            labeled += 1
    cv2.destroyAllWindows()
    print(f"[holdout] done — {labeled} labeled this session, {len(done)+labeled} total.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
