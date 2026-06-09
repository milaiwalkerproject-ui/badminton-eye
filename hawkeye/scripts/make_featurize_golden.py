#!/usr/bin/env python
"""Generate the featurize golden fixture (hawkeye/tests/fixtures/featurize_golden.json).

ADR-0001 constraint (c): the fixture pins featurize()'s exact output so any
future change to the orientation normalization or feature engineering is
caught by tests/test_orientation.py::test_golden_fixture_side_on.

  side_on : generated NOW from a deterministic synthetic rally (this script,
            no args). Safe because side_on normalization is the identity —
            the fixture pins the historical featurizer behavior.
  end_on  : TODO — must be generated from ONE HAND-VERIFIED end-on rally
            (a real rally where a human confirmed which side is near/far and
            who won), AFTER reviewing this implementation. Until then the
            fixture stores a TODO marker and the end_on golden test skips.
            To generate:
              python hawkeye/scripts/make_featurize_golden.py \
                  --end-on-traj data/processed/trajectories/<video>.json \
                  --rally-id <id> --verified-by "<name, date, evidence>"

Usage:
    python hawkeye/scripts/make_featurize_golden.py            # (re)write side_on golden
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

HAWKEYE_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HAWKEYE_ROOT / "src"))

from hawkeye.orientation import SIDE_ON, END_ON  # noqa: E402
from hawkeye.train.winner_classifier import featurize  # noqa: E402

FIXTURE_PATH = HAWKEYE_ROOT / "tests" / "fixtures" / "featurize_golden.json"

END_ON_TODO = (
    "TODO (ADR-0001 constraint c): generate from ONE hand-verified end-on rally "
    "AFTER the apex-axis implementation is reviewed. Run this script with "
    "--end-on-traj/--rally-id/--verified-by. Do NOT fabricate this entry from "
    "synthetic data."
)


def deterministic_side_on_trajectory() -> list[dict]:
    """A fixed, seedless, closed-form side_on rally (no RNG -> stable forever)."""
    traj = []
    npts = 40
    for i in range(npts):
        t = i / (npts - 1)
        x = 0.85 - 0.6 * t + 0.03 * math.sin(7 * math.pi * t)   # right -> left (sideA wins)
        y = 0.55 - 0.35 * math.sin(math.pi * t) + 0.02 * math.cos(5 * math.pi * t)
        traj.append({"f": 3 * i, "x": round(x, 6), "y": round(y, 6),
                     "conf": 0.9, "vis": (i % 9 != 4)})  # a few invisible gaps
    return traj


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--end-on-traj", type=Path, default=None,
                    help="trajectory JSON of the HAND-VERIFIED end-on rally")
    ap.add_argument("--rally-id", type=int, default=None)
    ap.add_argument("--verified-by", default=None,
                    help="who hand-verified the rally (name, date, evidence)")
    args = ap.parse_args()

    fixture: dict = {}
    if FIXTURE_PATH.exists():
        fixture = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))

    # --- side_on golden (deterministic, generated now) ---
    traj = deterministic_side_on_trajectory()
    feats = featurize(traj, SIDE_ON)
    fixture["side_on"] = {
        "orientation": SIDE_ON,
        "source": "deterministic synthetic rally (make_featurize_golden.py)",
        "trajectory": traj,
        "features": [float(v) for v in feats],
    }

    # --- end_on golden (gated on a human-verified rally) ---
    if args.end_on_traj is not None:
        if args.rally_id is None or not args.verified_by:
            ap.error("--end-on-traj requires --rally-id and --verified-by "
                     "(the end_on golden MUST come from a hand-verified rally)")
        data = json.loads(args.end_on_traj.read_text(encoding="utf-8"))
        rally = next(r for r in data["rallies"] if int(r["rally_id"]) == args.rally_id)
        etraj = rally["trajectory"]
        efeats = featurize(etraj, END_ON)
        fixture["end_on"] = {
            "orientation": END_ON,
            "source": f"{data['video']}:r{args.rally_id} (hand-verified)",
            "verified_by": args.verified_by,
            "trajectory": etraj,
            "features": [float(v) for v in efeats],
        }
    elif "end_on" not in fixture or isinstance(fixture.get("end_on"), str) \
            or (isinstance(fixture.get("end_on"), dict) and "todo" in fixture["end_on"]):
        fixture["end_on"] = {"todo": END_ON_TODO}

    FIXTURE_PATH.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE_PATH.write_text(json.dumps(fixture, indent=2) + "\n", encoding="utf-8")
    print(f"[golden] wrote {FIXTURE_PATH}")
    print(f"[golden] side_on: {len(fixture['side_on']['features'])} features")
    print(f"[golden] end_on: "
          f"{'POPULATED' if 'features' in fixture.get('end_on', {}) else 'TODO (hand-verified rally required)'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
