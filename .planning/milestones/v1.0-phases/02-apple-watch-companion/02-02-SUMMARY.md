---
phase: 02-apple-watch-companion
plan: 02
subsystem: ui
tags: [watchos, swiftui, haptics, watchkit, wkinterfacedevice]

# Dependency graph
requires:
  - phase: 02-apple-watch-companion/01
    provides: WatchSessionManager, WatchMatchViewModel, SyncPayload, CodableMatchState
  - phase: 01-scoring-engine
    provides: ScoringEngine package (MatchState, Side, GameState, MatchEngine)
provides:
  - watchOS app target with Xcode project configuration
  - WatchScoringView with top/bottom tap zones for scoring
  - WatchScoreDisplay with 44pt glanceable score, server indicator, team name
  - GameDotsIndicator for current game tracking (filled/unfilled dots)
  - WatchWaitingView for no-active-match state
  - Haptic feedback patterns (click/success/notification)
affects: [02-apple-watch-companion/03, 03-swiftdata-persistence]

# Tech tracking
tech-stack:
  added: [WatchKit haptics, watchOS 10.0 target]
  patterns: [top/bottom split scoring layout, glanceable watch UI, haptic feedback tiers]

key-files:
  created:
    - BadmintonEye/BadmintonEyeWatch/App/BadmintonEyeWatchApp.swift
    - BadmintonEye/BadmintonEyeWatch/Views/WatchScoringView.swift
    - BadmintonEye/BadmintonEyeWatch/Views/WatchScoreDisplay.swift
    - BadmintonEye/BadmintonEyeWatch/Views/WatchWaitingView.swift
    - BadmintonEye/BadmintonEyeWatch/Assets.xcassets/Contents.json
    - BadmintonEye/BadmintonEye.xcodeproj/xcshareddata/xcschemes/BadmintonEyeWatch.xcscheme
    - BadmintonEye/BadmintonEye.xcodeproj/xcshareddata/xcschemes/BadmintonEye.xcscheme
  modified:
    - BadmintonEye/BadmintonEye.xcodeproj/project.pbxproj

key-decisions:
  - "Used Apple Watch Series 11 simulator (Series 10 not available in Xcode 26)"
  - "Added SyncPayload.swift and WatchSyncManager.swift to iOS pbxproj (missing from 02-01)"

patterns-established:
  - "Top/bottom split layout: wrist-ergonomic scoring interface for watchOS"
  - "Three-tier haptic feedback: click (point) < success (game) < notification (match)"
  - "Shared source files: CodableMatchState and SyncPayload compile for both iOS and watchOS targets"

requirements-completed: [WATCH-01, WATCH-02]

# Metrics
duration: 6min
completed: 2026-03-28
---

# Phase 2 Plan 2: Watch App & Scoring UI Summary

**watchOS app with top/bottom tap-zone scoring, 44pt glanceable score display, game dots, shuttlecock server icon, and three-tier haptic feedback**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-29T05:48:14Z
- **Completed:** 2026-03-29T05:54:37Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments
- watchOS target builds and links ScoringEngine, WatchConnectivity, HealthKit frameworks
- Top/bottom tap zone scoring with distinct haptic feedback for point/game/match events
- Glanceable 44pt score display with game indicator dots and shuttlecock server icon
- Shared source files (CodableMatchState, SyncPayload) compile for both iOS and watchOS targets

## Task Commits

Each task was committed atomically:

1. **Task 1: Create watchOS app entry point and Xcode project configuration** - `eafa48f` (feat)
2. **Task 2: Build Watch scoring UI with tap zones, game dots, server icon, and haptics** - `1a4ae4d` (feat)

## Files Created/Modified
- `BadmintonEye/BadmintonEyeWatch/App/BadmintonEyeWatchApp.swift` - watchOS app entry point with routing and WatchSessionManager activation
- `BadmintonEye/BadmintonEyeWatch/Views/WatchScoringView.swift` - Top/bottom split tap zones with haptic feedback
- `BadmintonEye/BadmintonEyeWatch/Views/WatchScoreDisplay.swift` - Glanceable 44pt score, team name, shuttlecock server indicator
- `BadmintonEye/BadmintonEyeWatch/Views/WatchWaitingView.swift` - Waiting state with iPhone prompt
- `BadmintonEye/BadmintonEye.xcodeproj/project.pbxproj` - watchOS target, shared files, framework linking
- `BadmintonEye/BadmintonEye.xcodeproj/xcshareddata/xcschemes/BadmintonEyeWatch.xcscheme` - Shared scheme for watchOS target
- `BadmintonEye/BadmintonEye.xcodeproj/xcshareddata/xcschemes/BadmintonEye.xcscheme` - Shared scheme for iOS target
- `BadmintonEye/BadmintonEyeWatch/Assets.xcassets/Contents.json` - watchOS asset catalog
- `BadmintonEye/BadmintonEyeWatch/Assets.xcassets/AppIcon.appiconset/Contents.json` - watchOS app icon placeholder

## Decisions Made
- Used Apple Watch Series 11 simulator since Series 10 is not available in Xcode 26
- Added SyncPayload.swift and WatchSyncManager.swift to the iOS target's project.pbxproj (were created on disk by 02-01 but not registered in the project file)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added SyncPayload.swift to iOS target in project.pbxproj**
- **Found during:** Task 1 (Xcode project configuration)
- **Issue:** SyncPayload.swift existed on disk from Plan 02-01 but was never added to the iOS target's PBXSourcesBuildPhase, causing it to be invisible to the compiler
- **Fix:** Added PBXFileReference (A2000D), PBXBuildFile (A1000C) for iOS target, and PBXBuildFile (W1000A) for watchOS target
- **Files modified:** BadmintonEye/BadmintonEye.xcodeproj/project.pbxproj
- **Verification:** Both iOS and watchOS targets build successfully
- **Committed in:** eafa48f (Task 1 commit)

**2. [Rule 3 - Blocking] Added WatchSyncManager.swift to iOS target in project.pbxproj**
- **Found during:** Task 1 (Xcode project configuration)
- **Issue:** WatchSyncManager.swift existed in BadmintonEye/BadmintonEye/Services/ from Plan 02-01 but was never registered in the project file; LiveMatchViewModel.swift references WatchSyncManager causing iOS build failure
- **Fix:** Added PBXFileReference (A2000F), PBXBuildFile (A1000E), PBXGroup (A40006/Services), and source build phase entry for the iOS target
- **Files modified:** BadmintonEye/BadmintonEye.xcodeproj/project.pbxproj
- **Verification:** iOS target builds successfully with WatchSyncManager in scope
- **Committed in:** eafa48f (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (2 blocking issues from 02-01 missing pbxproj entries)
**Impact on plan:** Both auto-fixes were essential for iOS target compilation. No scope creep.

## Issues Encountered
- Apple Watch Series 10 (46mm) simulator not available in Xcode 26; used Series 11 (46mm) instead

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- watchOS app builds and links all required frameworks
- Ready for Plan 02-03 (HealthKit workout session integration)
- WKCompanionAppBundleIdentifier set to com.badmintoneye.app for proper pairing

## Self-Check: PASSED

All 6 key files verified present. Both task commits (eafa48f, 1a4ae4d) verified in git log.

---
*Phase: 02-apple-watch-companion*
*Completed: 2026-03-28*
