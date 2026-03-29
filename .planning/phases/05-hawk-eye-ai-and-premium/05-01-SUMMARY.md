---
phase: 05-hawk-eye-ai-and-premium
plan: 01
subsystem: ui, video, camera
tags: [AVFoundation, SwiftData, SwiftUI, PhotosUI, AVKit, court-calibration, video-capture]

requires:
  - phase: 01-scoring-engine
    provides: MatchState with currentGame scores and matchPhase for Challenge button visibility
  - phase: 03-match-data-and-player-profiles
    provides: SwiftData modelContainer and PersistedMatch pattern for CalibrationProfile
provides:
  - CalibrationProfile SwiftData model for court corner persistence
  - VideoCaptureManager AVFoundation service for video recording
  - CourtCalibrationView with 4-corner tap calibration overlay
  - ChallengeVideoView with record/select video options
  - Challenge button in LiveMatchView toolbar with 10s countdown
affects: [05-03-trajectory-engine, 05-04-hawk-eye-analysis]

tech-stack:
  added: [AVFoundation, PhotosUI, AVKit]
  patterns: [UIViewRepresentable camera preview, @preconcurrency AVFoundation import for Swift 6]

key-files:
  created:
    - BadmintonEye/BadmintonEye/Models/CalibrationProfile.swift
    - BadmintonEye/BadmintonEye/Services/VideoCaptureManager.swift
    - BadmintonEye/BadmintonEye/Views/CourtCalibrationView.swift
    - BadmintonEye/BadmintonEye/Views/ChallengeVideoView.swift
  modified:
    - BadmintonEye/BadmintonEye/Views/LiveMatchView.swift
    - BadmintonEye/BadmintonEye/App/BadmintonEyeApp.swift
    - BadmintonEye/BadmintonEye.xcodeproj/project.pbxproj

key-decisions:
  - "CameraPreviewView as UIViewRepresentable wrapping AVCaptureVideoPreviewLayer for SwiftUI integration"
  - "@preconcurrency import AVFoundation to suppress Swift 6 Sendable warnings for AVCaptureSession"
  - "Challenge countdown tracks currentGame.scoreA + scoreB changes via onChange to reset 10s timer"
  - "CalibrationProfile uses JSON-encoded CodablePoint wrapper for CGPoint storage in SwiftData Data fields"

patterns-established:
  - "UIViewRepresentable camera preview: CameraPreviewView wraps AVCaptureVideoPreviewLayer with coordinator for frame updates"
  - "Challenge button countdown: Timer-based 10s window after each point scored, disabled when expired"

requirements-completed: [HAWK-01, HAWK-02, HAWK-03]

duration: 9min
completed: 2026-03-29
---

# Phase 5 Plan 1: Court Calibration and Challenge Video Pipeline Summary

**Court 4-corner calibration with SwiftData persistence, AVFoundation video capture manager, and Challenge button with 10s countdown timer integrated into LiveMatchView toolbar**

## Performance

- **Duration:** 9 min
- **Started:** 2026-03-29T12:15:33Z
- **Completed:** 2026-03-29T12:25:22Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- CalibrationProfile SwiftData model stores 4 court corner CGPoints as JSON Data with venue name and capture dimensions
- VideoCaptureManager captures up to 10-second video clips via AVFoundation with auto-stop and temp file management
- CourtCalibrationView provides full-screen camera preview with numbered green dots at each tap location and Confirm/Recalibrate flow
- ChallengeVideoView offers Record Clip (camera) and Select from Library (PhotosPicker) with calibration prerequisite check
- Challenge button in LiveMatchView appears only during active play with yellow countdown badge resetting after each rally

## Task Commits

Each task was committed atomically:

1. **Task 1: CalibrationProfile model and VideoCaptureManager service** - `d3ba461` (feat) [pre-existing from 05-02 Rule 3 deviation]
2. **Task 2: CourtCalibrationView, ChallengeVideoView, and Challenge button in LiveMatchView** - `7efdd1b` (feat)

## Files Created/Modified
- `BadmintonEye/BadmintonEye/Models/CalibrationProfile.swift` - SwiftData @Model with 4 corner Data? fields, CodablePoint encoding, setCorners/corners computed property
- `BadmintonEye/BadmintonEye/Services/VideoCaptureManager.swift` - @Observable AVFoundation capture manager with 10s auto-stop, temp file output, AVCaptureFileOutputRecordingDelegate
- `BadmintonEye/BadmintonEye/Views/CourtCalibrationView.swift` - Full-screen camera overlay with tap-to-place numbered green dots, venue name TextField, Confirm saves to SwiftData
- `BadmintonEye/BadmintonEye/Views/ChallengeVideoView.swift` - Sheet with calibration check, Record Clip camera UI with duration counter, PhotosPicker for library selection, video review with placeholder analysis
- `BadmintonEye/BadmintonEye/Views/LiveMatchView.swift` - Added Challenge button with eye.trianglebadge.exclamationmark icon, 10s countdown badge, sheet presentation of ChallengeVideoView
- `BadmintonEye/BadmintonEye/App/BadmintonEyeApp.swift` - Added CalibrationProfile.self to modelContainer schema
- `BadmintonEye/BadmintonEye.xcodeproj/project.pbxproj` - Added all new Swift files and AVFoundation.framework, camera/microphone/photo library usage descriptions

## Decisions Made
- CameraPreviewView as UIViewRepresentable wrapping AVCaptureVideoPreviewLayer for SwiftUI integration
- @preconcurrency import AVFoundation to suppress Swift 6 Sendable warnings for AVCaptureSession
- Challenge countdown tracks currentGame.scoreA + scoreB changes via onChange to reset 10s timer after each point
- CalibrationProfile uses JSON-encoded CodablePoint wrapper for CGPoint storage in SwiftData Data fields
- NSCameraUsageDescription, NSMicrophoneUsageDescription, NSPhotoLibraryUsageDescription added to Info.plist build settings

## Deviations from Plan

### Note on Prior Execution

Task 1 artifacts (CalibrationProfile.swift, VideoCaptureManager.swift, stub views) were already committed as part of a prior 05-02 plan execution (commit d3ba461) as a Rule 3 auto-fix to unblock the SubscriptionManager build. The full CourtCalibrationView and ChallengeVideoView implementations were committed in 388af41. This execution verified all existing code, added the @preconcurrency fix for Swift 6 compliance, and implemented the Challenge button integration into LiveMatchView which was not previously done.

**Total deviations:** 0 new auto-fixes required. Prior Rule 3 deviation acknowledged.
**Impact on plan:** No scope creep. All plan objectives met.

## Issues Encountered
- iPhone 16 simulator not available -- used iPhone 17 Pro simulator destination for build verification
- Task 1 files pre-existed from prior 05-02 execution -- verified correctness and proceeded to Task 2

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Court calibration and video capture pipeline ready for Plan 03 trajectory engine integration
- CalibrationProfile corners available for coordinate mapping in AI analysis
- VideoCaptureManager.capturedVideoURL ready to feed into shuttle detection model
- Challenge button wired and functional, "Analyze" button placeholder ready for Plan 03 connection

## Self-Check: PASSED

- All 5 key files verified present on disk
- Commit d3ba461 (Task 1) verified in git history
- Commit 7efdd1b (Task 2) verified in git history
- Build succeeds on iPhone 17 Pro simulator

---
*Phase: 05-hawk-eye-ai-and-premium*
*Completed: 2026-03-29*
