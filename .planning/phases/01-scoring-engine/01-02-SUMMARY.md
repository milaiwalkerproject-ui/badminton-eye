---
phase: 01-scoring-engine
plan: 02
subsystem: ui
tags: [swift, swiftui, swiftdata, xcode, ios17, cloudkit-safe]

requires:
  - phase: 01-scoring-engine/01
    provides: "BWF-compliant scoring engine (MatchEngine, MatchState, Types)"
provides:
  - "Xcode project targeting iOS 17+ with local ScoringEngine package dependency"
  - "SwiftData PersistedMatch model with CloudKit-safe properties for crash recovery"
  - "LiveMatchViewModel bridging MatchEngine to SwiftUI with per-point persistence"
  - "Match setup screen with format picker and player name entry"
  - "Half-screen tap zone scoring UI with server indicator and service court display"
  - "Game end overlay with score summary and auto-dismiss"
  - "Match end view with full scorecard"
affects: [03-watch-app, 04-cloudkit-sync, 05-hawk-eye]

tech-stack:
  added: [swiftui, swiftdata, xcode-project]
  patterns: [codable-mirror-for-recursive-types, observable-viewmodel-bridge, half-screen-tap-zones]

key-files:
  created:
    - BadmintonEye/BadmintonEye.xcodeproj/project.pbxproj
    - BadmintonEye/BadmintonEye/App/BadmintonEyeApp.swift
    - BadmintonEye/BadmintonEye/Models/SwiftDataModels.swift
    - BadmintonEye/BadmintonEye/Models/CodableMatchState.swift
    - BadmintonEye/BadmintonEye/ViewModels/LiveMatchViewModel.swift
    - BadmintonEye/BadmintonEye/Views/MatchSetupView.swift
    - BadmintonEye/BadmintonEye/Views/LiveMatchView.swift
    - BadmintonEye/BadmintonEye/Views/ScorePanel.swift
    - BadmintonEye/BadmintonEye/Views/GameEndOverlay.swift
    - BadmintonEye/BadmintonEye/Views/MatchEndView.swift
    - BadmintonEye/BadmintonEye/Assets.xcassets/Contents.json
    - BadmintonEye/BadmintonEye/Assets.xcassets/AppIcon.appiconset/Contents.json
  modified: []

key-decisions:
  - "CodableMatchState mirror struct for JSON serialization, excluding recursive previousState field"
  - "Hand-crafted project.pbxproj for CLI-based Xcode project creation with local package reference"
  - "Used iPhone 17 Pro simulator (Xcode 26.3) since iPhone 16 not available"

patterns-established:
  - "CodableMatchState pattern: Codable mirror of non-Codable recursive struct for SwiftData persistence"
  - "LiveMatchViewModel as @Observable bridge: UI -> ViewModel.scorePoint -> MatchEngine.apply -> persistState"
  - "Half-screen tap zones: GeometryReader + HStack(spacing:0) + contentShape(Rectangle()) for full-area tap"
  - "Server indicator: shuttlecock icon (circle.fill) with R/L court label on serving side only"

requirements-completed: [SCORE-01, SCORE-02, SCORE-08]

duration: 4min
completed: 2026-03-28
---

# Phase 1 Plan 2: iPhone App with SwiftData and Live Scoring UI Summary

**SwiftUI app with SwiftData crash-recovery persistence, half-screen tap zones, server/court indicators, game end overlay, and full match scorecard -- zero network calls**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-29T05:14:39Z
- **Completed:** 2026-03-29T05:18:58Z
- **Tasks:** 2
- **Files modified:** 12

## Accomplishments
- Complete Xcode project with iOS 17+ target linking local ScoringEngine package, builds successfully on simulator
- SwiftData PersistedMatch model with all CloudKit-safe properties (no @Attribute(.unique), all optional or defaulted)
- LiveMatchViewModel bridges MatchEngine.apply to SwiftUI with automatic SwiftData persistence after every point
- Full scoring UI with 120pt score display, shuttlecock server indicator, R/L service court label, undo, and end match
- Game end overlay with auto-dismiss and undo safety net; match end scorecard with game-by-game results

