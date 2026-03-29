---
phase: 02-apple-watch-companion
plan: 03
subsystem: watch, ui
tags: [healthkit, hkworkoutsession, navigationsplitview, ipad, watchos, swiftui]

# Dependency graph
requires:
  - phase: 02-apple-watch-companion/02-02
    provides: "Watch scoring UI, WatchMatchViewModel, WatchScoringView"
  - phase: 02-apple-watch-companion/02-01
    provides: "WatchConnectivity sync infrastructure, WatchSessionManager, WatchSyncManager"
provides:
  - "WorkoutManager for HKWorkoutSession lifecycle on Apple Watch"
  - "iPad-adaptive ContentView with NavigationSplitView sidebar"
  - "WatchSyncManager activation on iOS side"
affects: [03-swiftdata-persistence, 04-hawk-eye]

# Tech tracking
tech-stack:
  added: [HealthKit, HKWorkoutSession, HKLiveWorkoutBuilder, HKLiveWorkoutDataSource]
  patterns: [NavigationSplitView for iPad, horizontalSizeClass adaptive layout, singleton workout manager]

key-files:
  created:
    - BadmintonEye/BadmintonEyeWatch/Services/WorkoutManager.swift
  modified:
    - BadmintonEye/BadmintonEyeWatch/ViewModels/WatchMatchViewModel.swift
    - BadmintonEye/BadmintonEyeWatch/App/BadmintonEyeWatchApp.swift
    - BadmintonEye/BadmintonEye/App/BadmintonEyeApp.swift
    - BadmintonEye/BadmintonEye.xcodeproj/project.pbxproj

key-decisions:
  - "WorkoutManager uses @unchecked Sendable for Swift 6 concurrency compatibility with singleton pattern"
  - "Local variable capture of workoutManager in Task closures to satisfy Swift 6 sending parameter requirements"
  - "iPad compact mode (Split View/Slide Over) falls back to iPhone NavigationStack to avoid narrow tap zones"

patterns-established:
  - "Singleton @unchecked Sendable pattern for watchOS managers with async methods"
  - "horizontalSizeClass-based branching between NavigationSplitView and NavigationStack"

requirements-completed: [WATCH-05, WATCH-06, UX-02]

# Metrics
duration: 5min
completed: 2026-03-28
---

# Phase 2 Plan 3: HealthKit Workout Integration & iPad Layout Summary

**HKWorkoutSession with .badminton activity type auto-starts/stops with match lifecycle, plus iPad NavigationSplitView with match list sidebar**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-29T05:57:08Z
- **Completed:** 2026-03-29T06:02:23Z
- **Tasks:** 3 (2 auto + 1 checkpoint auto-approved)
- **Files modified:** 5

## Accomplishments
- WorkoutManager handles full HKWorkoutSession + HKLiveWorkoutBuilder lifecycle for badminton workouts with Activity Ring credit via finishWorkout()
- Workout auto-starts when match state arrives from iPhone and auto-ends when match completes (locally or via sync)
- HealthKit permissions requested at Watch app launch, never mid-match
- iPad displays NavigationSplitView with sidebar showing in-progress and completed matches
- iPhone layout unchanged; iPad compact mode falls back to NavigationStack

## Task Commits

Each task was committed atomically:

1. **Task 1: Create WorkoutManager and wire to WatchMatchViewModel** - `349ebaf` (feat)
2. **Task 2: Add iPad adaptive layout with NavigationSplitView** - `7bd65a9` (feat)
3. **Task 3: Verify Watch scoring, sync, and iPad layout** - auto-approved (YOLO mode)

## Files Created/Modified
- `BadmintonEye/BadmintonEyeWatch/Services/WorkoutManager.swift` - HKWorkoutSession + HKLiveWorkoutBuilder lifecycle manager
- `BadmintonEye/BadmintonEyeWatch/ViewModels/WatchMatchViewModel.swift` - Added workout start/end wiring to match state transitions
- `BadmintonEye/BadmintonEyeWatch/App/BadmintonEyeWatchApp.swift` - HealthKit authorization request at launch
- `BadmintonEye/BadmintonEye/App/BadmintonEyeApp.swift` - iPad NavigationSplitView with match list sidebar
- `BadmintonEye/BadmintonEye.xcodeproj/project.pbxproj` - Added WorkoutManager.swift to watch target

## Decisions Made
- Used @unchecked Sendable on WorkoutManager for Swift 6 strict concurrency (same pattern as WatchSessionManager)
- Captured workoutManager as local variable before Task closures to satisfy Swift 6 sending parameter requirements
- iPad compact size class falls back to iPhone layout to avoid narrow scoring tap zones in Split View

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Swift 6 concurrency: WorkoutManager not Sendable**
- **Found during:** Task 1 (WorkoutManager creation)
- **Issue:** Static property 'shared' flagged as not concurrency-safe for non-Sendable type
- **Fix:** Added @unchecked Sendable conformance (matches WatchSessionManager pattern)
- **Files modified:** BadmintonEye/BadmintonEyeWatch/Services/WorkoutManager.swift
- **Verification:** watchOS build succeeded
- **Committed in:** 349ebaf

**2. [Rule 3 - Blocking] Swift 6 concurrency: Task closure sending parameter data races**
- **Found during:** Task 1 (WatchMatchViewModel wiring)
- **Issue:** Passing closures capturing self.workoutManager as 'sending' parameter risks data races
- **Fix:** Captured workoutManager as local variable before Task closure
- **Files modified:** BadmintonEye/BadmintonEyeWatch/ViewModels/WatchMatchViewModel.swift
- **Verification:** watchOS build succeeded
- **Committed in:** 349ebaf

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both fixes required for Swift 6 strict concurrency compliance. No scope creep.

## Issues Encountered
- watchOS Simulator name changed from "Apple Watch Series 10" to "Apple Watch Series 11" -- used available simulator

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 2 (Apple Watch Companion) is complete
- Watch app has scoring, sync, haptics, and HealthKit workout tracking
- iPad layout ready with NavigationSplitView
- Ready for Phase 3: SwiftData persistence enhancements

---
*Phase: 02-apple-watch-companion*
*Completed: 2026-03-28*
