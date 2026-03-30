---
phase: 05-hawk-eye-ai-and-premium
plan: 03
subsystem: ai, ui
tags: [hawk-eye, trajectory, homography, core-ml-placeholder, storekit, premium-gating, animation]

requires:
  - phase: 05-hawk-eye-ai-and-premium/01
    provides: CalibrationProfile, VideoCaptureManager, ChallengeVideoView, CourtCalibrationView
  - phase: 05-hawk-eye-ai-and-premium/02
    provides: SubscriptionManager, PaywallView
provides:
  - HawkEyePipeline service with placeholder shuttle detection and trajectory computation
  - TrajectoryCalculator with homography transform, trajectory fitting, in/out determination, confidence scoring
  - TrajectoryReplayView with animated court diagram, trajectory path, and color-coded landing spot
  - Full end-to-end challenge flow from video capture through analysis to animated result display
  - Premium gating on Challenge button with lock icon and PaywallView for free users
affects: [05-hawk-eye-ai-and-premium/04]

tech-stack:
  added: [AVAssetImageGenerator, Canvas/CoreGraphics court rendering]
  patterns: [placeholder AI with TODO markers, homography-based coordinate transform, trim-based path animation]

key-files:
  created:
    - BadmintonEye/BadmintonEye/Services/HawkEyePipeline.swift
    - BadmintonEye/BadmintonEye/Services/TrajectoryCalculator.swift
    - BadmintonEye/BadmintonEye/Views/TrajectoryReplayView.swift
  modified:
    - BadmintonEye/BadmintonEye/Views/ChallengeVideoView.swift
    - BadmintonEye/BadmintonEye/Views/LiveMatchView.swift
    - BadmintonEye/BadmintonEye.xcodeproj/project.pbxproj

key-decisions:
  - "Placeholder shuttle detection generates 8-15 simulated positions along parabolic arc with +-5px noise for realistic UI testing"
  - "Gaussian elimination with partial pivoting for 8x8 homography solve -- no external linear algebra dependency"
  - "Quadratic y-component + linear x-component for trajectory fitting (gravity-like descent model)"
  - "Computed property for SubscriptionManager access in LiveMatchView to avoid polluting synthesized memberwise init"

patterns-established:
  - "Placeholder AI pattern: TODO-marked simulation with clear replacement path for real Core ML model"
  - "Canvas-based court rendering for 2D diagrams (no UIKit dependency in SwiftUI views)"
  - "trim(from:to:) animation pattern for progressive path reveal"

requirements-completed: [HAWK-04, HAWK-05, HAWK-06]

duration: 6min
completed: 2026-03-29
---

# Phase 5 Plan 3: Hawk Eye Pipeline and Trajectory Replay Summary

**Hawk Eye analysis pipeline with placeholder shuttle detection, homography-based trajectory computation, animated court replay with color-coded IN/OUT/UNCERTAIN landing, and premium-gated challenge flow**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-29T12:28:37Z
- **Completed:** 2026-03-29T12:34:31Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- HawkEyePipeline orchestrates video analysis with placeholder shuttle detection, homography transform, trajectory fitting, and confidence scoring
- TrajectoryReplayView provides dramatic animated court overlay with trajectory path reveal, pulsing landing spot, and color-coded IN/OUT result
- ChallengeVideoView wired end-to-end: analyze button triggers pipeline, progress overlay with shimmer text, fullScreenCover presents replay
- LiveMatchView gates Challenge behind premium: lock icon badge for free users, PaywallView instead of challenge flow

## Task Commits

Each task was committed atomically:

1. **Task 1: HawkEyePipeline and TrajectoryCalculator services** - `fbae723` (feat)
2. **Task 2: TrajectoryReplayView and full challenge flow wiring with premium gating** - `5fc8d59` (feat)

## Files Created/Modified
- `BadmintonEye/BadmintonEye/Services/TrajectoryCalculator.swift` - CourtPoint, LandingResult, HawkEyeResult types; homography, trajectory fitting, in/out, confidence methods
- `BadmintonEye/BadmintonEye/Services/HawkEyePipeline.swift` - @Observable pipeline: frame extraction, placeholder detection, trajectory computation with artificial delays
- `BadmintonEye/BadmintonEye/Views/TrajectoryReplayView.swift` - Full-screen Hawk Eye replay with Canvas court, animated trajectory path, pulsing landing spot, confidence badges
- `BadmintonEye/BadmintonEye/Views/ChallengeVideoView.swift` - Wired HawkEyePipeline analyze, progress overlay, TrajectoryReplayView presentation, error handling
- `BadmintonEye/BadmintonEye/Views/LiveMatchView.swift` - Premium gating with lock icon badge, PaywallView sheet for free users
- `BadmintonEye/BadmintonEye.xcodeproj/project.pbxproj` - Added 3 new Swift files to project

## Decisions Made
- Placeholder shuttle detection generates 8-15 simulated positions along parabolic arc with +-5px noise for realistic UI testing
- Gaussian elimination with partial pivoting for 8x8 homography solve -- no external linear algebra dependency needed
- Quadratic y-component + linear x-component for trajectory fitting (gravity-like descent model)
- Computed property for SubscriptionManager access in LiveMatchView to avoid polluting synthesized memberwise init

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed let-to-var for videoDuration/videoFPS in HawkEyePipeline**
- **Found during:** Task 1 (build verification)
- **Issue:** Swift compiler error -- let bindings cannot be reassigned in catch block fallback
- **Fix:** Changed `let videoDuration` and `let videoFPS` to `var`
- **Files modified:** HawkEyePipeline.swift
- **Verification:** Build succeeded
- **Committed in:** fbae723

**2. [Rule 1 - Bug] Fixed synthesized init accessibility in LiveMatchView**
- **Found during:** Task 2 (build verification)
- **Issue:** Adding `private var subscriptionManager` property caused synthesized memberwise init to become private, breaking callers
- **Fix:** Changed stored property to computed property returning SubscriptionManager.shared
- **Files modified:** LiveMatchView.swift
- **Verification:** Build succeeded
- **Committed in:** 5fc8d59

---

**Total deviations:** 2 auto-fixed (2 bugs)
**Impact on plan:** Both auto-fixes were simple compiler error corrections. No scope creep.

## Issues Encountered
- iOS Simulator name "iPhone 16" not available on this Xcode version; switched to "iPhone 17 Pro" -- resolved immediately

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Full Hawk Eye challenge flow is operational end-to-end with placeholder AI
- Ready for Plan 04 (final integration, polish, onboarding)
- Real Core ML model can be dropped into HawkEyePipeline by replacing the placeholder detection section (marked with TODO comments)

---
## Self-Check: PASSED

- FOUND: BadmintonEye/BadmintonEye/Services/HawkEyePipeline.swift
- FOUND: BadmintonEye/BadmintonEye/Services/TrajectoryCalculator.swift
- FOUND: BadmintonEye/BadmintonEye/Views/TrajectoryReplayView.swift
- COMMIT: fbae723 (Task 1)
- COMMIT: 5fc8d59 (Task 2)

---
*Phase: 05-hawk-eye-ai-and-premium*
*Completed: 2026-03-29*
