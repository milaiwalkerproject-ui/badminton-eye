"""Cross-court shuttle mask — POST-FILTER on existing trajectory JSONs.

Problem (fix #3 in the pipeline plan): the offline pipeline has no court mask,
so the heatmap argmax grabs shuttles from ADJACENT courts, polluting mean_x and
every downstream winner heuristic. Re-running TrackNet is the dominant GPU
cost; this module instead post-filters the already-extracted trajectories in
seconds per JSON.

How it works:
  - A per-video "active court" quad lives in a sidecar
    ``data/processed/court_masks.json``: ``{video_id: [[x, y], ...4 corners]}``,
    NORMALIZED 0-1 coords (same space as trajectory points).
  - For every trajectory JSON, each point is tested against the quad.
    Points OUTSIDE the quad get ``vis = false``. Points are NEVER deleted, so
    frame indices / point counts / rally boundaries are all preserved.
  - Results are written to a NEW directory (default
    ``data/processed/trajectories_masked/``) mirroring the original filenames.
    ORIGINALS ARE NEVER TOUCHED.
  - Videos with no mask entry are copied through byte-identical with a logged
    warning (so the masked dir is always a complete corpus).

NOTE: downstream consumers (winner_classifier / holdout_eval / export_shots)
are NOT switched to the masked dir here — that is a separate, signoff-gated
change.

Usage:
    # Apply masks (post-filter):
    python -m hawkeye.preprocess.mask_courts \
        --in data/processed/trajectories \
        --out data/processed/trajectories_masked \
        --masks data/processed/court_masks.json

    # Defaults are exactly the paths above, so plain form works too:
    python -m hawkeye.preprocess.mask_courts

    # Capture a quad for one video (click 4 corners on the first frame):
    python -m hawkeye.preprocess.mask_courts --capture IMG_4665
    #   click 4 corners | u = undo | r = reset | s/ENTER = save | q/ESC = abort
"""
from __future__ import annotations

import argparse
import json
import logging
import shutil
import sys
from pathlib import Path

logger = logging.getLogger(__name__)

REPO_ROOT = Path(__file__).resolve().parents[3]
TRAJ_DIR = REPO_ROOT / "data" / "processed" / "trajectories"
MASKED_DIR = REPO_ROOT / "data" / "processed" / "trajectories_masked"
MASKS_PATH = REPO_ROOT / "data" / "processed" / "court_masks.json"

# Tolerance for the "point exactly on a quad edge" test. A shuttle on the
# court boundary line is legitimate play, so edge points count as INSIDE.
_EDGE_EPS = 1e-9

Quad = list[list[float]]  # [[x, y]] * 4, normalized 0-1


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------

def _on_segment(px: float, py: float, ax: float, ay: float,
                bx: float, by: float, eps: float = _EDGE_EPS) -> bool:
    """True if point P lies on segment AB (within ``eps``)."""
    cross = (bx - ax) * (py - ay) - (by - ay) * (px - ax)
    if abs(cross) > eps:
        return False
    return (min(ax, bx) - eps <= px <= max(ax, bx) + eps
            and min(ay, by) - eps <= py <= max(ay, by) + eps)


def point_in_quad(x: float, y: float, quad: Quad) -> bool:
    """Ray-casting point-in-polygon test for the active-court quad.

    Points exactly on an edge or vertex count as INSIDE (a shuttle on the
    line is real play; we only blank clearly-outside detections).
    """
    n = len(quad)
    # Edge/vertex points are inside by definition.
    for i in range(n):
        ax, ay = quad[i]
        bx, by = quad[(i + 1) % n]
        if _on_segment(x, y, ax, ay, bx, by):
            return True
    inside = False
    j = n - 1
    for i in range(n):
        xi, yi = quad[i]
        xj, yj = quad[j]
        if (yi > y) != (yj > y):
            x_cross = (xj - xi) * (y - yi) / (yj - yi) + xi
            if x < x_cross:
                inside = not inside
        j = i
    return inside


