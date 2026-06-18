# Reel-Parity & Trust Roadmap

**Created:** 2026-06-18 · **Status:** proposed (pre-implementation) · **Owner:** milaiwalker

## Provenance

A June 2026 Instagram reel (@girsta) claimed Claude Opus 4.8 "one-shot" an app that **tracks the
shuttle, keeps score, and measures shot speed in real time**. An 8-agent audit of this repo +
CV-literature research (workflow run `wf_e1081f35-9b2`) established what that app's CV models really
are and how this repo already compares. This roadmap turns that analysis into sequenced, buildable work.

**The "one-shot" claim is marketing.** Real shuttle tracking needs pretrained TrackNet weights + tens
of thousands of labeled frames. We will not out-*model* the reel — we already ship the same SOTA
tracker. **We out-*measure* it:** publish a real accuracy number, ship a calibrated speed with an honest
error band, and move scoring to the robust serve-rule method.

## Baseline — what already ships (do NOT rebuild)

| Capability | Status | Where |
|---|---|---|
| Shuttle tracking | ✅ TrackNetV3 heatmap CNN, on-device (ANE) + Python | `TrackNetShuttleDetector.swift`, `TrackNetWindowAdapter.swift`, `hawkeye/.../preprocess/extract_rallies.py` |
| Rally → winner suggestion | ✅ trajectory fit → side + confidence, 0.92 auto-apply gate | `TrajectoryRallySuggestor.swift`, `ClassifierRallyScorer.swift`, `TrajectoryCalculator.swift`, `LiveMatchViewModel.swift` |
| Scorekeeping (rules) | ✅ pure-Swift BWF state machine | `ScoringEngine/` (SwiftPM, 143/143 tests) |
| Court calibration | ✅ manual 4-corner tap → homography to normalized [0,1] | `CourtCalibrationView.swift`, `CalibrationProfile.swift` |
| Continuous capture + 2s buffer | ✅ 60/30 fps capture, ~5 fps decimated ring | `GameRecordingService.swift`, `CircularFrameBuffer.swift` |

Current GSD position (`STATE.md`): MVP Phase E — on-device validation, awaiting iPhone tether + free
Apple ID install + calibrate + play rallies. **F2's offline accuracy metric is independent of Phase E** —
it runs in the Python pipeline on real rallies already sitting in `labeling-bundle/` (no phone, no Studio).
The phone is only needed for *end-to-end on-device* validation, which is a separate, broader check.

## The three real gaps (this is the work)

1. **Shot speed has no physical-unit path** — only `final_velocity` (px/frame, a classifier feature),
   never converted to km/h or shown; homography is image→normalized, not image→meters; capture
   decimates to ~5 fps so smash-peak is uncapturable.
2. **Real accuracy is UNMEASURED** — holdout = 7 *synthetic* side-on rallies; shipped classifier is
   synthetic-trained; the 0.92 gate is a guess. (`HANDOFF.md` §3 says so.)
3. **Winner inference uses the hard method** — trajectory/landing-side (the monocular in/out problem)
   instead of the robust serve-rule method ("next server won the last point" + serve-side parity). No
   serve detector, no player/pose tracking.

## Reel teardown — what the demo actually runs (observed 2026-06-18)

The reel video was downloaded (`yt-dlp`) and inspected frame-by-frame (`/tmp/reel.mp4`, 32.5 s, 720×1280, 30 fps).
A burnt-in `frame N` counter proves it is an **offline batch-processing script**, not a live app. Over a single
side-on camera it renders a full multi-model pipeline:

- **Player detection + identity** (`P0`/`P1` boxes → names MAY/MAL) · **player pose** (skeletons) ·
  **TrackNet-family shuttle track** (yellow arc) · **hit detection** (`shots:` counter + comic words at each
  contact) · **top-down homography minimap** (`TOP VIEW`) · **rally state machine** (`IN PLAY 0.7s…` vs
  `— between rallies —`) · **shot speed** (`8–12 m/s`).
