"""Tests for hawkeye.preprocess.mask_courts (fix #3, post-filter only)."""
from __future__ import annotations

import json
import logging
from pathlib import Path

import pytest

from hawkeye.preprocess.mask_courts import (
    load_masks,
    mask_trajectory,
    point_in_quad,
    run,
    validate_quad,
)

# Axis-aligned quad for readable expectations; production quads are skewed
# perspective quads, covered by the non-axis-aligned test below.
SQUARE = [[0.2, 0.2], [0.8, 0.2], [0.8, 0.8], [0.2, 0.8]]
SKEWED = [[0.3, 0.1], [0.9, 0.3], [0.7, 0.9], [0.1, 0.7]]


def make_traj(points: list[dict], video: str = "vidA") -> dict:
    return {
        "video": video,
        "fps": 30.0,
        "rallies": [
            {"rally_id": 0, "start_frame": 7, "end_frame": 55,
             "trajectory": points},
        ],
    }


def pt(f: int, x: float, y: float, vis: bool = True, conf: float = 0.9) -> dict:
    return {"f": f, "x": x, "y": y, "conf": conf, "vis": vis}


# ---------------------------------------------------------------------------
# point_in_quad
# ---------------------------------------------------------------------------

class TestPointInQuad:
    def test_inside(self):
        assert point_in_quad(0.5, 0.5, SQUARE)

    @pytest.mark.parametrize("x,y", [
        (0.1, 0.5),   # left of quad
        (0.9, 0.5),   # right of quad
        (0.5, 0.1),   # above
        (0.5, 0.9),   # below
        (0.0, 0.0),   # far corner
        (1.0, 1.0),
    ])
    def test_outside(self, x, y):
        assert not point_in_quad(x, y, SQUARE)

    def test_edge_and_vertex_count_as_inside(self):
        # Shuttle on the court line is real play -> must NOT be blanked.
        assert point_in_quad(0.2, 0.5, SQUARE)   # on left edge
        assert point_in_quad(0.5, 0.2, SQUARE)   # on top edge
        assert point_in_quad(0.8, 0.8, SQUARE)   # on a vertex

    def test_skewed_quad(self):
        assert point_in_quad(0.5, 0.5, SKEWED)        # center
        assert not point_in_quad(0.15, 0.15, SKEWED)  # inside bbox, outside quad
        assert not point_in_quad(0.85, 0.85, SKEWED)


# ---------------------------------------------------------------------------
# validate_quad / load_masks
# ---------------------------------------------------------------------------

class TestValidation:
    @pytest.mark.parametrize("bad", [
        "nope",
        [[0.1, 0.1]] * 3,                       # 3 points
        [[0.1, 0.1], [0.2], [0.3, 0.3], [0.4, 0.4]],  # malformed point
        [[1.5, 0.1], [0.2, 0.2], [0.3, 0.3], [0.4, 0.4]],  # out of 0-1 range
    ])
    def test_rejects_bad_quads(self, bad):
        with pytest.raises(ValueError):
            validate_quad(bad, "v")

    def test_load_masks_rejects_non_object(self, tmp_path):
        p = tmp_path / "court_masks.json"
        p.write_text(json.dumps([SQUARE]))
        with pytest.raises(ValueError):
            load_masks(p)


# ---------------------------------------------------------------------------
# mask_trajectory: vis flip semantics
# ---------------------------------------------------------------------------

class TestMaskTrajectory:
    def test_outside_points_get_vis_false_inside_untouched(self):
        data = make_traj([
            pt(7, 0.5, 0.5),            # inside  -> stays vis=True
            pt(8, 0.05, 0.05),          # outside -> vis=False
            pt(9, 0.95, 0.5),           # outside -> vis=False
            pt(10, 0.3, 0.7),           # inside  -> stays vis=True
        ])
        _, total, flipped = mask_trajectory(data, SQUARE)
        vis = [p["vis"] for p in data["rallies"][0]["trajectory"]]
        assert vis == [True, False, False, True]
        assert (total, flipped) == (4, 2)

    def test_points_never_deleted_frames_and_fields_preserved(self):
        points = [pt(7, 0.05, 0.05, conf=0.63), pt(15, 0.5, 0.5, conf=0.71)]
        data = make_traj([dict(p) for p in points])
        mask_trajectory(data, SQUARE)
        traj = data["rallies"][0]["trajectory"]
        assert len(traj) == 2                                   # nothing deleted
        assert [p["f"] for p in traj] == [7, 15]                # indices intact
        assert [p["conf"] for p in traj] == [0.63, 0.71]        # conf untouched
        assert data["rallies"][0]["start_frame"] == 7           # rally bounds intact
        assert data["rallies"][0]["end_frame"] == 55

    def test_already_invisible_outside_point_not_counted_as_flip(self):
        data = make_traj([pt(7, 0.05, 0.05, vis=False)])
        _, total, flipped = mask_trajectory(data, SQUARE)
        assert (total, flipped) == (1, 0)
        assert data["rallies"][0]["trajectory"][0]["vis"] is False


# ---------------------------------------------------------------------------
# run(): end-to-end over a directory
# ---------------------------------------------------------------------------

@pytest.fixture()
def corpus(tmp_path: Path):
    in_dir = tmp_path / "trajectories"
    out_dir = tmp_path / "trajectories_masked"
    in_dir.mkdir()
    masked_vid = make_traj([pt(7, 0.5, 0.5), pt(8, 0.05, 0.05)], video="vidA")
    nomask_vid = make_traj([pt(3, 0.99, 0.99)], video="vidB")
    (in_dir / "vidA.json").write_text(json.dumps(masked_vid))
    (in_dir / "vidB.json").write_text(json.dumps(nomask_vid))
    masks = tmp_path / "court_masks.json"
    masks.write_text(json.dumps({"vidA": SQUARE}))
    return in_dir, out_dir, masks


class TestRun:
    def test_masked_output_written_to_new_dir(self, corpus):
        in_dir, out_dir, masks = corpus
        stats = run(in_dir, out_dir, masks)
        assert stats == {"files": 2, "masked": 1, "passthrough": 1,
                         "points": 2, "flipped": 1}
        out = json.loads((out_dir / "vidA.json").read_text())
        assert [p["vis"] for p in out["rallies"][0]["trajectory"]] == [True, False]

    def test_passthrough_without_mask_is_byte_identical_and_warns(
            self, corpus, caplog):
        in_dir, out_dir, masks = corpus
        with caplog.at_level(logging.WARNING, "hawkeye.preprocess.mask_courts"):
            run(in_dir, out_dir, masks)
        assert ((out_dir / "vidB.json").read_bytes()
                == (in_dir / "vidB.json").read_bytes())
        assert any("vidB" in r.message and "UNCHANGED" in r.message
                   for r in caplog.records)

    def test_originals_untouched(self, corpus):
        in_dir, out_dir, masks = corpus
        before = {p.name: p.read_bytes() for p in in_dir.glob("*.json")}
        run(in_dir, out_dir, masks)
        after = {p.name: p.read_bytes() for p in in_dir.glob("*.json")}
        assert before == after
        # And the outside point in the ORIGINAL is still vis=True.
        orig = json.loads((in_dir / "vidA.json").read_text())
        assert orig["rallies"][0]["trajectory"][1]["vis"] is True

    def test_missing_input_dir_raises(self, tmp_path):
        masks = tmp_path / "m.json"
        masks.write_text("{}")
        with pytest.raises(FileNotFoundError):
            run(tmp_path / "nope", tmp_path / "out", masks)
