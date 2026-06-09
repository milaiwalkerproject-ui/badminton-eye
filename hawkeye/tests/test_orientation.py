"""Tests for ADR-0001: orientation-aware pipeline (both-angle support).

Covers the binding constraints:
  (a) only the player-separation axis is normalized to canonical X;
      apex/gravity features stay on raw image-Y in BOTH orientations;
      side_on normalization == IDENTITY.
  (b) end-on model inference is hard-gated until a model trained on real
      end-on labels exists.
  (c) featurize behavior is pinned by the golden fixture (side_on now;
      end_on TODO, gated on a hand-verified rally).
Plus: the shared convention helper is equivalent to the 4 historical
copy-pasted ``mean_x < 0.5 -> sideA`` sites for side_on.
"""
from __future__ import annotations

import json
import math
import random
from pathlib import Path

import numpy as np
import pytest

from hawkeye.orientation import (
    SIDE_ON, END_ON,
    side_coordinate, winner_from_side_axis, tail_side_mean, heuristic_winner,
    load_orientation_map, resolve_orientation,
    end_on_inference_allowed, check_inference_gate,
)
from hawkeye.train.winner_classifier import (
    featurize, normalize_for_orientation, synthetic_dataset, FEATURE_DIM, NUM_SAMPLES,
)

FIXTURE_PATH = Path(__file__).resolve().parent / "fixtures" / "featurize_golden.json"

# Feature vector layout (see winner_classifier.featurize):
IDX_MEAN_LAST_X = 2 * NUM_SAMPLES          # 32
IDX_MEAN_LAST_Y = IDX_MEAN_LAST_X + 1      # 33
IDX_FINAL_V = IDX_MEAN_LAST_X + 2          # 34
IDX_APEX_Y = IDX_MEAN_LAST_X + 3           # 35
IDX_LENGTH = IDX_MEAN_LAST_X + 4           # 36
IDX_GAP_RATIO = IDX_MEAN_LAST_X + 5        # 37


def make_traj(rng: random.Random, n: int = 40, end_x: float = 0.3,
              with_gaps: bool = True) -> list[dict]:
    traj = []
    start_x = 1 - end_x
    for i in range(n):
        t = i / (n - 1)
        x = start_x * (1 - t) + end_x * t + rng.gauss(0, 0.02)
        y = 0.5 - 0.4 * math.sin(math.pi * t) + rng.gauss(0, 0.02)
        vis = (not with_gaps) or rng.random() > 0.15
        traj.append({"f": 2 * i, "x": x, "y": y, "conf": 0.9, "vis": vis})
    return traj


# ---------------------------------------------------------------------------
# Constraint (a): side_on == identity
# ---------------------------------------------------------------------------

def test_normalize_side_on_is_identity_object():
    rng = random.Random(1)
    traj = make_traj(rng)
    assert normalize_for_orientation(traj, SIDE_ON) is traj  # the very same list