- **It genuinely auto-scores:** the board moved on its own, correctly — `10:8 → 10:9 → 11:9` — with rally-end
  detection and a shot-counter reset between points.

**Takeaways:** (1) the robust auto-scoring path is **track the rally structure (hits + players), not classify a
trajectory blob** — strong validation of the F3 direction; (2) the displayed speeds (8–12 m/s for "smashes",
≈30–43 km/h) are physically far too low → speed is the **cosmetic** layer, re-confirming F1's value is the
*feature repair*, not the readout; (3) it's offline + GPU — doing this **live on-device** is the real lift we'd
own; (4) no accuracy number shown — adopting the approach still needs F2 to trust it.

**Keystone extracted → FK below:** the highest-leverage, cheapest-to-adopt piece is **hit detection off our
existing shuttle trajectory** (no new model) → auto rally-segmentation + last-hit winner attribution.

---

# Features

> Recommended order is now **FK → F2 → F1 → F3** — FK (hit detection) is the keystone the reel revealed: it needs
> no new model, replaces the manual "Rally Ended" tap, and gives a more robust winner signal than today's
> trajectory classifier. F1/F2/F3 keep their original numbering and remain independently specced.

## FK — Hit detection & rally state (keystone)  ·  *the reel's real lesson; no new model*

**Goal:** read hit/stroke events off the EXISTING tracked shuttle trajectory to (a) count shots, (b) auto-detect
rally end (replace the manual "Rally Ended" tap with an `in-play` / `between-rallies` state machine), and (c)
attribute the LAST hit to a side — a more robust winner signal than the current trajectory classifier.

**Why it leads:** the reel teardown showed auto-scoring works by tracking rally STRUCTURE (hits → who hit last),
not by classifying a trajectory shape. We already produce the shuttle trajectory, so v1 needs **no new ML model** —
a hit is a turning point where the shuttle reverses along the inter-player (canonical side) axis. Cheapest path to
materially better auto-scoring, and the foundation serve-rule scoring (F3) builds on.

**Design:** specced via workflow `wf_53967582-90e` (literature + repo-grounding + first-principles → one spec).
Core signal: local extrema of the side-axis coordinate over time (smoothed, min-separation guarded); rally-end =
sustained no-hit / track settle. Lives alongside `TrajectoryCalculator`/`ShotSpeed`, deterministic + unit-tested.

**Depends on:** nothing new — the live trajectory already exists. **Coupling:** last-hit attribution can feed /
cross-check the F2 winner metric, and being pure geometry it's measurable offline on `labeling-bundle/` rallies too.

**Status (2026-06-18):** ✅ v1 implemented + tested — `BadmintonEye/.../Services/HitDetector.swift`
(`SideAxisTurningPointHitDetector`) + **10 unit tests passing** (`HitDetectorTests`), app builds clean.
Testing caught a real bug (approach-speed was sampled AT the turn, where a clear's apex velocity ≈ 0 → real
strokes wrongly rejected; now uses the incoming-arc PEAK speed). Also: the spec's hitter→side prose was inverted
vs its own test cases — implemented per the physically-correct cases (reversal toward far baseline ⇒ far player
`.sideA`). ⏳ Not yet wired into the live rally path (`TrajectoryRallySuggestor` for last-hit attribution / shot
count; `LiveMatchViewModel` for auto rally-end) — that wiring is the next step.

## F1 — Calibrated shuttle velocity  ·  *primarily a scoring-feature repair; km/h is a byproduct*

**Reframed 2026-06-18 (why we build this for an auto-scoring app, not for reel-parity):** the rally-winner
classifier already depends on a speed feature — `final_velocity` — and it is the single most broken input.
It is computed in normalized-image-units per *frame index* (`winner_classifier.py:128`,
`ClassifierRallyScorer.swift:236`), so it is camera-framing-dependent AND frame-rate-dependent. That is the
documented TRAIN/SERVE skew (`ClassifierRallyScorer.swift:48–53`) and the reason the auto-apply gate is pinned
at a conservative 0.92.

