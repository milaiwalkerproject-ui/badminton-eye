# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-29)

**Core value:** Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time.
**Current focus:** v1.2 — Haptic Scoring, BWF 3x15 & Multi-Camera

## Current Position

Phase: 10 of 12
Plan: —
Status: Ready to plan
Last activity: 2026-03-29 — Roadmap created

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 24 (16 v1.0 + 8 v1.1)
- Average duration: —
- Total execution time: —

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1-5 (v1.0) | 16 | — | — |
| 6-9 (v1.1) | 8 | — | — |
| 10-12 (v1.2) | 0/6 | — | — |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Carried forward from v1.0:

- SwiftData models use optional properties and defaults for CloudKit
- Placeholder Core ML shuttle detection (replaced in Phase 9 with real CoreMLShuttleDetector)
- Gaussian elimination homography solve (no external linear algebra)

v1.1 roadmap decisions:
- Analytics first (Phase 6): zero deps on AI/camera, ships user value immediately
- Training pipeline (Phase 7) parallel with analytics: longest calendar lead time (dataset collection)
- 240fps capture (Phase 8) before AI integration: testable with placeholder model
- Real AI integration last (Phase 9): depends on trained model + 240fps pipeline

v1.2 roadmap decisions:
- BWF 3x15 first (Phase 10): pure scoring logic, no hardware deps, foundational for haptics
- Haptics second (Phase 11): must trigger on both scoring formats, quick win after scoring stabilizes
- Multi-camera last (Phase 12): highest complexity, device-dependent, builds on stable pipeline

### Pending Todos

None yet.

### Blockers/Concerns

- BWF 3x15 exact thresholds (deuce at 14? cap at 17?) — depends on April 25 vote; implement best-known rules, parameterize for easy update
- Dual 240fps CircularFrameBuffer memory (~8.6GB) — use asymmetric FPS (240 primary + 60 secondary) for multi-camera
- Watch haptics threading — WatchMatchViewModel not @MainActor; haptic calls from WCSession callbacks silently fail on background threads

## Session Continuity

Last session: 2026-03-29
Stopped at: v1.2 roadmap created — ready to plan Phase 10
Resume file: None
