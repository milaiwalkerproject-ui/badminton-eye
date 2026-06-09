"""Trajectory-level rally annotation tool.

For each rally in data/processed/trajectories/*.json, find the matching video
in data/raw/youtube/<video_id>.mp4, play the rally segment with the trajectory
overlaid, and prompt the user for the winning side.

Keys:
    A = sideA (side_on: LEFT half wins; end_on: NEAR player / bottom wins)
    B = sideB (side_on: RIGHT half wins; end_on: FAR player / top wins)
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

Orientation awareness (ADR-0001): each video's camera orientation is resolved
via hawkeye.orientation (trajectory JSON ``orientation`` field > sidecar
``data/processed/orientation.json`` > ``side_on``), overridable with
``--orientation``. The divider/legend rotates with it:
    side_on: vertical divider, A=left / B=right   (historical, pixel-identical)
    end_on:  horizontal divider, A=near(bottom) / B=far(top)
Keys and the stored record schema are UNCHANGED — the winner is always
``sideA``/``sideB``; its spatial meaning is bound by (winner, orientation).

Usage:
    python -m hawkeye.annotate.annotate_rallies [--annotator NAME]
        [--orientation side_on|end_on]
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
from pathlib import Path

import cv2

from ..orientation import (
    SIDE_ON,
    VALID_ORIENTATIONS,
    load_orientation_map,
    resolve_orientation,
)
from .rally_filter import implausibility_reason

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


# ---------------------------------------------------------------------------
# Orientation-aware presentation (ADR-0001) — pure, testable helpers.
# ---------------------------------------------------------------------------

def resolve_labeler_orientation(video_id: str,
                                traj_payload: dict | None = None,
                                sidecar: dict[str, str] | None = None,
                                override: str | None = None) -> str:
    """Resolve the orientation used to PRESENT a video for labeling.

    Precedence: explicit ``--orientation`` override > trajectory-JSON field >
    sidecar > ``side_on`` (the historical default; absent metadata ALWAYS
    means side_on so every pre-ADR video renders exactly as before).
    """
    if override is not None:
        if override not in VALID_ORIENTATIONS:
            raise ValueError(
                f"invalid orientation {override!r}; expected one of {VALID_ORIENTATIONS}")
        return override
    return resolve_orientation(video_id, traj_payload=traj_payload, sidecar=sidecar)


def win_name(orientation: str = SIDE_ON) -> str:
    """OpenCV window title. side_on returns the historical title verbatim."""
    if orientation == SIDE_ON:
        return WIN_NAME
    if orientation not in VALID_ORIENTATIONS:
        raise ValueError(
            f"invalid orientation {orientation!r}; expected one of {VALID_ORIENTATIONS}")
    return ("Annotate Rally  A=near wins  B=far wins  "
            "N=not a rally (warm-up/junk)  S=skip unclear  R=replay  Q=quit")


def key_legend_text(orientation: str = SIDE_ON) -> str:
    """On-screen key legend. side_on returns the historical string verbatim."""
    if orientation == SIDE_ON:
        return ("A=left wins  B=right wins  N=not a rally (warm-up/junk)  "
                "S=skip unclear  R=replay  Q=quit")
    if orientation not in VALID_ORIENTATIONS:
        raise ValueError(
            f"invalid orientation {orientation!r}; expected one of {VALID_ORIENTATIONS}")
    return ("A=near player wins  B=far player wins  N=not a rally (warm-up/junk)  "
            "S=skip unclear  R=replay  Q=quit")


def side_legend_geometry(orientation: str, W: int, H: int) -> dict:
    """Pure divider/legend geometry for a WxH frame.

    Returns a dict of:
      divider:  ((x1, y1), (x2, y2)) endpoints of the A/B divider line
      rect_a:   ((x1, y1), (x2, y2)) tint rectangle of side A's half
      rect_b:   ((x1, y1), (x2, y2)) tint rectangle of side B's half
      label_a:  (cx, y_base) anchor of the big "A" label; the renderer draws at
                org = (cx - text_w // 2, y_base + text_h)
      label_b:  (cx, y_base) anchor of the big "B" label

    side_on values are EXACTLY the legacy hard-coded geometry (vertical divider
    at W//2, A=left, B=right, both labels along the top edge) — the regression
    bar is pixel-identical side_on rendering.

    end_on: horizontal divider at H//2; A = NEAR player = BOTTOM half,
    B = FAR player = TOP half (ADR-0001: side = 1 - image_y).
    """
    if orientation == SIDE_ON:
        mid = W // 2
        return {
            "divider": ((mid, 0), (mid, H)),
            "rect_a": ((0, 0), (mid, H)),
            "rect_b": ((mid, 0), (W, H)),
            "label_a": (mid // 2, 12),
            "label_b": (mid + mid // 2, 12),
        }
    if orientation not in VALID_ORIENTATIONS:
        raise ValueError(
            f"invalid orientation {orientation!r}; expected one of {VALID_ORIENTATIONS}")
    midy = H // 2
    return {
        "divider": ((0, midy), (W, midy)),
        "rect_a": ((0, midy), (W, H)),   # A = near player = bottom half
        "rect_b": ((0, 0), (W, midy)),   # B = far player  = top half
        "label_a": (W // 2, midy + 12),  # just below the divider
        "label_b": (W // 2, 12),         # top edge, as side_on labels were
    }

# Trajectory overlay tuning.
TRAIL_LEN = 10  # number of most-recent points to draw as a fading trail

# DISPLAY-ONLY padding past the rally's end_frame (fix #4): segmentation often
# cuts right at the last detected shuttle point, hiding the landing/outcome.
# We PLAY a little extra video so the human sees the point resolve, but the
# trajectory overlay still stops at end_frame and start/end_frame and all
# stored data are UNCHANGED.
PAD_S = 2.0


def padded_end_frame(end_frame: int, fps: float,
                     last_video_frame: int | None,
                     pad_s: float = PAD_S) -> int:
    """Last frame to PLAY for a rally clip (display-only padding, fix #4).

    Returns ``min(end_frame + round(pad_s * fps), last_video_frame)``, clamped
    so it is never below ``end_frame`` (a broken/unknown frame count must not
    truncate the original clip; the read loop already stops safely at EOF).

    Pure function — does NOT modify the rally; ``end_frame`` as stored in the
    trajectory/segmentation JSON is untouched.
    """
    pad = int(round(max(pad_s, 0.0) * max(fps, 0.0)))
    target = end_frame + pad
    if last_video_frame is not None and last_video_frame >= 0:
        target = min(target, last_video_frame)
    return max(target, end_frame)


def _draw_side_legend(frame, W: int, H: int, orientation: str = SIDE_ON) -> None:
    """Persistent A/B court-half indicator, orientation-aware (ADR-0001).

    Convention (binding for the stored label): the pipeline's heuristic maps a
    rally to a side via the canonical side axis (hawkeye.orientation):
        side_on: side = x      -> LEFT half  (x < 0.5)        = A (sideA)
                                  RIGHT half (x >= 0.5)        = B (sideB)
        end_on:  side = 1 - y  -> NEAR/bottom half (y >= 0.5)  = A (sideA)
                                  FAR/top half     (y < 0.5)   = B (sideB)
    All geometry comes from ``side_legend_geometry``; side_on values are the
    legacy constants, so side_on rendering is pixel-identical to before.
    """
    g = side_legend_geometry(orientation, W, H)
    overlay = frame.copy()
    # Tint each half faintly so the split is obvious without obscuring play.
    cv2.rectangle(overlay, g["rect_a"][0], g["rect_a"][1], (60, 120, 60), -1)  # A: greenish
    cv2.rectangle(overlay, g["rect_b"][0], g["rect_b"][1], (60, 60, 140), -1)  # B: reddish
    cv2.addWeighted(overlay, 0.12, frame, 0.88, 0, frame)
    # Divider (vertical for side_on, horizontal for end_on).
    cv2.line(frame, g["divider"][0], g["divider"][1], (255, 255, 255), 1)

    # Large persistent side labels, one per half.
    fs = max(1.5, H / 360.0)
    th = max(2, int(H / 200))
    for txt, (cx, y_base), color in (("A", g["label_a"], (120, 255, 120)),
                                     ("B", g["label_b"], (140, 140, 255))):
        (tw, tht), _ = cv2.getTextSize(txt, cv2.FONT_HERSHEY_SIMPLEX, fs, th)
        org = (cx - tw // 2, y_base + tht)
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


def play_and_prompt(video_path: Path, rally: dict, fps: float,
                    orientation: str = SIDE_ON) -> str | None:
    """Return 'sideA' | 'sideB' | 'not_rally' | 'skip' | 'quit'. None to replay.

    ``orientation`` (ADR-0001) only rotates the PRESENTATION (divider, legend,
    window title): side_on keeps the historical vertical A=left/B=right split
    pixel-identical; end_on shows a horizontal split with A=near(bottom) and
    B=far(top). Keys and return values are identical in both orientations.

    'not_rally' (key N) means the clip is not real play (warm-up/junk) and must
    NOT be coerced into an A/B winner; callers store it as a segregated row that
    is excluded from winner training/eval. 'skip' (S) means a real rally with an
    unclear winner and records nothing.

    DISPLAY-ONLY padding (fix #4): playback continues ~PAD_S seconds past
    end_frame (clamped at EOF) so the human sees the point resolve; the
    trajectory overlay is drawn only up to end_frame, and the rally's stored
    start_frame/end_frame are never modified.
    """
    sf, ef = rally["start_frame"], rally["end_frame"]
    traj = rally["trajectory"]

    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        print(f"[annotate] cannot open {video_path}")
        return "skip"
    cap.set(cv2.CAP_PROP_POS_FRAMES, sf)

    # Last playable frame: end_frame + display padding, clamped at EOF.
    n_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    last_video_frame = n_frames - 1 if n_frames > 0 else None
    play_ef = padded_end_frame(ef, fps, last_video_frame)

    # Index trajectory points by frame for overlay lookup.
    by_frame: dict[int, dict] = {p["f"]: p for p in traj}
    pts_so_far: list[tuple[int, int]] = []

    delay = max(1, int(1000.0 / max(fps, 1.0)))

    wname = win_name(orientation)
    legend = key_legend_text(orientation)
    cv2.namedWindow(wname, cv2.WINDOW_NORMAL)
    f = sf
    while f <= play_ef:
        ok, frame = cap.read()
        if not ok:
            break
        H, W = frame.shape[:2]
        # Persistent A/B court-half indicator (drawn first, under the trail).
        _draw_side_legend(frame, W, H, orientation)

        # Overlay only up to the ORIGINAL end_frame; padded frames past ef are
        # context-only (no new trajectory points are added).
        p = by_frame.get(f) if f <= ef else None
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

        hud = f"rally {rally['rally_id']}  frame {f}/{ef}"
        if f > ef:
            hud += "  [post-rally pad]"
        cv2.putText(frame, hud,
                    (12, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 0), 4)
        cv2.putText(frame, hud,
                    (12, 28), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
        # On-screen key legend so the A/B-vs-N-vs-S distinction is always visible.
        cv2.putText(frame, legend, (12, H - 14),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.52, (0, 0, 0), 4)
        cv2.putText(frame, legend, (12, H - 14),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.52, (255, 255, 255), 1)
        cv2.imshow(wname, frame)
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
    ap.add_argument("--orientation", choices=list(VALID_ORIENTATIONS), default=None,
                    help="camera orientation override (default: trajectory JSON "
                         "field, else orientation.json sidecar, else side_on)")
    args = ap.parse_args()

    done = load_done()
    print(f"[annotate] {len(done)} rallies already annotated")

    if not TRAJ_DIR.exists():
        print(f"[annotate] no trajectories at {TRAJ_DIR}"); return 2

    sidecar = load_orientation_map()
    ANN_PATH.parent.mkdir(parents=True, exist_ok=True)
    auto_skipped = 0
    with ANN_PATH.open("a") as ann_f:
        for jp in sorted(TRAJ_DIR.glob("*.json")):
            data = json.loads(jp.read_text())
            vid = data["video"]; fps = float(data.get("fps", 30.0))
            video_path = resolve_video(vid)
            if video_path is None:
                print(f"[annotate] no video for {vid}, skipping")
                continue
            orientation = resolve_labeler_orientation(
                vid, traj_payload=data, sidecar=sidecar, override=args.orientation)
            if orientation != SIDE_ON:
                print(f"[annotate] {vid}: orientation={orientation} "
                      f"(A=near/bottom, B=far/top)")
            for rally in data.get("rallies", []):
                key = (vid, int(rally["rally_id"]))
                if key in done:
                    continue
                # Fix #2: DISPLAY-TIME auto-skip of implausible/degenerate
                # segments. Writes NOTHING (auto-skip != ground-truth
                # not_rally); the N key remains the human fallback.
                reason = implausibility_reason(rally, fps)
                if reason is not None:
                    auto_skipped += 1
                    print(f"[annotate] {vid} rally {rally['rally_id']}: "
                          f"AUTO-SKIP ({reason}) — nothing written",
                          file=sys.stderr)
                    continue
                while True:
                    res = play_and_prompt(video_path, rally, fps, orientation)
                    if res is None:
                        continue  # replay
                    break
                if res == "quit":
                    if auto_skipped:
                        print(f"[annotate] auto-skipped {auto_skipped} implausible segment(s) (display-only, nothing written)", file=sys.stderr)
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
    if auto_skipped:
        print(f"[annotate] auto-skipped {auto_skipped} implausible segment(s) (display-only, nothing written)", file=sys.stderr)
    print("[annotate] all rallies processed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
