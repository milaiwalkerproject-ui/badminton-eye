# ADR-0001: Orientation-aware pipeline (both-angle support)

- **Status**: Accepted (user-approved 2026-06-09)
- **Context**: hawkeye offline pipeline (`hawkeye/`), fix #1 of the pipeline fix plan
- **Drivers**: end-on own footage (`IMG_4665..4668`) has trajectories but zero labels; every
  existing label and the shipped winner model assume a side-on camera.

## Context

The entire winner pipeline hardcodes a **side-on** camera: players separate left/right on
image-X, and the rally winner is decided by the `mean_x < 0.5 -> sideA` convention,
copy-pasted at four sites (`auto_annotate.classify_rally`, `holdout_eval._heuristic_winner`,
`export_shots._heuristic_winner`, and the synthetic-generator convention in
`winner_classifier.py`). End-on footage separates players **near/far on image-Y**, so under
the old code every end-on rally would be classified by lateral drift — garbage.

All 7 human holdout labels are side-on; the training annotations file is empty (the shipped
model is synthetic-trained). Nothing end-on has been labeled yet, so we can fix the geometry
before any contamination.

## Decision

### 1. One model, with normalization (not a second model)

We keep a single winner classifier and normalize features per orientation. End-on data is
too scarce for a second model, and the physics is the same signal on a different image axis.

### 2. Per-video orientation tag

- Sidecar `data/processed/orientation.json`: `{ "<video_id>": "side_on" | "end_on" }`.
- Optional top-level `orientation` field in trajectory JSON (written by
  `extract_rallies.py` going forward; explicit field > sidecar > default).
- **ABSENT means `side_on`** — every existing trajectory JSON, label file, and the 7-row
  holdout keep their meaning *by construction*. No existing JSON is rewritten; no label
  file changes.
- Resolution lives in one place: `hawkeye.orientation.resolve_orientation`.

### 3. Winner stays `sideA`/`sideB`, bound to a physical axis per orientation

| orientation | sideA | sideB | side axis |
|---|---|---|---|
| `side_on` | LEFT half | RIGHT half | image-X (unchanged, historical) |
| `end_on` | NEAR (bottom of frame) | FAR (top of frame) | image-Y |

`(winner, orientation)` together are unambiguous; stored labels never change vocabulary.
`export_shots` records the `orientation` on each shot record.

## Binding constraint (a): normalize ONLY the player-separation axis

**This is NOT a whole-coordinate 90° rotation.** In `winner_classifier.featurize`,
`apex_y = ys.min()` is a gravity/arc-height feature; rotating the whole frame would feed
horizontal spread into it and produce garbage. Only the *side-discriminating* coordinate is
remapped; all gravity/physics features keep RAW image coordinates in both orientations.

### The exact mapping (the ONE way, implemented in `hawkeye/src/hawkeye/orientation.py`)

```
canonical side coordinate:
  side_on:  side = x            (IDENTITY — historical convention preserved bit-for-bit)
  end_on:   side = 1.0 - y      (near/bottom: y≈1 → side≈0 < 0.5 → sideA
                                 far/top:     y≈0 → side≈1 ≥ 0.5 → sideB)

winner rule (single source of truth, all sites):  side < 0.5 → sideA, else sideB
```

The `1 - y` flip is what makes the historical `< 0.5 → sideA` rule keep working unchanged
for end-on (near maps to the "left-like" small side), so **no consumer of the convention
changes its comparison**.

### What uses which coordinate in `featurize(traj, orientation)`

| feature | coordinate |
|---|---|
| 16 samples, x-channel | canonical side axis (`x` / `1−y`) |
| 16 samples, y-channel | **raw image y** |
| `mean_last_x` | canonical side axis |
| `mean_last_y` | raw image y |
| `final_v` | raw image (x, y) deltas |
| `apex_y` | raw image y (`ys.min()`) |
| `length` | raw image (x, y) path |
| `gap_ratio` | frames only (orientation-free) |

`normalize_for_orientation(traj, orientation)` implements this: `side_on` returns the input
list unchanged (identity — self-tested); `end_on` sets `x := 1 − y` per point while
preserving raw `y` and keeping raw x as `img_x` for the physics features.

### Collapse of the 4 copy-pasted convention sites