def test_featurize_side_on_identity_vs_legacy():
    """featurize(traj, 'side_on') must be bit-for-bit the historical featurizer."""

    def legacy_featurize(trajectory):  # verbatim pre-ADR-0001 implementation
        pts = [(float(p["x"]), float(p["y"]), int(p["f"]), bool(p.get("vis", True)))
               for p in trajectory]
        pts = [p for p in pts if p[3]]
        if len(pts) < 2:
            return np.zeros(FEATURE_DIM, dtype=np.float32)
        xs = np.array([p[0] for p in pts], dtype=np.float32)
        ys = np.array([p[1] for p in pts], dtype=np.float32)
        fs = np.array([p[2] for p in pts], dtype=np.float32)
        idx = np.linspace(0, len(pts) - 1, num=NUM_SAMPLES)
        lo = np.floor(idx).astype(int); hi = np.minimum(lo + 1, len(pts) - 1)
        frac = idx - lo
        sx = xs[lo] * (1 - frac) + xs[hi] * frac
        sy = ys[lo] * (1 - frac) + ys[hi] * frac
        samples = np.stack([sx, sy], axis=1).reshape(-1)
        last3 = pts[-3:]
        mean_last_x = float(np.mean([p[0] for p in last3]))
        mean_last_y = float(np.mean([p[1] for p in last3]))
        if len(pts) >= 4:
            dx = pts[-1][0] - pts[-4][0]
            dy = pts[-1][1] - pts[-4][1]
            df = max(1.0, pts[-1][2] - pts[-4][2])
            final_v = math.hypot(dx, dy) / df
        else:
            final_v = 0.0
        apex_y = float(ys.min())
        length = float(np.hypot(np.diff(xs), np.diff(ys)).sum())
        span = max(1.0, float(fs[-1] - fs[0]))
        gap_ratio = float(1.0 - (len(pts) / (span + 1.0)))
        extras = np.array([mean_last_x, mean_last_y, final_v, apex_y, length, gap_ratio],
                          dtype=np.float32)
        return np.concatenate([samples, extras]).astype(np.float32)

    rng = random.Random(42)
    for k in range(20):
        traj = make_traj(rng, n=rng.randint(5, 80), end_x=rng.choice([0.2, 0.3, 0.7, 0.8]))
        new = featurize(traj)                 # default orientation
        new_explicit = featurize(traj, SIDE_ON)
        old = legacy_featurize(traj)
        np.testing.assert_array_equal(new, old, err_msg=f"case {k}: default != legacy")
        np.testing.assert_array_equal(new_explicit, old, err_msg=f"case {k}: side_on != legacy")

    # degenerate: <2 visible points
    np.testing.assert_array_equal(featurize([], SIDE_ON), np.zeros(FEATURE_DIM, np.float32))


# ---------------------------------------------------------------------------
# Constraint (a): end_on mapping — side axis from image-Y, near -> sideA
# ---------------------------------------------------------------------------

def test_end_on_side_coordinate_mapping():
    near = {"x": 0.5, "y": 0.9}   # bottom of frame = near player
    far = {"x": 0.5, "y": 0.1}    # top of frame = far player
    assert side_coordinate(near, END_ON) == pytest.approx(0.1)   # < 0.5 -> sideA
    assert side_coordinate(far, END_ON) == pytest.approx(0.9)    # >= 0.5 -> sideB
    # side_on identity
    assert side_coordinate({"x": 0.27, "y": 0.9}, SIDE_ON) == pytest.approx(0.27)


def test_end_on_heuristic_near_far_winners():
    def end_on_traj(end_y: float, n: int = 30) -> list[dict]:
        # shuttle travels down-court: image y moves from 1-end_y toward end_y
        start_y = 1 - end_y
        return [{"f": i, "x": 0.5, "y": start_y + (end_y - start_y) * i / (n - 1),
                 "conf": 0.9, "vis": True} for i in range(n)]

    # rally ends at the BOTTOM (y~0.9) -> near side -> sideA
    assert heuristic_winner(end_on_traj(0.9), END_ON) == "sideA"
    # rally ends at the TOP (y~0.1) -> far side -> sideB
    assert heuristic_winner(end_on_traj(0.1), END_ON) == "sideB"
    # same trajectories under side_on read x=0.5 ties to sideB (historical >= rule)
    assert winner_from_side_axis(0.5) == "sideB"
    # too few visible points -> None
    assert heuristic_winner(end_on_traj(0.9)[:2], END_ON) is None


def test_end_on_featurize_side_axis_and_normalize():
    rng = random.Random(7)
    traj = make_traj(rng, n=30, with_gaps=False)
    norm = normalize_for_orientation(traj, END_ON)
    assert norm is not traj
    for p_raw, p_norm in zip(traj, norm):
        assert p_norm["x"] == pytest.approx(1.0 - p_raw["y"])   # canonical side axis
        assert p_norm["y"] == p_raw["y"]                         # raw image y untouched
        assert p_norm["img_x"] == pytest.approx(p_raw["x"])      # raw image x preserved
    # original trajectory not mutated
    assert "img_x" not in traj[0]

    feats = featurize(traj, END_ON)
    ys = np.array([p["y"] for p in traj], dtype=np.float32)
    # mean_last_x feature is the canonical side axis = mean(1 - y) of last 3
    assert feats[IDX_MEAN_LAST_X] == pytest.approx(float(np.mean(1.0 - ys[-3:])), abs=1e-6)
    # sample x-channel is the side axis: first sample == 1 - y[0]
    assert feats[0] == pytest.approx(1.0 - ys[0], abs=1e-6)
    # sample y-channel stays raw image y
    assert feats[1] == pytest.approx(ys[0], abs=1e-6)


