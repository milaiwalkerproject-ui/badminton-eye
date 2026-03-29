---
phase: 04-cloud-sync-and-authentication
plan: 02
subsystem: ui
tags: [activitykit, live-activity, dynamic-island, widgetkit, swift-concurrency]

# Dependency graph
requires:
  - phase: 01-scoring-engine
    provides: MatchState, GameState, Side, MatchPhase, currentServer
  - phase: 04-cloud-sync-and-authentication
    provides: 04-01 established project structure with entitlements
provides:
  - Live Activity widget extension (lock screen + Dynamic Island)
  - MatchActivityAttributes shared between main app and widget extension
  - Automatic Live Activity lifecycle tied to match start/update/end
affects: [05-hawk-eye-and-premium]

# Tech tracking
tech-stack:
  added: [ActivityKit, WidgetKit]
  patterns: [scalar-capture-for-swift6-task-isolation, activity-id-lookup-pattern]

key-files:
  created:
    - BadmintonEye/BadmintonEyeLiveActivity/MatchActivityAttributes.swift
    - BadmintonEye/BadmintonEyeLiveActivity/BadmintonEyeLiveActivityLiveActivity.swift
    - BadmintonEye/BadmintonEyeLiveActivity/BadmintonEyeLiveActivityBundle.swift
  modified:
    - BadmintonEye/BadmintonEye/ViewModels/LiveMatchViewModel.swift
    - BadmintonEye/BadmintonEye.xcodeproj/project.pbxproj

key-decisions:
  - "Scalar capture pattern for Swift 6 Task isolation -- extract primitive values before Task closure to avoid region isolation errors with Activity type"
  - "Activity ID lookup via Activity.activities instead of storing Activity reference -- avoids non-Sendable capture in Swift 6 strict concurrency"
  - "5-minute dismissal delay after match end to keep final score visible on lock screen"

patterns-established:
  - "Activity ID pattern: Store activity ID (String) not Activity reference, look up via Activity.activities for updates"
  - "Scalar capture: Extract Int/String values from non-Sendable types before passing into Task closures"

requirements-completed: [UX-01]

# Metrics
duration: 4min
completed: 2026-03-29
---

# Phase 4 Plan 2: Live Activity Lock Screen and Dynamic Island Summary

**ActivityKit Live Activity showing real-time match scores on lock screen (large score, names, game dots, server indicator) and Dynamic Island (compact score)**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-29T10:22:38Z
- **Completed:** 2026-03-29T10:26:35Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Live Activity widget extension with full lock screen expanded view (player names, large score, game indicator dots, server arrow, tap hint)
- Dynamic Island compact (leading/trailing score), expanded (names + score + dots), and minimal (single score) views
- LiveMatchViewModel auto-starts Live Activity on match begin (new and crash recovery), updates on every point/undo, ends on complete/abandon

## Task Commits

Each task was committed atomically:

1. **Task 1: MatchActivityAttributes and Live Activity widget extension** - `a8c6442` (feat)
2. **Task 2: Integrate Live Activity lifecycle into LiveMatchViewModel** - `f0d9d20` (feat)

## Files Created/Modified
- `BadmintonEye/BadmintonEyeLiveActivity/MatchActivityAttributes.swift` - ActivityAttributes with ContentState for live match data
- `BadmintonEye/BadmintonEyeLiveActivity/BadmintonEyeLiveActivityLiveActivity.swift` - Lock screen and Dynamic Island UI views
- `BadmintonEye/BadmintonEyeLiveActivity/BadmintonEyeLiveActivityBundle.swift` - WidgetBundle entry point
- `BadmintonEye/BadmintonEye/ViewModels/LiveMatchViewModel.swift` - ActivityKit lifecycle (start/update/end)
- `BadmintonEye/BadmintonEye.xcodeproj/project.pbxproj` - Widget extension target, NSSupportsLiveActivities

## Decisions Made
- Scalar capture pattern for Swift 6 Task isolation: extract primitive values (Int, String) from non-Sendable MatchState before Task closure to avoid region isolation checker errors
- Activity ID lookup via Activity<MatchActivityAttributes>.activities instead of storing Activity reference directly, since Activity is not Sendable in Swift 6
- 5-minute dismissal delay after match end keeps final score visible on lock screen

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed NSSupportsLiveActivities missing from Release config**
- **Found during:** Task 1
- **Issue:** Release build configuration for main app was missing INFOPLIST_KEY_NSSupportsLiveActivities = YES (only present in Debug)
- **Fix:** Added the key to AE0004 Release config
- **Files modified:** project.pbxproj
- **Verification:** Build succeeded
- **Committed in:** a8c6442

**2. [Rule 1 - Bug] Fixed INFOPLIST_KEY_NSExtension to NSExtensionPointIdentifier**
- **Found during:** Task 1
- **Issue:** Live Activity extension configs used incorrect key INFOPLIST_KEY_NSExtension instead of INFOPLIST_KEY_NSExtensionPointIdentifier
- **Fix:** Replaced in both Debug and Release configs
- **Files modified:** project.pbxproj
- **Verification:** Build succeeded
- **Committed in:** a8c6442

**3. [Rule 3 - Blocking] Swift 6 strict concurrency with Activity type**
- **Found during:** Task 2
- **Issue:** Activity<MatchActivityAttributes> is not Sendable; capturing it in Task closures caused region isolation errors
- **Fix:** Store activity ID (String) instead of Activity reference; extract scalar values before Task closure; look up activity via Activity.activities inside Task
- **Files modified:** LiveMatchViewModel.swift
- **Verification:** Build succeeded with Swift 6 strict concurrency
- **Committed in:** f0d9d20

---

**Total deviations:** 3 auto-fixed (2 bugs, 1 blocking)
**Impact on plan:** All auto-fixes necessary for correctness and Swift 6 compliance. No scope creep.

## Issues Encountered
None beyond the auto-fixed deviations above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Live Activity infrastructure complete, ready for Phase 5 features
- Push notification-based Live Activity updates could be added later for background refresh
- Widget extension target established for potential future WidgetKit home screen widgets

## Self-Check: PASSED

All 4 key files verified present. Both task commits (a8c6442, f0d9d20) verified in git log.

---
*Phase: 04-cloud-sync-and-authentication*
*Completed: 2026-03-29*
