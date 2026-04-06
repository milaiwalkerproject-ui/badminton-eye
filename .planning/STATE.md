# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-05)

**Core value:** Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time.
**Current focus:** v1.17 — 3×15 Games 3–4–5 Service Continuity Tests

## Current Position

Phase: 40 of 40
Plan: Phase 40 in progress
Status: In progress
Last activity: 2026-04-05 — v1.17 started, writing 3×15 games 3→4 and 4→5 service continuity tests

Progress: [##########] 10% (v1.17)

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
