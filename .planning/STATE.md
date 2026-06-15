# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-16 — MVP pivot)

**Current focus:** MVP — Installable iPhone Prototype with Auto-Suggest Scoring
**Driver:** Claude Code `/goal` command (not GSD). GSD `.planning/` history is preserved for context but not actively driving phases.

## Current Position

Phase: MVP-E — On-device validation (Phases A–D code complete; pipeline live, awaiting physical-device test pass)
Plan: See PROJECT.md → Phases A–E
Status:
- **Phase A (Strip down):** ✅ `AppMode.freeAppleIDMode` gates CloudKit, Apple Sign In, StoreKit, Live Activity, Watch sync. Entitlements stripped of paid capabilities.
- **Phase B (Continuous capture + calibration):** ✅ `CourtCalibrationView` runs at match start; `GameRecordingService` re-enabled — `startContinuousCapture` / `stopContinuousCapture` call `recorder.startMatchRecording` / `stopMatchRecording` from `LiveMatchViewModel`. Court Calibration also reachable from Settings.
- **Phase C (Real shuttle detector):** ✅ `TrackNetV3.mlpackage` is bundled. `TrackNetWindowAdapter` wraps `TrackNetShuttleDetector`'s windowed API into `ShuttleDetecting`, with rolling 8-frame ring, 288×512 CI preprocessing into a `CVPixelBufferPool`, oldest-frame background (TODO: temporal-median), and stride-4 inference caching. `LiveMatchViewModel` injects it into the suggestor. Pipeline since gained orientation-aware / both-angle support and a cross-court shuttle mask post-filter (ADR-0001).
- **Phase D (Rally-end suggestion loop):** ✅ `TrajectoryRallySuggestor` replaces `StubRallySuggestor` — pulls last ~2s from `CircularFrameBuffer`, runs `ShuttleDetecting`, fits trajectory via `TrajectoryCalculator`, maps landing into court space via `CalibrationProfile`, returns side + confidence (count + parabola-residual + distance-from-net, equal weights, clamped). Graceful fallback (coin-flip capped at 0.50) when calibration missing / buffer empty / < 2 detections. `RallySuggestionSheet` accepts an injected suggestor; `LiveMatchView` passes the real one.
- **Phase E (On-device validation):** ⏳ Awaiting user — tether iPhone, free Apple ID install, calibrate court, play short rallies, measure suggestion accuracy vs the ~70% target.

Work landed since the 2026-05-21 snapshot (54 commits): Footage tab fully wired (see resolved follow-up #3), trim/zoom highlight clip editor with persisted `ClipRef`, library video import streamed to disk with progress, Players-tab + cold-launch perf fixes (killed a measured 2.0s SwiftData main-thread hang), five trust-breaker UX defects from design review, and a large hawkeye/labeler push (orientation support, N=not-a-rally verdict, auto-annotate baselines).

Open follow-ups (quality improvements, not Phase E blockers):
1. **TrackNet adapter background frame:** uses oldest-window frame; temporal-median blend is the proper fix — improves accuracy when the camera is static (typical tripod setup). Tracked as `TODO(bg-median)` in `TrackNetWindowAdapter.swift`.
2. **TrackNet confidence calibration:** heatmap peak passed through clamped to [0,1]; may want `sigmoid()` if the bundled checkpoint emits logits (suggestor's ranking still works either way).
3. ~~**Footage tab WIP**~~ ✅ RESOLVED — `GameVideoRecord` is registered in the `ModelContainer` schema, `PersistedMatch.gameVideos` cascade relationship is in place, and the files are wired into `project.pbxproj`. Footage editor (trim/zoom, `ClipRef`) shipped.

Infra:
- **CI added** (`.github/workflows/ci.yml`): macOS runner runs `swift test` for ScoringEngine and `xcodebuild test` for the BadmintonEye scheme on push/PR to `main`.
- **Stale PRs:** 7 open PRs (#18, #20–24, #27) are pre-pivot (claude-flow bot, May 10) and mostly target features the MVP pivot cut (paywall, widgets, account deletion, superseded CoreML detector). Triaged 2026-06-15 — see PR comments.

Last activity: 2026-06-15 — refreshed planning state, added CI, triaged stale pre-pivot PRs. Code-complete through Phase D; Phase E (on-device) is the remaining gate.

Progress: [########--] 80% on MVP milestone — full pipeline live + hardened; awaiting on-device validation

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

Last session: 2026-06-15
Stopped at: Planning state refreshed, CI workflow added, stale pre-pivot PRs triaged. MVP Phases A–D code-complete; Phase E (on-device validation on a tethered iPhone) is the remaining gate and requires the user + a Mac.
Resume file: None
