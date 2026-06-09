"""Shared DISPLAY-TIME rally plausibility filter (fix #2, PIPELINE-FIX-PLAN).

Promoted from ``holdout_label._usable`` so the interactive labelers
(``annotate_rallies`` and ``holdout_label``) share ONE source of truth for
"is this segment worth showing a human at all?".

CRITICAL SEMANTICS — presentation only, zero data mutation:
  * An auto-skip writes NOTHING. It does NOT write an N / ``not_rally`` row:
    auto-skip is a heuristic display decision, NOT ground truth. The N key
    remains the human fallback for junk that passes this filter.
  * Trajectory JSONs, annotation JSONLs, start/end frames and segmentation
    data are never touched by this module. It only decides whether a rally
    is *presented* for labeling.

Rules (conservative on purpose — hiding a real rally is the failure mode):
  * duration must be within [MIN_DUR_S, MAX_DUR_S]
  * at least MIN_POINTS visible trajectory points
  * gap_ratio (fraction of rally frames WITHOUT a visible point) must not be
    excessive — a near-empty track is noise, not a followable rally
  * degenerate collapse: absurd duration (> DEGENERATE_DUR_S) or an absurd
    point count (> DEGENERATE_MAX_POINTS) means the segmenter collapsed
    most of a video into one "rally" (e.g. the IMG_4665 357s/156s monsters)
"""
from __future__ import annotations

# Usability thresholds (from P0 spike (b), previously in holdout_label.py).
MIN_POINTS = 10          # below this = noise/partial detection
MIN_DUR_S = 2.5          # shorter than a real rally
MAX_DUR_S = 40.0         # longer = a segmentation failure (whole-video collapse)

# Fraction of frames in [start_frame, end_frame] with NO visible point above
# which the track is too sparse to follow. 0.9 is deliberately permissive so
# borderline-but-real rallies still reach a human (who can press N/S).
MAX_GAP_RATIO = 0.9

# Degenerate-collapse rule: values no real rally can reach. Catches
# whole-video segmentation collapses regardless of the tighter MAX_DUR_S.
DEGENERATE_DUR_S = 60.0
DEGENERATE_MAX_POINTS = 2000


def implausibility_reason(rally: dict, fps: float) -> str | None:
    """Return a short human-readable reason this rally should be auto-skipped,
    or None if it is plausible and should be shown for labeling.

    Pure function of the rally dict + fps; never mutates its input.
    """
    sf, ef = rally.get("start_frame"), rally.get("end_frame")
    if sf is None or ef is None:
        return "missing start/end frame"

    dur = (ef - sf) / max(fps, 1.0)
    traj = rally.get("trajectory", [])

    if dur > DEGENERATE_DUR_S or len(traj) > DEGENERATE_MAX_POINTS:
        return (f"degenerate collapse (dur={dur:.1f}s, {len(traj)} pts; "
                f"limits {DEGENERATE_DUR_S:.0f}s/{DEGENERATE_MAX_POINTS})")
    if dur < MIN_DUR_S:
        return f"too short ({dur:.2f}s < {MIN_DUR_S}s)"
    if dur > MAX_DUR_S:
        return f"too long ({dur:.1f}s > {MAX_DUR_S}s)"

    n_vis = sum(1 for p in traj if p.get("vis", True))
    if n_vis < MIN_POINTS:
        return f"too few visible points ({n_vis} < {MIN_POINTS})"

    n_frames = ef - sf + 1
    if n_frames > 0:
        gap_ratio = 1.0 - (n_vis / n_frames)
        if gap_ratio > MAX_GAP_RATIO:
            return f"excessive gap ratio ({gap_ratio:.2f} > {MAX_GAP_RATIO})"
    return None


def is_plausible_rally(rally: dict, fps: float) -> bool:
    """True if the rally passes the display-time plausibility filter."""
    return implausibility_reason(rally, fps) is None