# ---------------------------------------------------------------------------
# Constraint (a): apex/gravity/physics features invariant under orientation
# ---------------------------------------------------------------------------

def test_apex_and_physics_features_invariant_under_orientation():
    """Same raw image trajectory -> identical apex_y/final_v/length/mean_last_y/
    gap_ratio and identical y-sample channel in BOTH orientations. A naive 90°
    rotation would break every one of these."""
    rng = random.Random(123)
    for _ in range(10):
        traj = make_traj(rng, n=rng.randint(10, 60))
        fs_side = featurize(traj, SIDE_ON)
        fs_end = featurize(traj, END_ON)

        for idx, name in [(IDX_MEAN_LAST_Y, "mean_last_y"), (IDX_FINAL_V, "final_v"),
                          (IDX_APEX_Y, "apex_y"), (IDX_LENGTH, "length"),
                          (IDX_GAP_RATIO, "gap_ratio")]:
            assert fs_side[idx] == pytest.approx(fs_end[idx], abs=1e-6), name

        # y channel of the 16 samples (odd indices) identical
        np.testing.assert_allclose(fs_side[1:32:2], fs_end[1:32:2], atol=1e-6)

        # apex really is the raw-image arc height (min y of visible points)
        vis_y = [p["y"] for p in traj if p["vis"]]
        assert fs_end[IDX_APEX_Y] == pytest.approx(min(vis_y), abs=1e-6)


# ---------------------------------------------------------------------------
# Shared convention helper == the 4 historical copy-paste sites (side_on)
# ---------------------------------------------------------------------------

def _old_heuristic_winner(trajectory):  # verbatim holdout_eval/export_shots pre-ADR
    vis = [p for p in trajectory if p.get("vis", True)]
    if len(vis) < 3:
        return None
    last = vis[-5:]
    mean_x = sum(float(p["x"]) for p in last) / len(last)
    return "sideA" if mean_x < 0.5 else "sideB"


def test_shared_helper_equivalent_to_old_sites_side_on():
    rng = random.Random(99)
    cases = [make_traj(rng, n=rng.randint(2, 50), end_x=rng.uniform(0.1, 0.9))
             for _ in range(50)]
    cases.append([])  # empty
    for traj in cases:
        assert heuristic_winner(traj, SIDE_ON) == _old_heuristic_winner(traj)

    # the thin wrappers in the consumers delegate to the shared helper
    from hawkeye.train import holdout_eval, export_shots
    for traj in cases:
        assert holdout_eval._heuristic_winner(traj) == _old_heuristic_winner(traj)
        assert export_shots._heuristic_winner(traj) == _old_heuristic_winner(traj)


def test_auto_annotate_classify_rally_side_on_unchanged_and_end_on_aware():
    from hawkeye.annotate.auto_annotate import classify_rally

    rng = random.Random(5)
    traj = make_traj(rng, n=30, end_x=0.25, with_gaps=False)
    winner, ev = classify_rally({"trajectory": traj})            # default side_on
    # old behavior: mean of last-5 x < 0.5 -> sideA
    mean_x = sum(p["x"] for p in traj[-5:]) / 5
    assert winner == ("sideA" if mean_x < 0.5 else "sideB")
    assert ev["orientation"] == SIDE_ON

    # end_on: vertical rally ending at bottom -> near -> sideA
    end_traj = [{"f": i, "x": 0.5, "y": 0.1 + 0.8 * i / 29, "conf": 0.9, "vis": True}
                for i in range(30)]
    winner, ev = classify_rally({"trajectory": end_traj}, END_ON)
    assert winner == "sideA"
    assert ev["orientation"] == END_ON
    assert ev["mean_side"] < 0.5


# ---------------------------------------------------------------------------
# Constraint (b): end-on inference hard gate
# ---------------------------------------------------------------------------

