"""Trajectory-level rally annotation tool.

For each rally in data/processed/trajectories/*.json, find the matching video
in data/raw/youtube/<video_id>.mp4, play the rally segment with the trajectory
overlaid, and prompt the user for the winning side.

Keys:
    A = sideA (left half wins)
    B = sideB (right half wins)
    N = NOT A RALLY  -- the segmenter surfaced non-play footage (warm-up,
        knock-up, players getting ready, between-point junk). DISTINCT from S:
        N means "this clip is not real play at all", so it must NEVER be forced
        into an A/B winner label. N rows are STORED (segregated, never trained)
        so they can later train a rally-vs-not-rally filter.
    S = skip -- it IS a rally but the winner is unclear; nothing is recorded.
    R = replay
    Q = quit & save

Verdict semantics (what gets written):
    A / B          -> {"winner": "sideA"|"sideB"} (training-grade)
    N (not a rally) -> {"winner": "not_rally", "not_rally": true,
                        "split": "not_rally"}  (stored, EXCLUDED from train/eval)
    S (skip)        -> no row written

Annotations appended to data/processed/annotations.jsonl. Already-annotated
(video, rally_id) pairs are skipped on resume.

Usage:
    python -m hawkeye.annotate.annotate_rallies [--annotator NAME]
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
from pathlib import Path

import cv2

REPO_ROOT = Path(__file__).resolve().parents[3]
TRAJ_DIR = REPO_ROOT / "data" / "processed" / "trajectories"
RAW_DIR = REPO_ROOT / "data" / "raw"
# Kept for backward compat / docs; resolve_video() now searches all of RAW_DIR.
VIDEO_DIR = RAW_DIR / "youtube"
ANN_PATH = REPO_ROOT / "data" / "processed" / "annotations.jsonl"

# Common video container extensions. Matching is case-insensitive, so this set
# covers .mp4/.MP4, .mov/.MOV, .m4v/.M4V regardless of how the file is stored.
VIDEO_EXTS = (".mp4", ".mov", ".m4v")


def resolve_video(vid: str, raw_dir: Path = RAW_DIR) -> Path | None:
    """Find the source video for a trajectory's ``<vid>`` id under ``data/raw/``.

    Historically videos lived only in ``data/raw/youtube/<vid>.mp4``. User footage
    (e.g. ``data/raw/own_footage/IMG_4665.MOV``) lives in sibling dirs and uses
    other extensions/cases. This searches ``raw_dir`` RECURSIVELY for a file named
    ``<vid>`` with any common video extension (``.mp4 .mov .m4v``), case-insensitive,
    and returns the first match (or None if not found).

    Existing youtube ``.mp4`` videos resolve exactly as before (the youtube/ dir is
    searched first for a deterministic, behavior-preserving result).
    """
    exts = {e.lower() for e in VIDEO_EXTS}

    def _scan(base: Path) -> Path | None:
        if not base.exists():
            return None
        # rglob a stable, case-insensitive set of candidates.
        for p in sorted(base.rglob(f"{vid}.*")):
            if p.is_file() and p.suffix.lower() in exts:
                return p
        return None

    # Preserve legacy behavior: prefer youtube/<vid>.mp4 first.
    youtube = raw_dir / "youtube"
    direct = youtube / f"{vid}.mp4"
    if direct.exists():
        return direct
    hit = _scan(youtube)
    if hit is not None:
        return hit
    # Fall back to a recursive search of the whole raw tree (own_footage/, etc.).
    return _scan(raw_dir)

WIN_NAME = ("Annotate Rally  A=left wins  B=right wins  "
            "N=not a rally (warm-up/junk)  S=skip unclear  R=replay  Q=quit")

# Trajectory overlay tuning.
TRAIL_LEN = 10  # number of most-recent points to draw as a fading trail


def _draw_side_legend(frame, W: int, H: int) -> None:
    """Persistent A/B court-half indicator.

    Convention (binding for the stored label): the pipeline's heuristic maps a
    rally to a side by the shuttle's mean x of its final visible points --
    ``"sideA" if mean_x < 0.5 else "sideB"`` (see hawkeye/train/holdout_eval.py
    and export_shots.py ``_heuristic_winner``). Normalized x maps to the frame's
    horizontal axis (px = x * W in the renderer), so:
        LEFT half  (x < 0.5)  -> A (sideA)
        RIGHT half (x >= 0.5) -> B (sideB)
    """
    mid = W // 2
    overlay = frame.copy()
    # Tint each half faintly so the split is obvious without obscuring play.
    cv2.rectangle(overlay, (0, 0), (mid, H), (60, 120, 60), -1)        # A: greenish
    cv2.rectangle(overlay, (mid, 0), (W, H), (60, 60, 140), -1)        # B: reddish
    cv2.addWeighted(overlay, 0.12, frame, 0.88, 0, frame)
    # Vertical divider.
    cv2.line(frame, (mid, 0), (mid, H), (255, 255, 255), 1)

    # Large persistent side labels, centered in each half.
    fs = max(1.5, H / 360.0)
    th = max(2, int(H / 200))
    for txt, cx, color in (("A", mid // 2, (120, 255, 120)),
                           ("B", mid + mid // 2, (140, 140, 255))):
        (tw, tht), _ = cv2.getTextSize(txt, cv2.FONT_HERSHEY_SIMPLEX, fs, th)
        org = (cx - tw // 2, tht + 12)
        cv2.putText(frame, txt, org, cv2.FONT_HERSHEY_SIMPLEX, fs, (0, 0, 0), th + 3)
        cv2.putText(frame, txt, org, cv2.FONT_HERSHEY_SIMPLEX, fs, color, th)


def load_done() -> set[tuple[str, int]]:
    done: set[tuple[str, int]] = set()
    if ANN_PATH.exists():
        for line in ANN_PATH.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
                done.add((rec["video"], int(rec["rally_id"])))
            except Exception:
                pass
    return done


def play_and_prompt(video_path: Path, rally: dict, fps: float) -> str | None:
    """Return 'sideA' | 'sideB' | 'not_rally' | 'skip' | 'quit'. None to replay.

    'not_rally' (key N) means the clip is not real play (warm-up/junk) and must
    NOT be coerced into an A/B winner; callers store it as a segregated row that
    is excluded from winner training/eval. 'skip' (S) means a real rally with an
    unclear winner and records nothing.
    """
    sf, ef = rally["start_frame"], rally["end_frame"]
    traj = rally["trajectory"]

    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        print(f"[annotate] cannot open {video_path}")
        return "skip"
    cap.set(cv2.CAP_PROP_POS_FRAMES, sf)

    # Index trajectory points by frame for overlay lookup.
    by_frame: dict[int, dict] = {p["f"]: p for p in traj}
    pts_so_far: list[tuple[int, int]] = []

    delay = max(1, int(1000.0 / max(fps, 1.0)))

    cv2.namedWindow(WIN_NAME, cv2.WINDOW_NORMAL)
    f = sf
    while f <= ef:
        ok, frame = cap.read()
        if not ok:
            break
        H, W = frame.shape[:2]
        # Persistent A/B court-half indicator (drawn first, under the trail).
        _draw_side_legend(frame, W, H)

        p = by_frame.get(f)
        if p is not None and p.get("vis"):
            px, py = int(p["x"] * W), int(p["y"] * H)
            pts_so_far.append((px, py))

        # Draw only a SHORT recent trail, fading older points (thinner + dimmer)
        # so the shuttle stays visible even on long rallies.
        trail = pts_so_far[-TRAIL_LEN:]
        n_trail = len(trail)
        for i in range(1, n_trail):
            age = i / n_trail  # 0 (oldest) .. 1 (newest)
            thickness = max(1, int(1 + 3 * age))
            color = (0, int(120 + 135 * age), int(180 + 75 * age))  # dim->bright yellow
            cv2.line(frame, trail[i - 1], trail[i], color, thickness)

        # Mark the CURRENT shuttle position prominently and unmistakably.
        if pts_so_far:
            cur = pts_so_far[-1]
            cv2.circle(frame, cur, 11, (0, 0, 0), -1)          # dark backing ring
            cv2.circle(frame, cur, 8, (0, 0, 255), -1)         # bright red fill
            cv2.circle(frame, cur, 13, (255, 255, 255), 2)     # white outline

        cv2.putText(frame, f"rally {rally['rally_id']}  frame {f}/{ef}",
                    (12, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 0), 4)
        cv2.putText(frame, f"rally {rally['rally_id']}  frame {f}/{ef}",
                    (12, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
        # On-screen key legend so the A/B-vs-N-vs-S distinction is always visible.
        legend = "A=left wins  B=right wins  N=not a rally (warm-up/junk)  S=skip unclear  R=replay  Q=quit"
        cv2.putText(frame, legend, (12, H - 14),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.52, (0, 0, 0), 4)
        cv2.putText(frame, legend, (12, H - 14),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.52, (255, 255, 255), 1)
        cv2.imshow(WIN_NAME, frame)
        k = cv2.waitKey(delay) & 0xFF
        if k in (ord('a'), ord('A')):
            cap.release(); return "sideA"
        if k in (ord('b'), ord('B')):
            cap.release(); return "sideB"
        if k in (ord('n'), ord('N')):
            cap.release(); return "not_rally"
        if k in (ord('s'), ord('S')):
            cap.release(); return "skip"
        if k in (ord('q'), ord('Q')):
            cap.release(); return "quit"
        if k in (ord('r'), ord('R')):
            cap.release(); return None
        f += 1
    cap.release()

    # End of clip — wait for keypress.
    while True:
        k = cv2.waitKey(0) & 0xFF
        if k in (ord('a'), ord('A')): return "sideA"
        if k in (ord('b'), ord('B')): return "sideB"
        if k in (ord('n'), ord('N')): return "not_rally"
        if k in (ord('s'), ord('S')): return "skip"
        if k in (ord('q'), ord('Q')): return "quit"
        if k in (ord('r'), ord('R')): return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--annotator", default=os.environ.get("USER", "unknown"))
    args = ap.parse_args()

    done = load_done()
    print(f"[annotate] {len(done)} rallies already annotated")

    if not TRAJ_DIR.exists():
        print(f"[annotate] no trajectories at {TRAJ_DIR}"); return 2

    ANN_PATH.parent.mkdir(parents=True, exist_ok=True)
    with ANN_PATH.open("a") as ann_f:
        for jp in sorted(TRAJ_DIR.glob("*.json")):
            data = json.loads(jp.read_text())
            vid = data["video"]; fps = float(data.get("fps", 30.0))
            video_path = resolve_video(vid)
            if video_path is None:
                print(f"[annotate] no video for {vid}, skipping")
                continue
            for rally in data.get("rallies", []):
                key = (vid, int(rally["rally_id"]))
                if key in done:
                    continue
                while True:
                    res = play_and_prompt(video_path, rally, fps)
                    if res is None:
                        continue  # replay
                    break
                if res == "quit":
                    print("[annotate] saving and quitting"); cv2.destroyAllWindows(); return 0
                if res == "skip":
                    print(f"[annotate] {vid} rally {rally['rally_id']}: skipped (unclear winner, not recorded)")
                    continue
                rec = {
                    "video": vid,
                    "rally_id": int(rally["rally_id"]),
                    "winner": res,
                    "annotator": args.annotator,
                    "timestamp": dt.datetime.utcnow().isoformat() + "Z",
                }
                # 'not_rally' is STORED but segregated: never a sideA/sideB winner,
                # excluded from winner train/eval (kept for a future rally-vs-not
                # filter). Mark it distinctly so loaders can tell it apart from S.
                if res == "not_rally":
                    rec["not_rally"] = True
                    rec["split"] = "not_rally"
                ann_f.write(json.dumps(rec) + "\n"); ann_f.flush()
                done.add(key)
                print(f"[annotate] {vid} rally {rally['rally_id']}: {res}")
    cv2.destroyAllWindows()
    print("[annotate] all rallies processed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
