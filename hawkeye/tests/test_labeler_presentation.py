"""Tests for the SAFE-NOW labeler presentation fixes (#2 auto-skip, #4 padding).

Pure-logic tests only: no cv2 GUI paths are exercised. ``rally_filter`` is
cv2-free; ``padded_end_frame`` is a pure function inside annotate_rallies.
"""
from __future__ import annotations

import copy
import json

import pytest

from hawkeye.annotate.annotate_rallies import PAD_S, padded_end_frame
from hawkeye.annotate.rally_filter import (
    DEGENERATE_DUR_S,
    DEGENERATE_MAX_POINTS,
    MAX_DUR_S,
    MAX_GAP_RATIO,
    MIN_DUR_S,
    MIN_POINTS,
    implausibility_reason,
    is_plausible_rally,
)

FPS = 30.0


def make_rally(dur_s: float, fps: float = FPS, *, n_points: int | None = None,
               sf: int = 100, rally_id: int = 1) -> dict:
    """Rally of dur_s seconds; by default one visible point per frame."""
    ef = sf + int(round(dur_s * fps))
    if n_points is None:
        frames = range(sf, ef + 1)
    else:
        n_frames = ef - sf + 1
        step = max(1, n_frames // max(n_points, 1))
        frames = list(range(sf, ef + 1, step))[:n_points]
    traj = [{"f": f, "x": 0.5, "y": 0.5, "conf": 0.9, "vis": True} for f in frames]
    return {"rally_id": rally_id, "start_frame": sf, "end_frame": ef, "trajectory": traj}


# ---------------------------------------------------------------------------
# Fix #2 — is_plausible_rally thresholds
# ---------------------------------------------------------------------------

class TestIsPlausibleRally:
    def test_in_range_rally_passes(self):
        rally = make_rally(8.0)
        assert is_plausible_rally(rally, FPS)
        assert implausibility_reason(rally, FPS) is None

    def test_boundary_durations_pass(self):
        assert is_plausible_rally(make_rally(MIN_DUR_S), FPS)
        assert is_plausible_rally(make_rally(MAX_DUR_S), FPS)

    def test_too_short_rejected(self):
        rally = make_rally(1.0)
        assert not is_plausible_rally(rally, FPS)
        assert "too short" in implausibility_reason(rally, FPS)

    def test_too_long_rejected(self):
        rally = make_rally(45.0)
        assert not is_plausible_rally(rally, FPS)
        assert "too long" in implausibility_reason(rally, FPS)

    def test_sparse_rejected_below_min_points(self):
        rally = make_rally(8.0, n_points=MIN_POINTS - 1)
        assert not is_plausible_rally(rally, FPS)
        assert "too few visible points" in implausibility_reason(rally, FPS)

    def test_invisible_points_do_not_count(self):
        rally = make_rally(8.0)
        for p in rally["trajectory"]:
            p["vis"] = False
        assert not is_plausible_rally(rally, FPS)

    def test_excessive_gap_ratio_rejected(self):
        # 20s @30fps = ~600 frames; 12 visible points -> gap ratio ~0.98.
        rally = make_rally(20.0, n_points=12)
        assert not is_plausible_rally(rally, FPS)
        assert "gap ratio" in implausibility_reason(rally, FPS)

    def test_dense_track_passes_gap_ratio(self):
        rally = make_rally(20.0)  # one point per frame -> gap ratio ~0
        assert is_plausible_rally(rally, FPS)

    def test_degenerate_duration_rejected(self):
        # The IMG_4665-style monsters: 357s and 156s "rallies".
        for dur in (357.0, 156.0, DEGENERATE_DUR_S + 1):
            rally = make_rally(dur)
            assert not is_plausible_rally(rally, FPS)
            assert "degenerate" in implausibility_reason(rally, FPS)

    def test_degenerate_point_count_rejected(self):
        rally = make_rally(8.0)
        p = rally["trajectory"][0]
        rally["trajectory"] = [dict(p) for _ in range(DEGENERATE_MAX_POINTS + 1)]
        assert not is_plausible_rally(rally, FPS)
        assert "degenerate" in implausibility_reason(rally, FPS)

    def test_missing_frame_bounds_rejected(self):
        assert not is_plausible_rally({"trajectory": []}, FPS)
        assert not is_plausible_rally({"start_frame": 0, "trajectory": []}, FPS)
        assert not is_plausible_rally({"end_frame": 100, "trajectory": []}, FPS)

    def test_filter_never_mutates_rally(self):
        rally = make_rally(8.0)
        snapshot = copy.deepcopy(rally)
        is_plausible_rally(rally, FPS)
        implausibility_reason(rally, FPS)
        assert rally == snapshot

    def test_thresholds_match_legacy_usable_values(self):
        # Promoted from holdout_label._usable — values must not drift.
        assert MIN_POINTS == 10
        assert MIN_DUR_S == 2.5
        assert MAX_DUR_S == 40.0
        assert 0.0 < MAX_GAP_RATIO < 1.0
        assert DEGENERATE_DUR_S >= MAX_DUR_S


class TestSelectSampleUsesSharedFilter:
    def test_degenerate_rally_excluded_from_sample(self, tmp_path, monkeypatch):
        from hawkeye.annotate import holdout_label

        good = make_rally(8.0, rally_id=1)
        monster = make_rally(357.0, rally_id=2)
        (tmp_path / "vid1.json").write_text(json.dumps(
            {"video": "vid1", "fps": FPS, "rallies": [good, monster]}))

        monkeypatch.setattr(holdout_label, "TRAJ_DIR", tmp_path)
        monkeypatch.setattr(holdout_label, "resolve_video",
                            lambda vid: tmp_path / f"{vid}.mp4")

        picked = holdout_label.select_sample(n=10, seed=0)
        ids = [(vid, r["rally_id"]) for vid, r, _fps in picked]
        assert ("vid1", 1) in ids
        assert ("vid1", 2) not in ids
        # Trajectory JSON on disk untouched (display-time filter only).
        data = json.loads((tmp_path / "vid1.json").read_text())
        assert len(data["rallies"]) == 2


# ---------------------------------------------------------------------------
# Fix #4 — display-only padding clamp math
# ---------------------------------------------------------------------------

class TestPaddedEndFrame:
    def test_pads_by_pad_s_seconds(self):
        assert padded_end_frame(1000, 30.0, 100_000) == 1000 + round(PAD_S * 30)

    def test_clamps_at_eof(self):
        assert padded_end_frame(1000, 30.0, 1020) == 1020

    def test_eof_exactly_at_end_frame(self):
        assert padded_end_frame(1000, 30.0, 1000) == 1000

    def test_eof_before_end_frame_never_truncates_clip(self):
        # Bogus/short frame count must not cut the original clip; the read
        # loop stops safely at EOF anyway.
        assert padded_end_frame(1000, 30.0, 900) == 1000

    def test_unknown_frame_count_pads_unclamped(self):
        assert padded_end_frame(1000, 30.0, None) == 1000 + round(PAD_S * 30)

    def test_fractional_fps_rounds(self):
        assert padded_end_frame(1000, 29.97, None, pad_s=2.0) == 1000 + 60

    def test_zero_pad_is_identity(self):
        assert padded_end_frame(1000, 30.0, 100_000, pad_s=0.0) == 1000

    def test_result_never_below_end_frame(self):
        for last in (None, -1, 0, 500, 999, 1000, 1059, 1060, 10**9):
            assert padded_end_frame(1000, 30.0, last) >= 1000

    def test_pad_s_is_about_two_seconds(self):
        assert 1.5 <= PAD_S <= 2.5
