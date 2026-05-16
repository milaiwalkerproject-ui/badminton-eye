# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-16 — MVP pivot)

**Current focus:** MVP — Installable iPhone Prototype with Auto-Suggest Scoring
**Driver:** Claude Code `/goal` command (not GSD). GSD `.planning/` history is preserved for context but not actively driving phases.

## Current Position

Phase: MVP-A — Strip down for free Apple ID install (code complete, awaiting on-device install confirmation)
Plan: See PROJECT.md → Phases A–E
Status: Phase A code landed. Added `AppMode.freeAppleIDMode` (default ON) in `BadmintonEyeApp.swift`; gated CloudKit binding in the SwiftData container, `AuthManager.checkAuthState`/`handleSignInResult`, every public StoreKit entry point on `SubscriptionManager`, and `startLiveActivity` on `LiveMatchViewModel`. Stripped `BadmintonEye.entitlements` of `applesignin`, `icloud-services`, `icloud-container-identifiers` (revert via git to flip back to paid mode). Watch + LiveActivity targets are untouched at the project-file level. Simulator build (iPhone 17) succeeds; `ScoringEngine` package tests pass 143/143. The shared BadmintonEye scheme has no Testables configured on `main` (pre-existing project-file hygiene gap — 5 test files on disk, only one wired into the target), so iOS-side `xcodebuild test` cannot run from the shared scheme; deferred to a later phase as it's outside Phase A scope.
Last activity: 2026-05-16 — Phase A complete pending physical-device install verification

Progress: [#---------] 10% on MVP milestone — awaiting human checkpoint A

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
