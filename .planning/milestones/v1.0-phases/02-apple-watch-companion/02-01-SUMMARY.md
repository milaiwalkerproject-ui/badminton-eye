---
phase: 02-apple-watch-companion
plan: 01
subsystem: sync
tags: [watchconnectivity, wcsession, watchos, offline-scoring, userdefaults]

# Dependency graph
requires:
  - phase: 01-scoring-engine
    provides: "MatchEngine, MatchState, CodableMatchState, Types"
provides:
  - "SyncPayload for WatchConnectivity transport"
  - "WatchSyncManager (iOS-side WCSessionDelegate singleton)"
  - "WatchSessionManager (watchOS-side WCSessionDelegate singleton)"
  - "WatchMatchViewModel with offline scoring and UserDefaults persistence"
  - "Bidirectional scoring intent bridge in LiveMatchViewModel"
affects: [02-apple-watch-companion, 03-match-history-analytics]

# Tech tracking
tech-stack:
  added: [WatchConnectivity]
  patterns: [dual-transport-sync, iphone-authoritative, sigkill-protection]

key-files:
  created:
    - BadmintonEye/BadmintonEye/Models/SyncPayload.swift
    - BadmintonEye/BadmintonEye/Services/WatchSyncManager.swift
    - BadmintonEye/BadmintonEyeWatch/Services/WatchSessionManager.swift
    - BadmintonEye/BadmintonEyeWatch/ViewModels/WatchMatchViewModel.swift
  modified:
    - BadmintonEye/BadmintonEye/ViewModels/LiveMatchViewModel.swift

key-decisions:
  - "Dual transport: updateApplicationContext (guaranteed) + sendMessage (fast) for reliability"
  - "iPhone-authoritative: Watch adopts iPhone state unconditionally on reconnection"
  - "UserDefaults persistence after every point for SIGKILL protection on watchOS"

patterns-established:
  - "Dual transport pattern: always updateApplicationContext + sendMessage when reachable"
  - "iPhone-authoritative sync: Watch local state is overwritten by iPhone state"
  - "Singleton WCSessionDelegate per target: WatchSyncManager (iOS), WatchSessionManager (watchOS)"

requirements-completed: [WATCH-03, WATCH-04]

# Metrics
duration: 2min
completed: 2026-03-28
---

# Phase 2 Plan 1: WatchConnectivity Sync Infrastructure Summary

**Bidirectional WatchConnectivity sync pipeline with dual transport, offline scoring via local MatchEngine, and UserDefaults SIGKILL protection**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-29T05:43:45Z
- **Completed:** 2026-03-29T05:45:38Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- SyncPayload wraps CodableMatchState with timestamp and isMatchActive flag for WatchConnectivity transport
- iPhone sends state via dual transport (updateApplicationContext + sendMessage) on every state change
- Watch scores points offline using local MatchEngine.apply when iPhone is unreachable
- Watch persists to UserDefaults after every scored point and restores on launch
- LiveMatchViewModel bridges scoring events bidirectionally via WatchSyncManager callbacks

## Task Commits

Each task was committed atomically:

1. **Task 1: Create SyncPayload and iOS WatchSyncManager** - `eb5fe0e` (feat)
2. **Task 2: Create watchOS WatchSessionManager and WatchMatchViewModel** - `fedfe79` (feat)

## Files Created/Modified
- `BadmintonEye/BadmintonEye/Models/SyncPayload.swift` - Codable sync payload wrapping CodableMatchState with dictionary serialization
- `BadmintonEye/BadmintonEye/Services/WatchSyncManager.swift` - iOS-side WCSessionDelegate singleton with dual transport and scoring intent callback
- `BadmintonEye/BadmintonEyeWatch/Services/WatchSessionManager.swift` - watchOS-side WCSessionDelegate singleton delivering state to ViewModel
- `BadmintonEye/BadmintonEyeWatch/ViewModels/WatchMatchViewModel.swift` - Observable ViewModel with offline scoring, UserDefaults persistence, iPhone-authoritative sync
- `BadmintonEye/BadmintonEye/ViewModels/LiveMatchViewModel.swift` - Added WatchSyncManager integration in persistState() and both init methods

## Decisions Made
- Dual transport: updateApplicationContext (guaranteed delivery) + sendMessage (immediate when reachable) ensures state arrives reliably
- iPhone-authoritative: Watch adopts iPhone state unconditionally on reconnection, avoiding complex conflict resolution
- UserDefaults persistence after every point protects against SIGKILL on watchOS (no graceful shutdown guaranteed)
- SyncPayload and CodableMatchState need to be shared with the watchOS target (noted for next plan when Xcode project is modified)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Sync infrastructure complete; ready for Watch UI views (02-02)
- SyncPayload.swift and CodableMatchState.swift must be added to the watchOS target in the Xcode project (02-02 or 02-03)
- WatchConnectivity must be tested on real paired devices (simulator is unreliable)

## Self-Check: PASSED

- All 4 created files verified on disk
- All 1 modified file verified on disk
- Commit eb5fe0e (Task 1) found in git log
- Commit fedfe79 (Task 2) found in git log
- ScoringEngine tests: 44/44 passing

---
*Phase: 02-apple-watch-companion*
*Completed: 2026-03-28*