def validate_quad(quad: object, video_id: str = "?") -> Quad:
    """Validate one sidecar entry: 4 points, each [x, y] with 0 <= v <= 1."""
    if (not isinstance(quad, list) or len(quad) != 4
            or any(not isinstance(p, (list, tuple)) or len(p) != 2 for p in quad)):
        raise ValueError(f"court_masks[{video_id!r}]: expected [[x,y]*4], got {quad!r}")
    out: Quad = []
    for p in quad:
        x, y = float(p[0]), float(p[1])
        if not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0):
            raise ValueError(
                f"court_masks[{video_id!r}]: coords must be normalized 0-1, got {p!r}")
        out.append([x, y])
    return out


# ---------------------------------------------------------------------------
# Masking
# ---------------------------------------------------------------------------

def load_masks(masks_path: Path) -> dict[str, Quad]:
    """Load and validate the ``{video_id: quad}`` sidecar."""
    raw = json.loads(Path(masks_path).read_text())
    if not isinstance(raw, dict):
        raise ValueError(f"{masks_path}: expected a JSON object {{video_id: quad}}")
    return {vid: validate_quad(quad, vid) for vid, quad in raw.items()}


def mask_trajectory(data: dict, quad: Quad) -> tuple[dict, int, int]:
    """Set ``vis=false`` on every point outside ``quad`` (in place).

    Points are never removed; only the ``vis`` flag flips. Returns
    ``(data, total_points, flipped_points)``.
    """
    total = flipped = 0
    for rally in data.get("rallies", []):
        for p in rally.get("trajectory", []):
            total += 1
            if not point_in_quad(p["x"], p["y"], quad):
                if p.get("vis", True):
                    flipped += 1
                p["vis"] = False
    return data, total, flipped


def run(in_dir: Path, out_dir: Path, masks_path: Path) -> dict[str, int]:
    """Post-filter every trajectory JSON in ``in_dir`` into ``out_dir``.

    Files whose video id has a quad in the sidecar are masked; the rest are
    copied through byte-identical with a warning. Originals are read-only.
    Returns summary counts.
    """
    in_dir, out_dir = Path(in_dir), Path(out_dir)
    if not in_dir.is_dir():
        raise FileNotFoundError(f"trajectory dir not found: {in_dir}")
    masks = load_masks(masks_path)
    out_dir.mkdir(parents=True, exist_ok=True)

    stats = {"files": 0, "masked": 0, "passthrough": 0, "points": 0, "flipped": 0}
    for in_path in sorted(in_dir.glob("*.json")):
        stats["files"] += 1
        out_path = out_dir / in_path.name
        video_id = in_path.stem
        quad = masks.get(video_id)
        if quad is None:
            logger.warning(
                "no court mask for %r — copied through UNCHANGED", video_id)
            shutil.copyfile(in_path, out_path)
            stats["passthrough"] += 1
            continue
        data = json.loads(in_path.read_text())
        data, total, flipped = mask_trajectory(data, quad)
        out_path.write_text(json.dumps(data))
        stats["masked"] += 1
        stats["points"] += total
        stats["flipped"] += flipped
        logger.info("%s: %d/%d points outside court -> vis=false",
                    in_path.name, flipped, total)

    logger.info(
        "done: %(files)d files (%(masked)d masked, %(passthrough)d passthrough), "
        "%(flipped)d/%(points)d points blanked", stats)
    return stats


# ---------------------------------------------------------------------------
# Capture helper (click 4 corners on the first frame)
# ---------------------------------------------------------------------------

