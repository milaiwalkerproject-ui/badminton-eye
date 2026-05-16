# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Badminton Eye — native iOS app (iPhone + iPad) with Apple Watch companion for live badminton scoring, plus a premium "Hawk Eye" AI in/out challenge system. 100% Apple-native (Swift 6, SwiftUI, SwiftData + CloudKit, WatchConnectivity, Core ML, StoreKit 2, ActivityKit, HealthKit) with zero external Swift dependencies. The Hawk Eye Core ML model is trained offline via a separate Python (YOLO) pipeline under `hawkeye/`.

## Repo layout (big picture)

- `BadmintonEye/BadmintonEye.xcodeproj` — the Xcode project. Three app targets share this project:
  - `BadmintonEye` (iOS app)
  - `BadmintonEyeWatch` (watchOS companion)
  - `BadmintonEyeLiveActivity` (Lock Screen / Dynamic Island widget)
  - Tests live in `BadmintonEye/BadmintonEyeTests/`.
- `ScoringEngine/` — local Swift Package (`swift-tools-version: 6.0`, iOS 17 / watchOS 10) containing the pure scoring rules engine (`MatchEngine`, `MatchState`, `BWFRules`, `ServiceTracker`, `Types`). Consumed by the Xcode project as a local package and shared by the iOS and Watch targets. **All scoring logic lives here, not in the app target** — keep it free of UIKit/SwiftUI/SwiftData.
- `hawkeye/` — Python training/data pipeline (YOLO → Core ML) with subpackages for `annotate`, `augment`, `convert`, `court`, `datasets`, `models`, `preprocess`, `train`, `trajectory`, `validate`. Outputs the `.mlmodel` consumed by `BadmintonEye/Services/CoreMLShuttleDetector.swift`. Not built as part of the iOS build.
- `scripts/training/` — YOLO training entrypoint (`train.py`, `requirements.txt`, `ANNOTATION_GUIDE.md`).
- `appstore/` — App Store assets / submission material.
- `.planning/` — GSD planning workflow state (see "Planning workflow" below). Source of truth for current milestone, requirements, roadmap.

### iOS app internal structure (`BadmintonEye/BadmintonEye/`)

- `App/BadmintonEyeApp.swift` — `@main` entry, SwiftData container, CloudKit config.
- `Models/` — SwiftData `@Model` types (`SwiftDataModels.swift`), Codable DTOs for Watch sync (`SyncPayload.swift`, `CodableMatchState.swift`), `Player`, `CalibrationProfile`.
- `Services/` — non-UI infrastructure. Notable seams:
  - `WatchSyncManager` — bidirectional WatchConnectivity bridge. Score changes on either device flow through this; both sides apply via the shared `ScoringEngine.MatchEngine`.
  - `HawkEyePipeline` orchestrates `MultiCamCaptureManager` → `CircularFrameBuffer` (240fps) → `CoreMLShuttleDetector` (via `ShuttleDetecting` protocol; `PlaceholderShuttleDetector` is the test/dev stand-in) → `TrajectoryCalculator` → `ResultFusionService` (combines multiple camera angles, aligned by `AudioTemporalSync`).
  - `AuthManager`, `SubscriptionManager` (StoreKit 2, Hawk Eye is the paywalled feature), `HapticFeedbackService`, `LocalizationManager`.
- `ViewModels/` — `@MainActor` view models (watch side is `WatchMatchViewModel`).
- `Views/` — SwiftUI. `LiveMatchView` + `ScorePanel` are the scoring hot path; Hawk Eye flow is `CourtCalibrationView` → `ChallengeVideoView` → `MultiAngleAnalysisView` → `TrajectoryReplayView`.
- Localized into 9 languages (`en`, `da`, `hi`, `id`, `ja`, `ko`, `ms`, `th`, `zh-Hans`) via `*.lproj` — when adding user-facing strings, add to all `.strings` files.
- `Configuration.storekit` — local StoreKit testing config for the subscription.

## Build & test

The Xcode project resolves `ScoringEngine` as a local SwiftPM dependency, so opening `BadmintonEye.xcodeproj` is enough — do **not** add it as a separate workspace.