All four sites now delegate to `hawkeye.orientation` (`side_coordinate`,
`winner_from_side_axis`, `tail_side_mean`, `heuristic_winner`), eliminating the silent-desync
risk. Equivalence with the old code for `side_on` is pinned by tests.

## Binding constraint (b): end-on inference is HARD-GATED on an end-on retrain

The shipped model has **never seen an end-on label** (it is synthetic-trained). It must
refuse/flag end-on input, not predict zero-shot:

- Model metadata gains `trained_orientations: [...]` in `RallyWinnerClassifier_meta.json`.
  - Written by `winner_classifier.main` from the **real** labeled dataset's orientations.
  - Synthetic training writes `["side_on"]` **always** — synthetic both-orientation toys do
    NOT open the gate; only a retrain on human end-on labels can put `"end_on"` there.
  - A meta file without the field (every pre-ADR model) means side-on only.
- `hawkeye.orientation.check_inference_gate(orientation, model_meta)`:
  - `side_on` → always allowed;
  - `end_on` → allowed only if `"end_on" ∈ trained_orientations`; otherwise the consumer
    **skips with a warning** (`holdout_eval` skips the rally and reports the skipped count;
    `export_shots --with-cv` leaves the cv vote `None` and reports the gated count).
- The heuristic (pure geometry, not a trained model) remains available for end-on via the
  shared orientation-aware helper, but produces heuristic-grade provenance only — never
  training-grade.

## Binding constraint (c): golden fixture order of operations

`hawkeye/tests/fixtures/featurize_golden.json`, generated by
`hawkeye/scripts/make_featurize_golden.py`:

- **`side_on` golden: created NOW** from a deterministic closed-form rally (no RNG). It pins
  the historical featurizer bit-for-bit (side_on normalization is the identity).
- **`end_on` golden: deliberately a TODO** until ONE hand-verified end-on rally exists (a
  human confirms near/far sides and the winner on real footage, after the cross-court mask
  fix #3 cleans the trajectory). It is then generated with
  `make_featurize_golden.py --end-on-traj <traj.json> --rally-id N --verified-by "<who/when>"`,
  which records the provenance. The fixture must be created AFTER this apex-axis
  implementation — never fabricated from synthetic data. The corresponding test skips with
  an explicit message until the entry is populated.

## Migration & safety

- `x < 0.5` convention + the 7 holdout labels preserved **by construction**: all are
  side-on; orientation defaults to side-on; side-on normalization is the identity
  (self-tested, including a verbatim-legacy-featurizer equality test); no JSON or label
  rewrites anywhere.
- Mislabeled orientation tag: default is the safe `side_on`; `end_on` requires explicit
  opt-in (sidecar entry or `--orientation end_on`); invalid values raise.
- Normalize-direction error: caught by the end-on mapping unit tests now and the
  hand-verified end-on golden fixture later.
- Labeler UIs (`annotate_rallies.py`, `holdout_label.py`) are explicitly out of scope of
  this change (concurrent work); they follow in a later wave using the same
  `hawkeye.orientation` module.

## Consequences

- End-on rallies can be extracted, tagged, heuristically annotated, and exported with
  correct side semantics today; **model** training/eval on end-on unlocks only after a
  retrain that includes real end-on labels flips `trained_orientations`.
- The synthetic generator now emits both orientations (correctly labeled through the same
  normalization), so the smoke model exercises the normalization path.
- Anyone adding a new side-decision site MUST use `hawkeye.orientation` — never reimplement
  `mean_x < 0.5`.

## Files

- `hawkeye/src/hawkeye/orientation.py` (new shared module: sidecar, mapping, convention
  helper, inference gate)
- `hawkeye/src/hawkeye/train/winner_classifier.py` (`normalize_for_orientation`,
  orientation-aware `featurize`, both-orientation synthetic, `trained_orientations` meta)
- `hawkeye/src/hawkeye/train/holdout_eval.py`, `hawkeye/src/hawkeye/train/export_shots.py`
  (shared helper, orientation threading, inference gate)
- `hawkeye/src/hawkeye/annotate/auto_annotate.py` (shared helper, orientation in rows)
- `hawkeye/src/hawkeye/preprocess/extract_rallies.py` (`--orientation`, sidecar, writes
  `orientation` field)
- `hawkeye/scripts/make_featurize_golden.py`, `hawkeye/tests/fixtures/featurize_golden.json`,
  `hawkeye/tests/test_orientation.py`