def capture_quad(video: str, masks_path: Path) -> Quad | None:
    """Show the first frame of ``video``; user clicks the 4 court corners.

    ``video`` is a path or a video id resolvable under ``data/raw/`` (reuses
    ``annotate_rallies.resolve_video``). Clicks are normalized by the display
    size (normalized coords are resolution-independent) and appended to the
    sidecar. Returns the saved quad, or None if aborted.
    """
    import cv2  # lazy: the post-filter itself must not require OpenCV

    path = Path(video)
    if not path.is_file():
        from hawkeye.annotate.annotate_rallies import resolve_video
        resolved = resolve_video(video)
        if resolved is None:
            raise FileNotFoundError(f"video not found (path or id): {video}")
        path = resolved
    video_id = path.stem

    cap = cv2.VideoCapture(str(path))
    ok, frame = cap.read()
    cap.release()
    if not ok:
        raise RuntimeError(f"could not read first frame of {path}")

    # Fit on screen; clicks are normalized by the DISPLAYED size, so the
    # scale factor cancels out.
    max_w = 1440
    if frame.shape[1] > max_w:
        s = max_w / frame.shape[1]
        frame = cv2.resize(frame, None, fx=s, fy=s)
    h, w = frame.shape[:2]

    pts: list[tuple[int, int]] = []
    win = f"court mask: {video_id}  (click 4 corners | u=undo r=reset s=save q=abort)"

    def on_mouse(event: int, x: int, y: int, *_args) -> None:
        if event == cv2.EVENT_LBUTTONDOWN and len(pts) < 4:
            pts.append((x, y))

    cv2.namedWindow(win)
    cv2.setMouseCallback(win, on_mouse)
    try:
        while True:
            disp = frame.copy()
            for i, (x, y) in enumerate(pts):
                cv2.circle(disp, (x, y), 6, (0, 255, 0), -1)
                cv2.putText(disp, str(i + 1), (x + 8, y - 8),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
            if len(pts) >= 2:
                closed = len(pts) == 4
                import numpy as np
                cv2.polylines(disp, [np.array(pts)], closed, (0, 255, 255), 2)
            cv2.imshow(win, disp)
            key = cv2.waitKey(30) & 0xFF
            if key in (ord("q"), 27):  # q / ESC
                logger.info("capture aborted; nothing saved")
                return None
            if key == ord("u") and pts:
                pts.pop()
            if key == ord("r"):
                pts.clear()
            if key in (ord("s"), 13) and len(pts) == 4:  # s / ENTER
                break
    finally:
        cv2.destroyAllWindows()

    quad = validate_quad([[round(x / w, 4), round(y / h, 4)] for x, y in pts],
                         video_id)
    masks_path = Path(masks_path)
    existing = json.loads(masks_path.read_text()) if masks_path.exists() else {}
    existing[video_id] = quad
    masks_path.parent.mkdir(parents=True, exist_ok=True)
    masks_path.write_text(json.dumps(existing, indent=2, sort_keys=True) + "\n")
    logger.info("saved quad for %r -> %s", video_id, masks_path)
    return quad


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    ap = argparse.ArgumentParser(
        prog="python -m hawkeye.preprocess.mask_courts",
        description="Post-filter trajectories with a per-video court quad "
                    "(or --capture one). Originals are never modified.")
    ap.add_argument("--in", dest="in_dir", type=Path, default=TRAJ_DIR,
                    help=f"trajectory dir (default: {TRAJ_DIR})")
    ap.add_argument("--out", dest="out_dir", type=Path, default=MASKED_DIR,
                    help=f"output dir for masked copies (default: {MASKED_DIR})")
    ap.add_argument("--masks", type=Path, default=MASKS_PATH,
                    help=f"court_masks.json sidecar (default: {MASKS_PATH})")
    ap.add_argument("--capture", metavar="VIDEO",
                    help="capture mode: click the 4 court corners on the first "
                         "frame of VIDEO (path or video id) and save to --masks")
    args = ap.parse_args(argv)

    if args.capture:
        return 0 if capture_quad(args.capture, args.masks) is not None else 1

    if not Path(args.masks).exists():
        ap.error(f"masks sidecar not found: {args.masks} "
                 "(capture quads first with --capture VIDEO)")
    run(args.in_dir, args.out_dir, args.masks)
    return 0


if __name__ == "__main__":
    sys.exit(main())