```bash
# List schemes / targets
xcodebuild -list -project BadmintonEye/BadmintonEye.xcodeproj

# Build the iOS app for the simulator
xcodebuild -project BadmintonEye/BadmintonEye.xcodeproj \
  -scheme BadmintonEye \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build

# Run the iOS app's unit tests (BadmintonEyeTests)
xcodebuild -project BadmintonEye/BadmintonEye.xcodeproj \
  -scheme BadmintonEye \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  test

# Run only the ScoringEngine package tests (targets iOS 17 / watchOS 10)
xcodebuild -scheme ScoringEngine \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  test

# Single test (XCTest filter: TestClass or TestClass/testMethod)
xcodebuild -scheme ScoringEngine \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:ScoringEngineTests/CustomScoringTests/testMidGameSwitchInFinalGame \
  test
```

Watch and Live Activity targets build via their own schemes (`BadmintonEyeWatch`, `BadmintonEyeLiveActivity`). For UI verification before PRs, use the `visual-qa` skill (build → simulator → screenshot).

## Hawk Eye / Python pipeline

```bash
pip install -r scripts/training/requirements.txt
python scripts/training/train.py        # YOLO training entrypoint
```

The pipeline produces a Core ML model consumed by `CoreMLShuttleDetector`. iOS builds do not depend on Python; only re-run when the detector model changes.

## Architecture invariants

- **Scoring rules are engine-only.** `ScoringEngine` is the single source of truth for match state transitions (BWF 21-point, 3×15, custom user-defined formats). Both the iOS app and Watch import it; never re-implement scoring inside a view or view model. `ScoringRules.isValid` gates custom formats — extend it (and its tests) when adding new rule parameters.
- **Watch sync is bidirectional and engine-driven.** A point recorded on either device is broadcast as a `SyncPayload` and re-applied through `MatchEngine` on the other side; UI state must derive from the engine, not from the payload directly.
- **Hawk Eye is composed via protocols** (`ShuttleDetecting`, with `CoreMLShuttleDetector` / `PlaceholderShuttleDetector`) so tests and previews don't need the real Core ML model. Wire new detectors through the protocol, not directly into `HawkEyePipeline`.
- **SwiftData + CloudKit** is the persistence story; models live in `Models/SwiftDataModels.swift`. CloudKit zone deletion is part of the account-deletion flow (App Store Guideline 5.1.1(v)) — see `AccountDeletedView` and `AccountDeletionTests`.
- **iOS 17 / watchOS 10 minimum**, Swift 6 strict concurrency. View models are `@MainActor`.

## Planning workflow (GSD)

This project uses the GSD planning skills under `.planning/`:

- `.planning/PROJECT.md` — what the project is and the **current milestone goal**. Read first.
- `.planning/ROADMAP.md`, `.planning/MILESTONES.md`, `.planning/REQUIREMENTS.md` — phase/milestone breakdown and validated requirement list.
- `.planning/STATE.md` — current phase position and accumulated context.
- `.planning/milestones/`, `.planning/research/` — per-milestone plans and research notes.

When the user invokes `/gsd:*` slash commands, those operate on this directory. Don't hand-edit phase files; use the GSD commands.

## Conventions worth knowing

- New user-facing strings → add to all 9 `*.lproj/Localizable.strings`.
- New scoring rules / edge cases → add tests under `ScoringEngine/Tests/ScoringEngineTests/` first; existing files are organized by concern (`SinglesScoringTests`, `DoublesScoringTests`, `MixedDoublesScoringTests`, `DeuceAndCapTests`, `GameTransitionTests`, `ServiceRotationTests`, `ThreeByFifteenTests`, `CustomScoringTests`, `UndoTests`).
- Account deletion / GDPR flow must wipe Keychain + SwiftData + UserDefaults + CloudKit zone; the regression test is `BadmintonEyeTests/AccountDeletionTests.swift`.
- Top-level files `wanman-debug.log`, `wanman-hourly-check.md`, `progress-report.md`, and the `.wanman/` directory are from an automation agent and are not part of the app — leave them alone unless explicitly asked.
