# Full-Match Analysis — Wave 1 Plan (approved 2026-07-06)

Owner decision: **GO**. Goal: replace the fake/demo footage analysis with real
chunked, resumable, thermal/storage-guarded on-device TrackNet over full
20–30 min matches, and put **"Who won? A/B" rally labeling INTO the app** so
labeling is fully portable (no Mac).

The Overseer's `FULLMATCH-ANALYSIS-DESIGN.md` lives on the Mac Studio, NOT in
this repo. This plan was reconstructed from `HANDOFF.md` + a full code
inventory (workflow wf_51852ea5-766). Locked constraints from the handoff:

- Canonical frame index **`f = round(t × 30)`** (t = PTS seconds).
- Imported-video training exports tagged **`unmasked_import: true`** and
  **quarantined** until the video is court-masked.
- Winner stored as `sideA`/`sideB`; meaning bound by `(winner, orientation)`.
  side_on: A=left/B=right. end_on: A=near/B=far. End-on inference stays
  HARD-GATED until a retrain includes end-on labels (`meta.trained_orientations`).

## What exists (inventory summary)

- **Capture → storage** is solid: `GameRecordingService` records each game
  full-length (720p H.264) to `Application Support/Footage/<matchUUID>-game<N>.mp4`
  via `FootageWriter`; persisted as `GameVideoRecord` rows on
  `PersistedMatch.gameVideos` at game boundaries (`LiveMatchViewModel`).
- **Live-rally analysis is real**: bundled `TrackNetV3.mlpackage` +
  `TrackNetWindowAdapter` → `TrajectoryRallySuggestor` (+ `RallyWinnerClassifier`
  via `ClassifierRallyScorer`, image-space features, 0.92 gate) already run on
  the live 2 s window. Rally review UI exists (`RallyReviewView`) and a
  TrainingExport JSONL + reviewQueue already carry per-rally ClipRef time ranges.
- **The fake part**: full-match / challenge-flow analysis surfaces
  (`ChallengeVideoView` probes a nonexistent "ShuttlecockDetector" model,
  `HawkEyePipeline` has a placeholder sleep/random branch). Nothing analyzes a
  recorded match file end-to-end today.
- **Label contract** (hawkeye Python): `annotations_human_holdout.jsonl` — one
  JSON object per line; join key is `(video, rally_id)` where `video` is the
  trajectory JSON filename stem. In-app labels must reproduce
  `build_holdout_record`'s fields with `annotator: "in_app"`, plus per-video
  `orientation.json` entries. `hit_attribution_eval.py` reads
  `orientation.json`, the holdout JSONL, and `trajectories/<video>.json`.
- **Missing device plumbing**: no thermal/battery/storage guards anywhere; no
  batch TrackNet path (per-call MLMultiArray alloc + per-pixel Swift loops is
  too slow for ~36k frames/game); imports never persist as GameVideoRecord; no
  Swift orientation type.

## Phases (label-first — portable labeling is the trip's highest-value deliverable)

### Phase 1 — In-app labeler over LIVE-recorded matches (no new analyzer needed)
Rallies of live matches already have time ranges (TrainingExport/reviewQueue).
- A/B/N/S labeler screen: generalize `RallyReviewView`'s player (2 s display
  padding, orientation-aware A/B legend: end_on near/far, side_on left/right).
- Ask orientation once per match/video; persist it (new SwiftData field or
  sidecar — must be CloudKit-additive, i.e. optional/defaulted).
- Store labels (SwiftData row or app-support JSONL) keyed `(video, rally_id)`,
  `video` = GameVideoRecord.fileName stem — keeps the flywheel join + dedupe.
- Share-sheet export of `annotations_human_holdout.jsonl` (+`orientation.json`)
  in the exact Python schema, `annotator: "in_app"`.
- All new strings → 9 `.lproj` files. Tests for record building + export.

### Phase 2 — Chunked analyzer core
- `FullMatchAnalyzer` actor over `AVAssetReader`; stamp `f = round(PTS×30)`.
- Batch TrackNet path (reuse MLMultiArray, vImage/vDSP or CoreML batch
  prediction; consider temporal-median background — a full pass makes it cheap).
- Per-chunk checkpoint persisted BEFORE advancing (resume after kill).
- Guards: `ProcessInfo.thermalState` observer (pause ≥ .serious, resume ≤ .fair),
  `volumeAvailableCapacityForImportantUsage` precheck.
- Foreground-first with `isIdleTimerDisabled`; BGProcessingTask is stretch.
- Progress UI in FootageDetailView (or the unified MatchDetailView — see
  RESTRUCTURE-PLAN.md).

### Phase 3 — Rally segmentation + labeling over analyzed footage
- Port `detect_rallies` (gap 1.0 s / min 1.5 s) to Swift; optionally corroborate
  boundaries with `HitDetector.confidentRallyEnd` (phantom-serve fix landed
  2026-07-06 — prerequisite met).
- Feed segmented rallies into the Phase-1 labeler → ANY footage becomes
  labelable; export `trajectories/<video>.json` + `orientation.json` so
  `hit_attribution_eval` / `winner_classifier` consume them directly. This
  replaces the Studio-only TrackNet extraction step (HANDOFF §4 travel blocker).

### Phase 4 — Imports + provenance
- Imported video → Footage persistence (`GameVideoRecord` with an
  `isImported`/`unmaskedImport` flag, CloudKit-additive).
- Tag all derived exports `unmasked_import: true`; add Python-side quarantine in
  `export_shots.ingest_ondevice` / `build_training_set` (hold rows until the
  video appears in `court_masks.json`).

### Then (after wave 1 core)
- Replace demo Hawk Eye surfaces: point ChallengeVideoView at TrackNetV3 via a
  windowed-file adapter, delete HawkEyePipeline's placeholder branch, gate
  MultiAngleAnalysisView fusion on real results.

## Cross-cutting guardrails
- SwiftData: new properties optional/defaulted (CloudKit-additive), follow the
  GameVideoRecord pattern.
- Swift 6.1 (CI Xcode 16.4) strict concurrency: @unchecked Sendable + NSLock for
  capture-adjacent classes, @MainActor VMs, heavy CoreML/CIContext lazily off
  main (LazyRallyResultProducer precedent). No main-actor state in nonisolated
  closures.
- 9-locale strings for every new user-facing string.
- Storage lifecycle gap (multi-GB Footage, no cleanup UI) — track as follow-up.
- Don't touch `wanman-*` files / `.wanman/`.