## Task Commits

Each task was committed atomically:

1. **Task 1: Create Xcode project, SwiftData models, and LiveMatchViewModel** - `ed5ff9d` (feat)
2. **Task 2: Build match setup screen and live scoring UI with half-screen tap zones** - `2f14369` (feat)

## Files Created/Modified
- `BadmintonEye/BadmintonEye.xcodeproj/project.pbxproj` - Xcode project with iOS 17+ target, local ScoringEngine package
- `BadmintonEye/BadmintonEye/App/BadmintonEyeApp.swift` - App entry point with SwiftData modelContainer
- `BadmintonEye/BadmintonEye/Models/SwiftDataModels.swift` - PersistedMatch @Model with CloudKit-safe properties
- `BadmintonEye/BadmintonEye/Models/CodableMatchState.swift` - Codable mirror for MatchState JSON serialization
- `BadmintonEye/BadmintonEye/ViewModels/LiveMatchViewModel.swift` - @Observable ViewModel bridging MatchEngine to SwiftUI
- `BadmintonEye/BadmintonEye/Views/MatchSetupView.swift` - Format picker (singles/doubles/mixed) and player names
- `BadmintonEye/BadmintonEye/Views/LiveMatchView.swift` - Half-screen tap zones with GeometryReader
- `BadmintonEye/BadmintonEye/Views/ScorePanel.swift` - Score display with server indicator and service court
- `BadmintonEye/BadmintonEye/Views/GameEndOverlay.swift` - Game end celebration with score summary
- `BadmintonEye/BadmintonEye/Views/MatchEndView.swift` - Full scorecard with New Match navigation
- `BadmintonEye/BadmintonEye/Assets.xcassets/` - Asset catalog with app icon placeholder

## Decisions Made
- **CodableMatchState mirror struct:** MatchState contains recursive previousState (via StateSnapshot class) which cannot be Codable. Created a separate CodableMatchState that mirrors all fields except previousState, with toMatchState() for deserialization. Cleanest approach without modifying the engine package.
- **Hand-crafted project.pbxproj:** Created Xcode project file manually from CLI since xcodebuild cannot create new projects. Used XCLocalSwiftPackageReference to link ScoringEngine. This is a well-known technique for CI/automation environments.
- **iPhone 17 Pro simulator:** Xcode 26.3 ships iPhone 17 series; iPhone 16 not available. Used iPhone 17 Pro for all build verification.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] CodableMatchState needed as separate file**
- **Found during:** Task 1
- **Issue:** Plan mentioned CodableMatchState inline in LiveMatchViewModel but it needed to be importable from Models
- **Fix:** Created separate CodableMatchState.swift in Models/ with full bi-directional conversion
- **Files modified:** BadmintonEye/BadmintonEye/Models/CodableMatchState.swift
- **Verification:** Project builds, JSON serialization works
- **Committed in:** `ed5ff9d` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Standard separation of concerns. No scope creep.

## Issues Encountered
None beyond the CodableMatchState extraction documented above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- iPhone app is complete and buildable for iOS Simulator
- App works fully offline with zero network calls (SCORE-08 satisfied)
- Ready for Plan 03 (match history and additional features) or Phase 2 (Watch app)
- SwiftData persistence layer ready for future CloudKit sync (Phase 4)

## Self-Check: PASSED

- All 12 files verified present on disk
- Commit `ed5ff9d` (Task 1) verified in git log
- Commit `2f14369` (Task 2) verified in git log
- Xcode build succeeds on iPhone 17 Pro simulator
- 44 ScoringEngine tests still passing

---
*Phase: 01-scoring-engine*
*Completed: 2026-03-28*
