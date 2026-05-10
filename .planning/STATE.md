# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-05)

**Core value:** Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time.
**Current focus:** v1.18 — Custom Scoring Mid-Switch & Validation Edge Cases

## Current Position

Phase: v2.0 App Store Release
Plan: Active — App Store submission pipeline
Status: In progress — PRs #1-17 merged to main; PRs #18-27 under CTO review
Last activity: 2026-05-10 — v2.0 release pipeline (screenshots, CI, Watch sync, WidgetKit, PaywallV2)

Progress: [#########-] 90% (v2.0 — pending App Store submission)

## v2.0 Features Shipped (PRs #1-17 merged)

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
