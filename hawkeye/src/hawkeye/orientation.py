"""Shared camera-orientation support for the hawkeye pipeline (ADR-0001).

Two supported camera orientations:
  - ``side_on`` (default): camera looks along the net; players separate LEFT/RIGHT
    on image-X.  sideA = left half (x < 0.5), sideB = right half.  This is the
    historical convention — every existing trajectory JSON and label was produced
    under it, so ABSENT orientation metadata always means ``side_on``.
  - ``end_on``: camera looks down the court from behind a baseline; players
    separate NEAR/FAR on image-Y.  sideA = near (bottom of frame), sideB = far.

Canonical side axis
-------------------
All side decisions in the pipeline go through ONE mapping that projects the
player-separation axis onto a canonical coordinate where the historical
``mean < 0.5 -> sideA`` rule keeps working unchanged:

  side_on:  side = x              (identity — preserves all existing data/labels)
  end_on:   side = 1.0 - y        (near/bottom: y≈1 -> side≈0 < 0.5 -> sideA;
                                   far/top:     y≈0 -> side≈1       -> sideB)

This is deliberately NOT a whole-coordinate rotation: gravity/arc features
(apex, final velocity, path length) must keep using RAW image coordinates in
both orientations (see ``winner_classifier.featurize``).

Orientation resolution (per video)
----------------------------------
1. explicit ``orientation`` field at the top level of the trajectory JSON;
2. else the sidecar ``data/processed/orientation.json`` (``video_id -> orientation``);
3. else ``side_on``.

End-on inference gate
---------------------
The shipped winner classifier has never trained on a single end-on label, so
end-on MODEL inference is hard-gated: it is only allowed when the model's
``*_meta.json`` explicitly lists ``"end_on"`` in ``trained_orientations``.
Consumers (holdout_eval, export_shots) must skip-with-warning instead of
predicting zero-shot.  See ``end_on_inference_allowed`` / ``check_inference_gate``.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Iterable, Optional

SIDE_ON = "side_on"
END_ON = "end_on"
VALID_ORIENTATIONS = (SIDE_ON, END_ON)

REPO_ROOT = Path(__file__).resolve().parents[2]
ORIENTATION_SIDECAR = REPO_ROOT / "data" / "processed" / "orientation.json"

# Tail-of-rally heuristic parameters shared by every convention site.
TAIL_POINTS = 5
MIN_TAIL_VISIBLE = 3


def _validate(orientation: str) -> str:
    if orientation not in VALID_ORIENTATIONS:
        raise ValueError(
            f"invalid orientation {orientation!r}; expected one of {VALID_ORIENTATIONS}")
    return orientation


def load_orientation_map(path: Optional[Path] = None) -> dict[str, str]:
    """Load the per-video orientation sidecar. Missing file -> {} (all side_on)."""
    p = Path(path) if path is not None else ORIENTATION_SIDECAR
    if not p.exists():
        return {}
    data = json.loads(p.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"orientation sidecar {p} must be a JSON object video_id->orientation")
    return {str(vid): _validate(str(o)) for vid, o in data.items()}


def resolve_orientation(video_id: str,
                        traj_payload: Optional[dict] = None,
                        sidecar: Optional[dict[str, str]] = None) -> str:
    """Resolve a video's orientation: trajectory JSON field > sidecar > side_on."""
    if traj_payload is not None and traj_payload.get("orientation") is not None:
        return _validate(str(traj_payload["orientation"]))
    if sidecar is None:
        sidecar = load_orientation_map()
    return _validate(sidecar.get(video_id, SIDE_ON))


# ---------- canonical side axis (the ONE convention) ----------

def side_coordinate(point: dict, orientation: str = SIDE_ON) -> float:
    """Project one trajectory point onto the canonical side axis (< 0.5 -> sideA)."""
    _validate(orientation)
    if orientation == SIDE_ON:
        return float(point["x"])
    return 1.0 - float(point["y"])  # end_on: near(bottom, y~1) -> ~0; far(top, y~0) -> ~1


def winner_from_side_axis(mean_side: float) -> str:
    """The single source of truth for the historical ``mean < 0.5 -> sideA`` rule."""
    return "sideA" if mean_side < 0.5 else "sideB"


def tail_side_mean(trajectory: Iterable[dict], orientation: str = SIDE_ON,
                   tail: int = TAIL_POINTS) -> tuple[Optional[float], int]:
    """Mean canonical-side coordinate of the last ``tail`` visible points.

    Returns (mean, n_points_used); mean is None when no visible points exist.
    """
    vis = [p for p in trajectory if p.get("vis", True)
           and p.get("x") is not None and p.get("y") is not None]
    if not vis:
        return None, 0
    last = vis[-tail:]
    return (sum(side_coordinate(p, orientation) for p in last) / len(last)), len(last)


def heuristic_winner(trajectory: Iterable[dict], orientation: str = SIDE_ON,
                     tail: int = TAIL_POINTS,
                     min_visible: int = MIN_TAIL_VISIBLE) -> Optional[str]:
    """Shared replacement for the 4 copy-pasted ``mean_x < 0.5 -> sideA`` sites.

    (auto_annotate.classify_rally, holdout_eval._heuristic_winner,
    export_shots._heuristic_winner, winner_classifier's synthetic convention.)
    """
    vis = [p for p in trajectory if p.get("vis", True)
           and p.get("x") is not None and p.get("y") is not None]
    if len(vis) < min_visible:
        return None
    mean_side, _ = tail_side_mean(vis, orientation, tail)
    if mean_side is None:
        return None
    return winner_from_side_axis(mean_side)


# ---------- end-on inference gate (ADR-0001 constraint b) ----------

def end_on_inference_allowed(model_meta: Optional[dict]) -> bool:
    """True only if the model was trained on REAL end-on labels.

    The flag is the ``trained_orientations`` list in the model's ``*_meta.json``;
    a model without the field (every model shipped before ADR-0001) is side-on
    only by definition. Synthetic both-orientation toys do NOT set the flag —
    only a retrain on human end-on labels may write ``"end_on"`` into it.
    """
    if not model_meta:
        return False
    return END_ON in model_meta.get("trained_orientations", [])


def check_inference_gate(orientation: str, model_meta: Optional[dict],
                         context: str = "") -> bool:
    """Gate model inference on an orientation. Returns True when allowed.

    side_on is always allowed; end_on requires ``end_on_inference_allowed``.
    Emits a warning to stderr when blocking (callers skip the rally/video).
    """
    _validate(orientation)
    if orientation == SIDE_ON:
        return True
    if end_on_inference_allowed(model_meta):
        return True
    print(f"[orientation-gate] BLOCKED end_on inference{(' (' + context + ')') if context else ''}: "
          f"model has no end_on training labels (trained_orientations="
          f"{(model_meta or {}).get('trained_orientations', 'absent')}). "
          f"Retrain with human end-on labels before evaluating/predicting end_on.",
          file=sys.stderr)
    return False


def load_model_meta(model_path: Path) -> Optional[dict]:
    """Load ``<Model>_meta.json`` next to an ``.mlpackage`` (None if missing)."""
    meta_path = model_path.with_name(model_path.stem + "_meta.json")
    if not meta_path.exists():
        return None
    try:
        return json.loads(meta_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
