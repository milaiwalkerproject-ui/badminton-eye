"""Tests for the orientation-aware labeler UI (ADR-0001, Labeler UI bullet).

Pure-logic tests only — no cv2 GUI paths are exercised. Covers:
  * side_on divider/legend geometry == the legacy hard-coded values
    (the regression bar: side_on rendering must be pixel-identical);
  * end_on geometry: horizontal divider, A=near=bottom, B=far=top;
  * orientation resolution precedence + side_on fallback;
  * holdout row schema: additive ``orientation`` field, old (pre-ADR) rows
    still parse and resume-skip.
"""
from __future__ import annotations

import json

import pytest

from hawkeye.annotate.annotate_rallies import (
    WIN_NAME,
    key_legend_text,
    resolve_labeler_orientation,
    side_legend_geometry,
    win_name,
)
from hawkeye.annotate.holdout_label import _load_done, build_holdout_record
from hawkeye.orientation import END_ON, SIDE_ON

SIZES = [(1280, 720), (1920, 1080), (640, 360), (1281, 721)]  # incl. odd dims


# ---------------------------------------------------------------------------
# side_on geometry — must equal the legacy hard-coded values exactly.
# ---------------------------------------------------------------------------

class TestSideOnGeometryIsLegacy:
    @pytest.mark.parametrize("W,H", SIZES)
    def test_vertical_divider_at_half_width(self, W, H):
        g = side_legend_geometry(SIDE_ON, W, H)
        mid = W // 2  # legacy: mid = W // 2
        assert g["divider"] == ((mid, 0), (mid, H))

    @pytest.mark.parametrize("W,H", SIZES)
    def test_tint_rects_match_legacy(self, W, H):
        g = side_legend_geometry(SIDE_ON, W, H)
        mid = W // 2
        assert g["rect_a"] == ((0, 0), (mid, H))      # legacy A: left half
        assert g["rect_b"] == ((mid, 0), (W, H))      # legacy B: right half

    @pytest.mark.parametrize("W,H", SIZES)
    def test_label_anchors_match_legacy(self, W, H):
        # Legacy: A at cx=mid//2, B at cx=mid+mid//2, org_y = text_h + 12.
        g = side_legend_geometry(SIDE_ON, W, H)
        mid = W // 2
        assert g["label_a"] == (mid // 2, 12)
        assert g["label_b"] == (mid + mid // 2, 12)

    def test_window_title_unchanged_for_side_on(self):
        assert win_name(SIDE_ON) == WIN_NAME
        assert win_name() == WIN_NAME

    def test_key_legend_unchanged_for_side_on(self):
        # The exact string previously hard-coded in play_and_prompt.
        assert key_legend_text(SIDE_ON) == (
            "A=left wins  B=right wins  N=not a rally (warm-up/junk)  "
            "S=skip unclear  R=replay  Q=quit")
        assert key_legend_text() == key_legend_text(SIDE_ON)


# ---------------------------------------------------------------------------
# end_on geometry — horizontal divider, A=near=bottom, B=far=top (ADR-0001).
# ---------------------------------------------------------------------------

class TestEndOnGeometry:
    @pytest.mark.parametrize("W,H", SIZES)
    def test_horizontal_divider_at_half_height(self, W, H):
        g = side_legend_geometry(END_ON, W, H)
        midy = H // 2
        assert g["divider"] == ((0, midy), (W, midy))

    @pytest.mark.parametrize("W,H", SIZES)
    def test_a_is_bottom_half_b_is_top_half(self, W, H):
        g = side_legend_geometry(END_ON, W, H)
        midy = H // 2
        assert g["rect_a"] == ((0, midy), (W, H))   # A = near player = bottom
        assert g["rect_b"] == ((0, 0), (W, midy))   # B = far player  = top

    @pytest.mark.parametrize("W,H", SIZES)
    def test_label_a_below_divider_label_b_above(self, W, H):
        g = side_legend_geometry(END_ON, W, H)
        midy = H // 2
        assert g["label_a"][1] >= midy   # A label in the bottom (near) half
        assert g["label_b"][1] < midy    # B label in the top (far) half

    def test_legend_text_names_near_and_far(self):
        txt = key_legend_text(END_ON)
        assert "A=near player wins" in txt
        assert "B=far player wins" in txt
        assert "left" not in txt and "right" not in txt

    def test_window_title_names_near_and_far(self):
        assert "A=near wins" in win_name(END_ON)
        assert "B=far wins" in win_name(END_ON)

    def test_invalid_orientation_rejected(self):
        for fn in (lambda: side_legend_geometry("diagonal", 100, 100),
                   lambda: win_name("diagonal"),
                   lambda: key_legend_text("diagonal")):
            with pytest.raises(ValueError):
                fn()


# ---------------------------------------------------------------------------
# Orientation resolution: override > trajectory field > sidecar > side_on.
# ---------------------------------------------------------------------------

class TestOrientationResolution:
    def test_fallback_is_side_on(self):
        assert resolve_labeler_orientation("vidX", traj_payload={}, sidecar={}) == SIDE_ON

    def test_sidecar_wins_over_fallback(self):
        assert resolve_labeler_orientation(
            "vidX", traj_payload={}, sidecar={"vidX": END_ON}) == END_ON

    def test_trajectory_field_wins_over_sidecar(self):
        assert resolve_labeler_orientation(
            "vidX", traj_payload={"orientation": END_ON},
            sidecar={"vidX": SIDE_ON}) == END_ON

    def test_override_wins_over_everything(self):
        assert resolve_labeler_orientation(
            "vidX", traj_payload={"orientation": END_ON},
            sidecar={"vidX": END_ON}, override=SIDE_ON) == SIDE_ON

    def test_invalid_override_rejected(self):
        with pytest.raises(ValueError):
            resolve_labeler_orientation("vidX", sidecar={}, override="diagonal")

    def test_select_sample_carries_orientation(self, tmp_path, monkeypatch):
        from hawkeye.annotate import holdout_label

        rally = {"rally_id": 1, "start_frame": 100, "end_frame": 340,
                 "trajectory": [{"f": 100 + i, "x": 0.5, "y": 0.5, "vis": True}
                                for i in range(241)]}
        (tmp_path / "vid_side.json").write_text(json.dumps(
            {"video": "vid_side", "fps": 30.0, "rallies": [rally]}))
        (tmp_path / "vid_end.json").write_text(json.dumps(
            {"video": "vid_end", "fps": 30.0, "orientation": END_ON,
             "rallies": [rally]}))

        monkeypatch.setattr(holdout_label, "TRAJ_DIR", tmp_path)
        monkeypatch.setattr(holdout_label, "resolve_video",
                            lambda vid: tmp_path / f"{vid}.mp4")

        picked = holdout_label.select_sample(n=10, seed=0, sidecar={})
        by_vid = {vid: orientation for vid, _r, _fps, orientation in picked}
        # End-on videos are SAMPLED (not excluded) and carry their orientation.
        assert by_vid == {"vid_side": SIDE_ON, "vid_end": END_ON}


# ---------------------------------------------------------------------------
# Holdout row schema: additive orientation field + old-row compatibility.
# ---------------------------------------------------------------------------

# Pre-ADR holdout row shape (exactly what main() wrote before this change).
OLD_ROWS = [
    {"video": "yt01", "rally_id": 3, "winner": "sideA",
     "annotator": "human_holdout", "split": "holdout",
     "timestamp": "2026-05-01T10:00:00Z"},
    {"video": "yt01", "rally_id": 7, "winner": "sideB",
     "annotator": "human_holdout", "split": "holdout",
     "timestamp": "2026-05-01T10:01:00Z"},
    {"video": "yt02", "rally_id": 1, "winner": "sideA",
     "annotator": "human_holdout", "split": "holdout",
     "timestamp": "2026-05-01T10:02:00Z"},
    {"video": "yt02", "rally_id": 4, "winner": "not_rally",
     "annotator": "human_holdout", "split": "not_rally", "not_rally": True,
     "timestamp": "2026-05-01T10:03:00Z"},
    {"video": "yt03", "rally_id": 2, "winner": "sideB",
     "annotator": "human_holdout", "split": "holdout",
     "timestamp": "2026-05-01T10:04:00Z"},
    {"video": "yt03", "rally_id": 9, "winner": "sideA",
     "annotator": "human_holdout", "split": "holdout",
     "timestamp": "2026-05-01T10:05:00Z"},
    {"video": "yt04", "rally_id": 5, "winner": "sideB",
     "annotator": "human_holdout", "split": "holdout",
     "timestamp": "2026-05-01T10:06:00Z"},
]


class TestHoldoutRowSchema:
    def test_new_rows_carry_orientation(self):
        rec = build_holdout_record("vidX", 3, "sideA", "human_holdout", END_ON)
        assert rec["orientation"] == END_ON
        assert rec["winner"] == "sideA"          # winner vocabulary unchanged
        assert rec["split"] == "holdout"
        rec2 = build_holdout_record("vidX", 4, "sideB", "human_holdout", SIDE_ON)
        assert rec2["orientation"] == SIDE_ON
        assert rec2["winner"] == "sideB"

    def test_not_rally_segregation_preserved(self):
        rec = build_holdout_record("vidX", 5, "not_rally", "human_holdout", END_ON)
        assert rec["not_rally"] is True
        assert rec["split"] == "not_rally"
        assert rec["orientation"] == END_ON

    def test_invalid_orientation_rejected(self):
        with pytest.raises(ValueError):
            build_holdout_record("vidX", 1, "sideA", "human_holdout", "diagonal")

    def test_old_seven_rows_parse_and_resume_skip(self, tmp_path):
        # The 7 pre-orientation rows must still parse into resume keys.
        path = tmp_path / "annotations_human_holdout.jsonl"
        path.write_text("\n".join(json.dumps(r) for r in OLD_ROWS) + "\n")
        done = _load_done(path)
        assert done == {(r["video"], r["rally_id"]) for r in OLD_ROWS}
        assert len(done) == 7

        # Resume filter (as in main()): every old row is skipped.
        sample = [(r["video"], {"rally_id": r["rally_id"]}, 30.0, SIDE_ON)
                  for r in OLD_ROWS]
        todo = [s for s in sample if (s[0], int(s[1]["rally_id"])) not in done]
        assert todo == []

    def test_mixed_old_and_new_rows_coexist(self, tmp_path):
        path = tmp_path / "annotations_human_holdout.jsonl"
        new_row = build_holdout_record("vid_end", 11, "sideA",
                                       "human_holdout", END_ON,
                                       timestamp="2026-06-09T00:00:00Z")
        rows = OLD_ROWS + [new_row]
        path.write_text("\n".join(json.dumps(r) for r in rows) + "\n")
        done = _load_done(path)
        assert len(done) == 8
        assert ("vid_end", 11) in done
        # Old rows are untouched by the new field (absent => side_on).
        parsed = [json.loads(l) for l in path.read_text().splitlines()]
        assert all("orientation" not in r for r in parsed[:7])
        assert parsed[7]["orientation"] == END_ON