**Goal:** produce a *calibrated, frame-rate-independent* shuttle velocity — metres (via the known court
rectangle) ÷ real seconds (via frame timestamps, already on every buffered frame) — and make it the
classifier's speed feature. This repairs the one signal blocking train→device transfer, which lets the 0.92
gate relax → the app auto-scores more often and more correctly. **The km/h readout is a free byproduct of the
same computation, not the goal.**

**Coupling to F2:** swapping the feature's definition requires retraining the classifier (Python featurize) +
matching the Swift port + golden fixture, then re-measuring on the real holdout. **F1's scoring payoff is
inseparable from F2** — build the velocity now, validate the gate change with F2.

**Honest limits:** court-plane speed ignores shuttle height (a lower bound on true 3-D speed); a smash peak
needs ~120–240 fps to capture. So the km/h readout stays labelled "approx" until F1.3 (high fps) lands. The
*classifier feature* benefits from the time-base fix even before high fps.

### Phase F1.1 — Metric calibration scale
- Extend `CalibrationProfile` to store a real-world length: user taps two points on a known court line
  (e.g. a 6.10 m back boundary, or the 3.96 m service line) at impact depth → derive `metersPerPixel`.
- `TrajectoryCalculator.computeHomography()` already yields image→court[0,1]; add an image→meters scale
  anchored on that known length. Persist court metric constants (13.40 × 6.10 m; net 1.55 m).
- **Files:** `CalibrationProfile.swift`, `CourtCalibrationView.swift`, `TrajectoryCalculator.swift`.
- **Accept:** a tap-measured 6.10 m line back-computes to 6.10 ± 0.15 m from the stored scale on 5 test calibrations.

### Phase F1.2 — Speed computation
- From the post-impact shuttle track, compute `v = ‖Δpixel‖ / Δt · metersPerPixel · 3.6` km/h over the
  first 2–4 clean frames (peak-off-racket), per the validated arxiv method (2509.05334).
- Reuse / promote the existing `final_velocity` math in `ClassifierRallyScorer.swift` but in real units
  and at full frame-rate (not the 5 fps decimated path).
- **Honesty guards:** reject/flag cross-court shots (track not parallel to the calibration line — they are
  underestimated and unfixable monocularly); require ≥3 detections; output a ± band from track residual.
- **Files:** `ClassifierRallyScorer.swift` / new `ShotSpeedEstimator.swift`, `TrajectoryCalculator.swift`.
- **Accept:** speed within ±15% of a radar/second-source on ≥10 in-plane smashes; cross-court shots flagged, not shown as exact.

### Phase F1.3 — High-fps capture path (dependency for accuracy of F1.2)
- `GameRecordingService` already prefers 60 fps; add a **120 fps (1080p) / 240 fps (720p)** capture mode
  for the speed path, and **verify true sensor fps from file metadata** (some slo-mo is interpolated).
- Stop decimating the *speed* window to 5 fps (keep decimation only for the winner path). Persist
  fps/resolution/codec with each clip.
- **Files:** `GameRecordingService.swift`, `CircularFrameBuffer.swift`, clip metadata model.
- **Accept:** speed window runs at ≥120 true fps; clip metadata records actual fps.

### Phase F1.4 — UI
- Show speed on the rally/replay UI with the location label ("peak, off racket") + uncertainty band.
- **Files:** `RallySuggestionSheet` / `LiveMatchView` / `TrajectoryReplayView.swift`.
- **Accept:** speed + band + location render on a real rally; absent gracefully when calibration missing.

**Effort:** ~1–1.5 weeks · **Depends on:** F1.3 for trustworthy numbers · **Risk:** monocular depth ceiling (mitigated by in-plane-only + 3D backlog item).

