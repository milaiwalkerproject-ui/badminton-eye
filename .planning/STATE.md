# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-28)

**Core value:** Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time.
**Current focus:** Phase 2: Apple Watch Companion

## Current Position

Phase: 2 of 5 (Apple Watch Companion)
Plan: 1 of 3 in current phase
Status: Plan 02-01 complete, ready for 02-02
Last activity: 2026-03-28 — Completed 02-01-PLAN.md (WatchConnectivity sync infrastructure)

Progress: [====░░░░░░] 19%

## Performance Metrics

**Velocity:**
- Total plans completed: 3
- Average duration: 3 min
- Total execution time: 0.17 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-scoring-engine | 2/3 | 8 min | 4 min |
| 02-apple-watch-companion | 1/3 | 2 min | 2 min |

**Recent Trend:**
- Last 5 plans: 01-01 (4 min), 01-02 (4 min), 02-01 (2 min)
- Trend: stable

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Roadmap: SwiftData models MUST use optional properties and default values from Phase 1 for future CloudKit compatibility
- Roadmap: Hawk Eye and Premium billing combined into single phase (interdependent features)
- Research: Use `updateApplicationContext` as primary WatchConnectivity transport for reliability
- 01-01: Used StateSnapshot class as indirect box to enable recursive MatchState storage in value type
- 01-01: Fixed rotation array of 4 PlayerPositions for doubles service tracking (index-based, not computed)
- 01-01: Custom Equatable excludes previousState to avoid infinite recursion
- 01-02: CodableMatchState mirror struct for JSON serialization, excluding recursive previousState field
- 01-02: Hand-crafted project.pbxproj for CLI-based Xcode project creation with local package reference
- 02-01: Dual transport (updateApplicationContext + sendMessage) for reliable Watch sync
- 02-01: iPhone-authoritative sync: Watch adopts iPhone state unconditionally on reconnection
- 02-01: UserDefaults persistence after every point for watchOS SIGKILL protection

### Pending Todos

None yet.

### Blockers/Concerns

- Hawk Eye single-camera accuracy is unproven -- prototype with 50+ real court videos early in Phase 5 before building full pipeline
- WatchConnectivity must be tested on real paired devices (simulator is unreliable for this)

## Session Continuity

Last session: 2026-03-28
Stopped at: Completed 02-01-PLAN.md
Resume file: None
