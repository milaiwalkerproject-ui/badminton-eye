---
phase: 01-scoring-engine
plan: 01
subsystem: scoring
tags: [swift, swift-testing, state-machine, bwf-rules, tdd]

requires: []
provides:
  - "BWF-compliant scoring engine as pure Swift package"
  - "Singles, doubles, mixed doubles scoring with correct service rotation"
  - "Deuce at 20-all, 30-point cap, best-of-3 games"
  - "Side switching at game end and mid-third-game at 11"
  - "Single-level undo including game-winning point reversal"
affects: [02-swiftdata-persistence, 03-iphone-ui, 04-watch-scoring]

tech-stack:
  added: [swift-6, swift-testing, swift-package-manager]
  patterns: [pure-state-machine, value-type-transitions, indirect-box-for-recursion]

key-files:
  created:
    - ScoringEngine/Package.swift
    - ScoringEngine/Sources/ScoringEngine/Types.swift
    - ScoringEngine/Sources/ScoringEngine/MatchState.swift
    - ScoringEngine/Sources/ScoringEngine/MatchEngine.swift
    - ScoringEngine/Sources/ScoringEngine/BWFRules.swift
    - ScoringEngine/Sources/ScoringEngine/ServiceTracker.swift
    - ScoringEngine/Tests/ScoringEngineTests/SinglesScoringTests.swift
    - ScoringEngine/Tests/ScoringEngineTests/DeuceAndCapTests.swift
    - ScoringEngine/Tests/ScoringEngineTests/ServiceRotationTests.swift
    - ScoringEngine/Tests/ScoringEngineTests/GameTransitionTests.swift
    - ScoringEngine/Tests/ScoringEngineTests/UndoTests.swift
    - ScoringEngine/Tests/ScoringEngineTests/DoublesScoringTests.swift
    - ScoringEngine/Tests/ScoringEngineTests/MixedDoublesScoringTests.swift
  modified: []

key-decisions:
  - "Used StateSnapshot class as indirect box to enable recursive MatchState storage in value type"
  - "Fixed rotation array of 4 PlayerPositions for doubles service tracking (index-based, not computed)"
  - "Custom Equatable excludes previousState to avoid infinite recursion"
  - "MatchEvent made Equatable for testability"

patterns-established:
  - "Pure state machine: MatchEngine.apply(event:to:) returns new MatchState with zero side effects"
  - "BWF rules as computed properties on MatchState (isDeuce, isGameWon, serviceCourt, etc.)"
  - "Doubles rotation via fixed 4-element array with modular index advancement"
  - "Single-level undo via previousState snapshot stored before each transition"

requirements-completed: [SCORE-01, SCORE-03, SCORE-04, SCORE-05, SCORE-06, SCORE-07]

duration: 4min
completed: 2026-03-28
---

# Phase 1 Plan 1: Scoring Engine Core Summary

**BWF-compliant scoring engine as pure Swift 6 package with 44 tests covering singles, doubles, mixed doubles service rotation, deuce/cap rules, game transitions, and undo**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-29T05:07:57Z
- **Completed:** 2026-03-29T05:12:01Z
- **Tasks:** 2
- **Files modified:** 13

## Accomplishments
- Pure value-type state machine with deterministic transitions and zero external dependencies
- Complete BWF Law 7 (scoring), Law 8 (side switches), Law 10 (singles service), Law 11 (doubles service) implementation
- 44 tests across 7 suites all passing in under 1ms, including the notoriously tricky doubles rotation cycle
- Mixed doubles 2026 rule (non-receiver serves) correctly handled via rotation array design

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ScoringEngine package with types, state structs, and core singles scoring** - `b7fb03a` (feat)
2. **Task 2: Add doubles and mixed doubles service rotation with exhaustive tests** - `42d6741` (feat)

## Files Created/Modified
- `ScoringEngine/Package.swift` - Swift 6 package manifest with library and test targets (iOS 17+, watchOS 10+)
- `ScoringEngine/Sources/ScoringEngine/Types.swift` - MatchFormat, Side, Court, MatchPhase, PlayerPosition, MatchEvent enums
- `ScoringEngine/Sources/ScoringEngine/MatchState.swift` - Core GameState and MatchState structs with factory methods
- `ScoringEngine/Sources/ScoringEngine/MatchEngine.swift` - Pure transition function with singles and doubles service logic
- `ScoringEngine/Sources/ScoringEngine/BWFRules.swift` - Computed properties: isDeuce, isAtCap, isGameWon, shouldSwitchSides, gamesWon
- `ScoringEngine/Sources/ScoringEngine/ServiceTracker.swift` - currentServer and serviceCourt computed properties
- `ScoringEngine/Tests/ScoringEngineTests/SinglesScoringTests.swift` - 10 tests for basic scoring and match flow
- `ScoringEngine/Tests/ScoringEngineTests/DeuceAndCapTests.swift` - 6 tests for deuce and 30-point cap
- `ScoringEngine/Tests/ScoringEngineTests/ServiceRotationTests.swift` - 6 tests for singles service court tracking
- `ScoringEngine/Tests/ScoringEngineTests/GameTransitionTests.swift` - 6 tests for side switches and game transitions
- `ScoringEngine/Tests/ScoringEngineTests/UndoTests.swift` - 4 tests for undo including game-winning point
- `ScoringEngine/Tests/ScoringEngineTests/DoublesScoringTests.swift` - 9 tests for doubles rotation and court swapping
- `ScoringEngine/Tests/ScoringEngineTests/MixedDoublesScoringTests.swift` - 5 tests for mixed doubles 2026 rule

## Decisions Made
- **StateSnapshot indirect box:** Swift structs cannot recursively contain themselves. Used a `final class StateSnapshot: @unchecked Sendable` wrapper to hold the previousState reference. This is the standard Swift pattern for recursive value types.
- **Fixed rotation array for doubles:** Instead of computing next server dynamically (error-prone), used a fixed 4-element `doublesRotation` array. Service changes are a simple index increment mod 4. This avoids the most common doubles scoring bug.
- **MatchEvent as Equatable:** Added Equatable conformance to MatchEvent for better test assertions beyond what the plan specified.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Swift struct cannot recursively contain itself**
- **Found during:** Task 1 (MatchState creation)
- **Issue:** `MatchState` is a struct with `var previousState: MatchState?` -- Swift value types cannot have recursive stored properties
- **Fix:** Created `StateSnapshot` class as indirect box, with computed `previousState` property forwarding to/from `previousSnapshot`
- **Files modified:** `ScoringEngine/Sources/ScoringEngine/MatchState.swift`
- **Verification:** Package compiles, all undo tests pass
- **Committed in:** `b7fb03a` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Standard Swift pattern for recursive value types. No scope creep.

## Issues Encountered
None beyond the recursive struct issue documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- ScoringEngine package is complete and ready to be linked into iOS app target
- SwiftData persistence layer (Plan 02) can import ScoringEngine and serialize MatchState
- iPhone UI (Plan 03) can use MatchEngine.apply() for all scoring interactions
- Watch target (Phase 2) can import the same package

## Self-Check: PASSED

- All 14 files verified present on disk
- Commit `b7fb03a` (Task 1) verified in git log
- Commit `42d6741` (Task 2) verified in git log
- 44 tests passing across 7 suites

---
*Phase: 01-scoring-engine*
*Completed: 2026-03-28*