**Status (2026-06-18):** ✅ foundation landed — `ShotSpeed` + `TrajectoryCalculator.shotSpeed(courtPoints:timestamps:)`
(calibrated metres ÷ real seconds), **9 unit tests passing** (`BadmintonEyeTests/ShotSpeedTests`), app builds clean.
⏳ Not yet wired into the live rally path or the classifier feature — that swap is the F2-coupled scoring payoff
(retrain on real holdout + match the Swift featurizer + golden fixture, then relax the 0.92 gate).

## F2 — Measured accuracy & calibrated confidence  ·  *cheap, foundational, completes Phase E*

**Goal:** replace "unverified like the reel" with a *published* rally-winner accuracy number on real
footage, and make the 0.92 gate mean something. Closes gap #2.

### Phase F2.1 — Real labeled holdout
- Label ~250 real rallies. **The data is already on this MacBook** — `labeling-bundle/` holds the user's own
  pre-extracted end-on rallies (IMG_4665–4668) queued for offline labeling; trajectories are already computed,
  so labeling + eval run on the MacBook CPU with **no phone and no Studio**.
- **Files:** labeling-bundle tooling, `hawkeye/.../train/build_training_set.py`.
- **Accept:** ≥250 human-labeled real rallies in the holdout JSONL; side-on and (stretch) end-on covered.

### Phase F2.2 — Run + publish eval
- Run `hawkeye/.../train/holdout_eval.py` on the real holdout; record accuracy + confusion matrix vs the
  heuristic baseline. Retrain the classifier on real (not synthetic) labels.
- **Files:** `holdout_eval.py`, `winner_classifier.py`, `export_shots.py`.
- **Accept:** a committed report with real accuracy + confusion matrix; classifier retrained on real data.

### Phase F2.3 — Calibrate the confidence gate
- **Build** `calibrate_confidence.py` (temperature scaling) — it is referenced in `HANDOFF.md` but **not
  present** in `hawkeye/train/`. Re-derive the auto-apply threshold from measured reliability instead of
  the hardcoded 0.92.
- **Files:** new `hawkeye/.../train/calibrate_confidence.py`, gate constant in `ClassifierRallyScorer.swift`.
- **Accept:** gate threshold is data-derived; calibration curve committed; auto-applied calls match target precision.

### Phase F2.4 — End-on support
- Collect human end-on labels, retrain with `trained_orientations` updated, and **port the orientation-aware
  featurizer to Swift** (on-device currently has no orientation concept; ADR-0001). Enforce the meta gate on device.
- **Files:** `winner_classifier.py`, `hawkeye/.../orientation.py`, on-device featurizer, `docs/adr/0001-*`.
- **Accept:** end-on inference ungated only when a real end-on-trained model is present; measured end-on accuracy reported.

**Effort:** ~3–6 days (F2.1–F2.3) + end-on pass · **Depends on:** nothing external — holdout rallies are already
in `labeling-bundle/`; all compute is the small offline Python pipeline (MLP train + eval), runnable on the MacBook
now. **The phone is NOT required for this metric.** · **Risk:** circular labels (break via human overrides only);
offline accuracy ≠ on-device accuracy — the on-device path has a coarser background frame, decimated fps, and no
orientation featurizer, so measure those separately during on-device validation.

## F3 — Serve-rule scoring + on-device pose  ·  *biggest correctness upgrade*

**Goal:** infer the rally winner from badminton's rules, not from fragile monocular landing calls. Closes gap #3.

### Phase F3.1 — On-device pose
- Add a pose model via CoreML — **MoveNet/BlazePose** (lightest) or **RTMPose-s**. Single-person tuned;
  handle doubles / identity-swap explicitly.
- **Accept:** per-frame player keypoints on device at ≥15 fps; identity stable across a rally.

### Phase F3.2 — Serve detection + player identity
- Detect serve (shuttle direction-reversal fused with player swing/pose); track which player served.
- **Accept:** serve detected with ≥90% recall on a labeled clip set; server identity correct ≥90%.

### Phase F3.3 — Rule-based scorer + correction UI
- Infer winner from "next server won the last point" + serve-side parity, re-anchored by periodic user
  confirmation. Keep the trajectory classifier as a **second vote** (wire the System-1/System-2 design).