def test_end_on_inference_gate():
    # no meta / legacy meta (the shipped synthetic-trained model) -> BLOCKED
    assert end_on_inference_allowed(None) is False
    assert end_on_inference_allowed({}) is False
    assert end_on_inference_allowed({"synthetic": True}) is False
    assert end_on_inference_allowed({"trained_orientations": ["side_on"]}) is False
    # only a model trained WITH end-on labels opens the gate
    assert end_on_inference_allowed({"trained_orientations": ["end_on", "side_on"]}) is True

    # side_on inference is never gated
    assert check_inference_gate(SIDE_ON, None) is True
    assert check_inference_gate(SIDE_ON, {"trained_orientations": ["side_on"]}) is True
    # end_on blocked until the flag exists
    assert check_inference_gate(END_ON, None) is False
    assert check_inference_gate(END_ON, {"trained_orientations": ["side_on"]}) is False
    assert check_inference_gate(END_ON, {"trained_orientations": ["side_on", "end_on"]}) is True

    with pytest.raises(ValueError):
        check_inference_gate("diagonal", None)


# ---------------------------------------------------------------------------
# Orientation resolution: sidecar + trajectory field, absent => side_on
# ---------------------------------------------------------------------------

def test_orientation_resolution(tmp_path):
    # missing sidecar -> empty map -> side_on default
    assert load_orientation_map(tmp_path / "nope.json") == {}
    assert resolve_orientation("vid1", sidecar={}) == SIDE_ON

    sidecar_path = tmp_path / "orientation.json"
    sidecar_path.write_text(json.dumps({"IMG_4665": "end_on", "yt_abc": "side_on"}))
    m = load_orientation_map(sidecar_path)
    assert m == {"IMG_4665": "end_on", "yt_abc": "side_on"}
    assert resolve_orientation("IMG_4665", sidecar=m) == END_ON
    assert resolve_orientation("unknown", sidecar=m) == SIDE_ON

    # explicit trajectory-JSON field wins over the sidecar
    assert resolve_orientation("IMG_4665", traj_payload={"orientation": "side_on"},
                               sidecar=m) == SIDE_ON
    # absent field falls through to the sidecar
    assert resolve_orientation("IMG_4665", traj_payload={"video": "IMG_4665"},
                               sidecar=m) == END_ON

    # invalid values rejected
    bad = tmp_path / "bad.json"
    bad.write_text(json.dumps({"v": "diagonal"}))
    with pytest.raises(ValueError):
        load_orientation_map(bad)
    with pytest.raises(ValueError):
        resolve_orientation("v", traj_payload={"orientation": "diagonal"}, sidecar={})


# ---------------------------------------------------------------------------
# Synthetic generator: both orientations, correctly labeled
# ---------------------------------------------------------------------------

def test_synthetic_dataset_emits_both_orientations_correctly_labeled():
    X, y = synthetic_dataset(60, seed=3)
    assert X.shape == (60, FEATURE_DIM)
    # After normalization the canonical tail side axis must agree with the
    # label in BOTH orientations (mean_last_x < 0.5 <=> sideA/label 0).
    side_tail = X[:, IDX_MEAN_LAST_X]
    agree = ((side_tail < 0.5) == (y == 0)).mean()
    assert agree >= 0.9, f"labels disagree with canonical side axis: {agree:.2f}"
    # both label classes present
    assert {0, 1} <= set(int(v) for v in y)


# ---------------------------------------------------------------------------
# Constraint (c): golden fixture
# ---------------------------------------------------------------------------

def test_golden_fixture_side_on():
    fixture = json.loads(FIXTURE_PATH.read_text())
    g = fixture["side_on"]
    assert g["orientation"] == SIDE_ON
    feats = featurize(g["trajectory"], SIDE_ON)
    np.testing.assert_allclose(feats, np.array(g["features"], dtype=np.float32),
                               rtol=0, atol=1e-7)


def test_golden_fixture_end_on_todo_or_verified():
    """end_on golden is gated on a HAND-VERIFIED rally (ADR-0001 constraint c)."""
    fixture = json.loads(FIXTURE_PATH.read_text())
    g = fixture["end_on"]
    if "features" not in g:
        assert "todo" in g  # documented TODO marker, never silently absent
        pytest.skip("end_on golden pending a hand-verified end-on rally "
                    "(scripts/make_featurize_golden.py --end-on-traj ...)")
    assert g.get("verified_by"), "end_on golden must record who hand-verified it"
    feats = featurize(g["trajectory"], END_ON)
    np.testing.assert_allclose(feats, np.array(g["features"], dtype=np.float32),
                               rtol=0, atol=1e-7)
