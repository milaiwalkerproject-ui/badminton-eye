# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-16 — MVP pivot)

**Current focus:** MVP — Installable iPhone Prototype with Auto-Suggest Scoring
**Driver:** Claude Code `/goal` command (not GSD). GSD `.planning/` history is preserved for context but not actively driving phases.

## Current Position

Phase: MVP-E — On-device validation (Phases A–D code complete; one model blocker remains before on-device demo)
Plan: See PROJECT.md → Phases A–E
Status:
- **Phase A (Strip down):** ✅ `AppMode.freeAppleIDMode` gates CloudKit, Apple Sign In, StoreKit, Live Activity, Watch sync. Entitlements stripped of paid capabilities.
- **Phase B (Continuous capture + calibration):** ✅ `CourtCalibrationView` runs at match start; `GameRecordingService` re-enabled (2026-05-21) — `startContinuousCapture` / `stopContinuousCapture` now actually call `recorder.startMatchRecording` / `stopMatchRecording` from `LiveMatchViewModel`.
- **Phase C (Real shuttle detector):** ⚠️ `TrackNetV3.mlpackage` is bundled and `TrackNetShuttleDetector` loads it, but it does NOT conform to `ShuttleDetecting` (windowed API). The suggestor below currently uses `CoreMLShuttleDetector` which looks for a `ShuttlecockDetector.mlmodelc` that is **not in the bundle**. See blockers.
- **Phase D (Rally-end suggestion loop):** ✅ `TrajectoryRallySuggestor` (2026-05-21) replaces `StubRallySuggestor` — pulls last ~2s from `CircularFrameBuffer`, runs `ShuttleDetecting`, fits trajectory via `TrajectoryCalculator`, maps landing into court space via `CalibrationProfile`, returns side + confidence (count + parabola-residual + distance-from-net, equal weights, clamped). Graceful fallback (coin-flip capped at 0.50) when calibration missing / buffer empty / < 2 detections. `RallySuggestionSheet` accepts an injected suggestor; `LiveMatchView` passes the real one from `LiveMatchViewModel`. Build on iPhone 17 sim: SUCCEEDED.
- **Phase E (On-device validation):** ⏳ Awaiting user — tether iPhone, free Apple ID install, calibrate court, play short rallies.

Outstanding blockers before Phase E will produce real (non-fallback) suggestions:
1. **Detector model mismatch.** `CoreMLShuttleDetector` expects `ShuttlecockDetector.mlmodelc`; bundle only ships `TrackNetV3.mlmodelc`. Options: (a) train/find a single-frame YOLO shuttlecock model named `ShuttlecockDetector` and add to `Resources/`; (b) write a `TrackNetWindowAdapter: ShuttleDetecting` that maintains a rolling 8-frame buffer + background + 288x512 preprocessing and adapts the windowed API to per-frame. Decision pending.
2. **Footage tab WIP** (`GameVideoRecord`, `FootageView`, `FootageDetailView`) is committed as standalone files but not registered in `ModelContainer` / `project.pbxproj`, and `PersistedMatch.gameVideos` relationship isn't added. Not on MVP critical path; defer until after Phase E proves the suggestion loop.

Last activity: 2026-05-21 — Phases B–D wired end-to-end; capture re-enabled; awaiting model decision for Phase E

Progress: [#####-----] 50% on MVP milestone — code path complete pending model + on-device test

## v2.0 history (paused, preserved for context)

### Features shipped before pivot

| PR | Feature |
|----|---------|
| #1  | L10n: register all .lproj/Localizable.strings in project.pbxproj |
| #2  | L10n: add missing voice-announcement keys to all 8 non-English locales |
| #3  | Privacy: add PrivacyInfo.xcprivacy manifest |
| #4  | Crash: safe ModelContainer init with in-memory fallback |
| #5  | Crash: safe JSONEncoder in SyncPayload (no try!) |
| #6  | Crash: eliminate fatalError in ResultFusionService |
| #7  | Release: bump CURRENT_PROJECT_VERSION to 2 |
| #8  | Watch: log and recover from WCSession sendMessage failures |
| #9  | Tests: add BadmintonEyeTests XCTest target |
| #10 | Docs: update v2.0 release notes |
| #11 | Watch: relay offline scoring intents on iPhone reconnect |
| #12 | Perf: defer persist/Watch sync; reposition score (>=48pt mid-top) |
| #13 | Infoplist: add ITSAppUsesNonExemptEncryption=NO |
| #14 | AppStore: App Store reviewer demo credentials |
| #15 | StoreKit: 7-day free trial introductory offer on yearly subscription |
| #17 | Tests: add LiveMatchPerformanceTests scoring throughput baseline |

## Performance Metrics

**Velocity:**
- Total plans completed: 26 (16 v1.0 + 8 v1.1 + 1 v1.12 + 1 v1.13)
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1-5 (v1.0) | 16 | — | — |
| 6-9 (v1.1) | 8 | — | — |
| 10-12 (v1.2) | 3 | — | — |
| 13-15 (v1.3) | 3 | — | — |
| 16-17 (v1.4) | 2 | — | — |
| 18 (v1.5) | 1 | — | — |
| 19-20 (v1.6) | 2 | — | — |
| 21-22 (v1.7) | 2 | — | — |
| 23-24 (v1.8) | 2 | — | — |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Carried forward from v1.0:

- SwiftData models use optional properties and defaults for CloudKit
- Placeholder Core ML shuttle detection (replaced in Phase 9 with real CoreMLShuttleDetector)
- Gaussian elimination homography solve (no external linear algebra)

v1.5 decisions:
- @MainActor on WatchMatchViewModel: explicit isolation matches actual runtime (WatchSessionManager already dispatches to @MainActor before calling onStateReceived)
- playReceiveHaptic skipped when wasLocallyUpdated: avoids double-haptic when Watch scores locally and iPhone echoes back confirmed state

v1.6 decisions:
- Not changing winner/loser service rule behavior: requires BWF rule verification; tests document current behavior (loser of prev game serves first)

v1.7 decisions:
- Doubles 3×15 and mixed doubles game-3 service are out of scope: same resetServiceForNewGame code path as singles; standard doubles covers the implementation

v1.13 decisions:
- Format string keys use `String(format: localization.localized("key"), arg)` pattern — no changes to LocalizationManager needed
- TrendRange rawValues changed to stable identifiers (last10/20/50); display name sourced via localizationKey property at render time

### Pending Todos

None.

### Blockers/Concerns

None.

## Session Continuity

Last session: 2026-03-31
Stopped at: v1.14 complete — all phases done
Resume file: None