- Add a **tap-to-fix-a-point** correction so the deterministic scorer degrades gracefully and re-anchors.
- **Files:** `LiveMatchViewModel.swift`, scorer services, `ScoringEngine/` integration, live UI.
- **Accept:** full-game score tracked from video with ≤1 manual correction per game on test footage.

**Effort:** ~2–3 weeks · **Depends on:** F3.1 → F3.2 → F3.3 in order · **Risk:** doubles identity tracking is hard; ship singles first.

---

## Recommended sequencing

1. **F2 first.** Cheapest, highest-credibility, and **unblocked right now** — the real holdout rallies are
   already in `labeling-bundle/` and the whole metric is offline Python (no phone, no Studio). It also produces
   the labeled real-rally dataset that F1 (speed ground-truth) and F3 (serve/winner training) both lean on.
   (Separately, end-to-end on-device validation — Phase E — does need the tethered iPhone, but that's a later,
   broader check.)
2. **F1 second.** The visible reel-parity win; F1.3 (high fps) is a prerequisite for a trustworthy number,
   so budget it inside F1.
3. **F3 third.** The largest effort and the deepest correctness gain; do it once accuracy is measured so
   you can prove the upgrade with numbers.

> Quick-win cluster if you want momentum: F2.1+F2.2 (measure) and F1.1+F1.2 (speed math) can land in the
> same week and together flip the app from "demo like the reel" to "verified, beats the reel."

## Backlog — differentiators the reel doesn't even claim (post F1–F3)

- **Shot-type classification** (clear/drop/smash/net/lift/serve). MVP: LSTM/temporal over pose + track
  (~85–90%). Stretch: reproduce **BST** (RTMPose + TrackNetV3 + court position) on **ShuttleSet** (92.7% top-2).
- **Automatic court detection** — court-keypoint heatmap CNN → homography (à la `TennisCourtDetector`),
  killing manual-calibration error. Fork **SoloShuttlePose** (MIT) as the integration skeleton.
- **3D speed for angled shots** — MonoTrack-style reconstruction (~8 cm error) so cross-court smashes
  aren't underestimated; or optional two-phone stereo. Report peak-off-racket *and* speed-at-net.
- **Tracker upgrade (optional)** — HRNet/WASB backbone or TrackNetV4 motion-attention if occlusion recall
  limits you. Lowest priority — the detector is not the bottleneck.
- **Continuous live tracking** — run TrackNet during play, not only on the post-rally buffer (needs
  thermal/storage guards; `FULLMATCH-ANALYSIS-DESIGN.md` Phase 2).

## Cross-cutting physics constraints (cannot be engineered away)

- **Temporal sampling:** a smash leaves the racket at ~110–155 m/s → need 120–240 fps to catch peak.
- **Monocular depth ambiguity:** a single camera measures only the in-plane velocity component.
- **Speed needs a location:** a shuttle halves its speed ~every 3.35 m; always state where the number was measured.

## Sources

- TrackNetV2 — ieeexplore.ieee.org/document/9302757 · TrackNetV3 — github.com/qaz812345/TrackNetV3,
  dl.acm.org/doi/fullHtml/10.1145/3595916.3626370
- Mobile smash-speed (YOLOv5 + planar scale) — arxiv.org/html/2509.05334v1
- Rally segmentation / player-ID (serve-rule) — arxiv.org/abs/1712.08714
- Shot-type / BST + ShuttleSet — arxiv.org/html/2502.21085v2, arxiv.org/abs/2306.04948
- Court detection — github.com/yastrebksv/TennisCourtDetector · SoloShuttlePose — github.com/sunwuzhou03/SoloShuttlePose
- 3D reconstruction — MonoTrack arxiv.org/abs/2204.01899 · Shipping reference — swing.vision
- Full analysis: workflow run `wf_e1081f35-9b2`; memory `cv-architecture-and-gaps`.
