# Technology Stack: v1.2 Haptic Feedback, BWF 3x15, Multi-Camera

**Project:** Badminton Eye
**Researched:** 2026-03-29
**Scope:** NEW capabilities only for v1.2 milestone

## Existing Stack (DO NOT CHANGE)

Already validated: Swift 6, SwiftUI, SwiftData + CloudKit, WatchConnectivity, Core ML, StoreKit 2, ActivityKit, HealthKit, AVFoundation (240fps delegate capture via CircularFrameBuffer), Vision framework VNCoreMLRequest, ScoringEngine Swift Package (pure struct state machine, 44 tests). Zero external dependencies.

---

## Stack Additions

### 1. Haptic Feedback on Score Events (iPhone)

| Technology | Version | Purpose | Why This, Not That |
|------------|---------|---------|-----|
| `UIImpactFeedbackGenerator` | UIKit, iOS 10+ (available iOS 17+) | Standard point-scored haptic | Use this, NOT CoreHaptics. `UIImpactFeedbackGenerator` is the correct tool for discrete UI feedback events (button taps, score changes). CoreHaptics is for continuous/complex patterns (game controllers, musical instruments) and requires engine lifecycle management (`CHHapticEngine.start()`, error handling for audio session conflicts). Scoring taps are discrete events -- impact generators are simpler, more reliable, and battery-efficient. |
| `UINotificationFeedbackGenerator` | UIKit, iOS 10+ | Game-won and match-won haptics | Provides `.success`, `.warning`, `.error` patterns. `.success` for game won (distinct double-tap feel), `.warning` for match complete (stronger attention-grab). These semantic patterns are designed by Apple's haptic team for exactly these "outcome notification" moments. |
| `WKInterfaceDevice.play(_:)` | watchOS 2+ | Watch haptics (ALREADY EXISTS) | The Watch already has haptics in `WatchScoringView.swift` (lines 63-74): `.click` for points, `.success` for game end, `.notification` for match end. No changes needed on watchOS. The v1.2 work is iPhone-only. |

**Why NOT CoreHaptics (CHHapticEngine):**

CoreHaptics would be overengineering for this use case. The downsides:
- Requires creating and managing a `CHHapticEngine` instance (lifecycle, error handling)
- Engine can fail to start if audio session is in use (conflict with AVFoundation capture during Hawk Eye)
- Requires building `CHHapticPattern` with intensity/sharpness curves
- Battery cost is higher for custom patterns vs. system feedback generators
- Apple's HIG explicitly recommends `UIFeedbackGenerator` for "brief, single-instance feedback"

`UIFeedbackGenerator` subclasses are fire-and-forget. No engine, no lifecycle, no audio session conflicts.

**API Details:**

```swift
// Prepare generators once (call in viewDidAppear or onAppear)
let pointHaptic = UIImpactFeedbackGenerator(style: .light)
let gameWonHaptic = UINotificationFeedbackGenerator()
let matchWonHaptic = UINotificationFeedbackGenerator()

// On point scored:
pointHaptic.impactOccurred()

// On game won:
gameWonHaptic.notificationOccurred(.success)

// On match won:
matchWonHaptic.notificationOccurred(.warning)
```

**Preparation optimization:** Call `.prepare()` on generators before the expected trigger to reduce latency. For scoring, call `pointHaptic.prepare()` after each tap (preparing for the next one). This pre-spins the Taptic Engine, reducing feedback latency from ~50ms to ~10ms.

**Integration point:** `LiveMatchViewModel.scorePoint(for:)` is where state transitions happen. The haptic trigger belongs in the VIEW layer (`LiveMatchView`), not the view model, because:
1. Haptics are a UI concern, not business logic
2. The view model is shared with Watch (which has its own haptic system)
3. SwiftUI's `.sensoryFeedback()` modifier (iOS 17+) is the cleanest integration

**SwiftUI-native alternative (RECOMMENDED):**

iOS 17 introduced `.sensoryFeedback()` modifier, which is even cleaner than UIKit generators:

```swift
// In LiveMatchView body:
.sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.6), trigger: currentTotalScore)
```

However, `.sensoryFeedback` has a limitation: it triggers on ANY change to the trigger value, with no way to distinguish point vs. game-end vs. match-end. For differentiated haptics (light tap for points, stronger for game/match end), use UIKit generators called from `.onChange(of:)`.

**Recommended approach:** Use `.onChange(of:)` in `LiveMatchView` to detect score changes and game/match transitions, then fire the appropriate UIKit haptic generator. This mirrors the existing Watch pattern in `WatchScoringView.playHaptic(gamesBefore:)`.

#### User Preference Toggle

Store haptic preference in `@AppStorage("hapticFeedbackEnabled")`. Add a Toggle in `SettingsView` under a new "Match Preferences" section. Default to ON -- haptic feedback is expected behavior in sports scoring apps.

---

### 2. BWF 3x15 Scoring Format (ScoringEngine)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| No new framework | N/A | Pure logic change in ScoringEngine | The 3x15 format is a rules change, not a technology change. All modifications are within the existing pure-struct state machine. |

**What is BWF 3x15:**

The BWF has been trialing a new scoring format: best-of-3 games to 15 points (instead of 21), with deuce at 14-14, cap at 17 (instead of 29/30). Side switch at 8 in the third game (instead of 11). No other rule changes -- service rotation, doubles rules, etc. remain identical.

**ScoringEngine changes needed:**

The current `BWFRules.swift` hardcodes thresholds:
- `isDeuce`: checks `>= 20` -- needs to become format-aware
- `isAtCap`: checks `== 29` -- needs to become format-aware
- `isGameWon`: checks `< 21` and `== 30` -- needs to become format-aware
- `shouldSwitchSides`: checks `== 11` -- needs to become format-aware

**Recommended approach: `ScoringRuleSet` struct**

```swift
public struct ScoringRuleSet: Codable, Sendable, Equatable {
    public let pointsToWin: Int      // 21 or 15
    public let deuceThreshold: Int   // 20 or 14
    public let capScore: Int         // 29 or 16 (cap at capScore+1)
    public let maxScore: Int         // 30 or 17
    public let thirdGameSwitch: Int  // 11 or 8
    public let gamesToWin: Int       // 2 (unchanged for both formats)

    public static let standard21 = ScoringRuleSet(
        pointsToWin: 21, deuceThreshold: 20, capScore: 29,
        maxScore: 30, thirdGameSwitch: 11, gamesToWin: 2
    )
    public static let bwf15 = ScoringRuleSet(
        pointsToWin: 15, deuceThreshold: 14, capScore: 16,
        maxScore: 17, thirdGameSwitch: 8, gamesToWin: 2
    )
}
```

Add `ruleSet: ScoringRuleSet` to `MatchState`. Replace all hardcoded numbers in `BWFRules.swift` with `ruleSet.xxx` properties. Factory methods (`newSinglesMatch`, etc.) take an optional `ruleSet` parameter defaulting to `.standard21`.

**Why a struct, not an enum:** A struct allows future flexibility (e.g., casual "first to 11" games, custom tournament formats) without breaking the API. Enums would require adding cases and updating all switch statements.

**Impact on existing tests:** All 44 tests use the default 21-point format. They should continue to pass unchanged because the default remains `.standard21`. Add new test file `ThreeByFifteenScoringTests.swift` with parallel tests for the 15-point format.

**Match setup UI change:** Add a segmented picker or toggle in `MatchSetupView` between "21-Point (Standard)" and "15-Point (BWF 3x15)". Store user's last selection in `@AppStorage("preferredScoringFormat")` so it persists.

**Data model impact:** `PersistedMatch` needs a `scoringFormat: String` field to record which rule set was used. The existing `format` field stores `singles/doubles/mixed` (match type), not scoring format. Add a separate field.

**Live Activity impact:** The `MatchActivityAttributes` currently shows "Game X" -- no change needed since both formats are best-of-3. The score display works regardless of target score.

**Watch sync impact:** `CodableMatchState` serializes the full `MatchState`. Adding `ruleSet` to `MatchState` means it will be included in the JSON payload automatically. Watch display is score-agnostic (just shows numbers), so no Watch UI changes needed.

---

### 3. Multi-Camera Hawk Eye (AVFoundation)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| `AVCaptureMultiCamSession` | iOS 13+ (available iOS 17+) | Simultaneous capture from 2+ cameras | Only API that allows concurrent frame delivery from multiple cameras. Standard `AVCaptureSession` is single-camera only. |
| `AVCaptureDevice.DiscoverySession` | iOS 17+ | Enumerate available cameras for multi-cam | Needed to find which cameras support simultaneous use with `AVCaptureMultiCamSession.isMultiCamSupported`. |

**What AVCaptureMultiCamSession provides:**

`AVCaptureMultiCamSession` is a subclass of `AVCaptureSession` that supports multiple `AVCaptureDeviceInput` instances simultaneously. Each input gets its own `AVCaptureVideoDataOutput` with independent delegate callbacks on separate dispatch queues.

**Device compatibility (CRITICAL CONSTRAINT):**

| Device | Multi-Cam Supported | Cameras Available |
|--------|---------------------|-------------------|
| iPhone 15 Pro / Pro Max | YES | Wide + Ultra-Wide + Telephoto (any 2 simultaneous) |
| iPhone 14 Pro / Pro Max | YES | Wide + Ultra-Wide + Telephoto (any 2 simultaneous) |
| iPhone 13 Pro+ | YES | Wide + Ultra-Wide (2 simultaneous) |
| iPhone 13/14/15 (non-Pro) | YES (limited) | Wide + Ultra-Wide (2 simultaneous, may reduce resolution) |
| iPhone SE, older than 13 | NO | Single camera only |
| iPad Pro (M1+) | YES | Wide + Ultra-Wide |

Multi-cam requires A12 Bionic or later. At iOS 17+ minimum, practically all supported devices have A12+, but non-Pro iPhones may have reduced FPS in multi-cam mode.

**IMPORTANT: Multi-cam does NOT mean multiple physical phones.**

Re-reading the project requirement: "Multi-camera angle support for higher Hawk Eye confidence." This could mean:

**(A) Multiple cameras on ONE device** (AVCaptureMultiCamSession) -- e.g., wide + ultra-wide simultaneously for wider court coverage.

**(B) Multiple separate devices/phones** each recording a different angle, then combining analyses.

**(C) Multiple pre-recorded videos** from different angles, analyzed sequentially and results merged.

**Recommendation: Implement option (C) first, then (A) as enhancement.**

Option (C) -- multiple pre-recorded videos -- is simpler, works on ALL devices, and delivers the core value (higher confidence from multiple angles). The user records from angle 1, then angle 2, then the app merges trajectory data. This requires:
- No new AVFoundation APIs (existing `HawkEyePipeline` + `AVAssetReader` already works)
- A new `MultiAngleAnalyzer` that runs the pipeline on each video, then merges observations
- A calibration profile per angle (the app already supports `CalibrationProfile`)

Option (A) -- `AVCaptureMultiCamSession` -- is the premium upgrade for Pro devices. Records two angles simultaneously from one tripod-mounted phone. This requires:
- Replace `AVCaptureSession` with `AVCaptureMultiCamSession` in `VideoCaptureManager`
- Two `AVCaptureVideoDataOutput` instances, one per camera
- Two `CircularFrameBuffer` instances
- Separate calibration for each camera's field of view

**API for Multi-Cam (Option A):**

```swift
// Check device support
guard AVCaptureMultiCamSession.isMultiCamSupported else {
    // Fall back to single camera
    return
}

let multiSession = AVCaptureMultiCamSession()

// Add wide camera
let wideDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)!
let wideInput = try AVCaptureDeviceInput(device: wideDevice)
multiSession.addInputWithNoConnections(wideInput)

// Add ultra-wide camera
let ultraDevice = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)!
let ultraInput = try AVCaptureDeviceInput(device: ultraDevice)
multiSession.addInputWithNoConnections(ultraInput)

// Create outputs and connections manually
let wideOutput = AVCaptureVideoDataOutput()
wideOutput.setSampleBufferDelegate(wideDelegate, queue: wideQueue)
multiSession.addOutputWithNoConnections(wideOutput)

let ultraOutput = AVCaptureVideoDataOutput()
ultraOutput.setSampleBufferDelegate(ultraDelegate, queue: ultraQueue)
multiSession.addOutputWithNoConnections(ultraOutput)

// Create connections (multi-cam requires explicit port connections)
let widePorts = wideInput.ports(for: .video, sourceDeviceType: .builtInWideAngleCamera, sourceDevicePosition: .back)
let wideConnection = AVCaptureConnection(inputPorts: widePorts, output: wideOutput)
multiSession.addConnection(wideConnection)

let ultraPorts = ultraInput.ports(for: .video, sourceDeviceType: .builtInUltraWideCamera, sourceDevicePosition: .back)
let ultraConnection = AVCaptureConnection(inputPorts: ultraPorts, output: ultraOutput)
multiSession.addConnection(ultraConnection)
```

**FPS constraint in multi-cam mode:** When running two cameras simultaneously, the system may limit each camera to 30fps or 60fps (not 240fps). This is a hardware bandwidth limitation. The confidence gain from two angles may offset the FPS loss, but this needs profiling on real devices.

**Confidence merging strategy:**

When two cameras observe the same shuttle trajectory:
1. Run `HawkEyePipeline.analyze()` independently for each camera's video
2. Each produces a `HawkEyeResult` with trajectory, landing point, and confidence
3. `MultiAngleAnalyzer` merges: if both agree on in/out, confidence = max(conf1, conf2) * 1.2 (capped at 1.0). If they disagree, confidence = 0.0 and result = "inconclusive"
4. The merged result is what the user sees

---

## Supporting Libraries (Already Available)

| Library | Source | Purpose | Notes |
|---------|--------|---------|-------|
| `UIKit` (UIFeedbackGenerator) | Apple framework, already linked | Haptic feedback on iPhone | UIKit is always available in SwiftUI apps on iOS. No additional linking needed. |
| `SwiftUI .sensoryFeedback()` | iOS 17+ built-in | Alternative haptic API | Available but less flexible than UIKit generators for differentiated feedback. |
| `WatchKit` | Already linked | Watch haptics | Already implemented in `WatchScoringView.swift`. No changes. |

**No new external dependencies.** The v1.2 stack remains 100% Apple-native with zero third-party packages.

---

## Integration Points with Existing Code

### Haptic Feedback

| Existing File | Change Needed |
|---------------|---------------|
| `LiveMatchView.swift` | Add `.onChange(of:)` handlers that fire haptics on score change, game end, match end. Mirror the pattern from `WatchScoringView.playHaptic()`. |
| `SettingsView.swift` | Add "Match Preferences" section with haptic toggle. |
| `LiveMatchViewModel.swift` | NO CHANGES. Haptics are a view-layer concern. |
| `WatchScoringView.swift` | NO CHANGES. Watch haptics already work. |

### BWF 3x15 Scoring

| Existing File | Change Needed |
|---------------|---------------|
| `ScoringEngine/Types.swift` | Add `ScoringRuleSet` struct. |
| `ScoringEngine/MatchState.swift` | Add `ruleSet: ScoringRuleSet` property. Update factory methods to accept optional rule set. |
| `ScoringEngine/BWFRules.swift` | Replace hardcoded `20`, `21`, `29`, `30`, `11` with `ruleSet.xxx` properties. |
| `ScoringEngine/MatchEngine.swift` | No direct changes (uses computed properties from BWFRules). |
| `MatchSetupView.swift` | Add scoring format picker. |
| `SwiftDataModels.swift` (PersistedMatch) | Add `scoringFormat: String` field. |
| `CodableMatchState.swift` | Add `ruleSet` to encoding/decoding. |
| `GameDotsIndicator` (WatchScoringView) | Currently hardcodes `totalGames: 3` -- still correct for 3x15. No change. |

### Multi-Camera Hawk Eye

| Existing File | Change Needed |
|---------------|---------------|
| `VideoCaptureManager.swift` | Add `AVCaptureMultiCamSession` path (guarded by `isMultiCamSupported`). Existing single-cam path unchanged. |
| `CircularFrameBuffer.swift` | Instantiate two buffers (one per camera) for multi-cam mode. |
| `HawkEyePipeline.swift` | Add `analyze(videoURLs: [URL], calibrations: [CalibrationProfile])` overload for multi-angle. |
| `ChallengeVideoView.swift` | Add UI for selecting "single camera" vs "multi-angle" mode. Multi-angle shows two video previews. |
| `CalibrationProfile.swift` | Support multiple calibration profiles (one per camera angle). May already work since it is a SwiftData `@Model` that can have multiple instances. |
| `TrajectoryCalculator.swift` | No changes. Called once per angle; merging happens in new `MultiAngleAnalyzer`. |

---

## What NOT to Add

| Technology | Why NOT |
|------------|---------|
| **CoreHaptics (CHHapticEngine)** | Overkill for discrete score feedback. Engine lifecycle conflicts with AVFoundation audio session during Hawk Eye recording. UIFeedbackGenerator is simpler, more reliable, and Apple-recommended for this use case. |
| **Multipeer Connectivity** | If "multi-camera" means multiple phones, Multipeer is tempting but adds massive complexity (discovery, pairing, time sync, data transfer). Use pre-recorded video import instead. |
| **ARKit / RealityKit** | Some badminton apps use AR for court overlay. Not needed -- the homography-based calibration in `TrajectoryCalculator` already maps image-space to court-space without AR. AR would add camera access conflicts. |
| **External scoring rule engines** | The ScoringEngine is 4 files, pure structs, 44 tests. Adding a generic rules engine library would be absurd for a 2-constant change. |
| **Third-party haptic libraries** | Libraries like "CoreHapticsUnity" or custom pattern designers are for game engines. UIFeedbackGenerator covers all needed patterns. |
| **AVCaptureMultiCamSession for v1.2 MVP** | Start with sequential multi-angle (Option C). Multi-cam simultaneous capture is a v1.3 enhancement after validating that multi-angle actually improves confidence. |
| **New SwiftData models for camera angles** | Reuse existing `CalibrationProfile` model. Each calibration is already per-angle implicitly. Just allow multiple profiles and label them. |

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| iPhone haptics | UIImpactFeedbackGenerator + UINotificationFeedbackGenerator | CoreHaptics CHHapticEngine | CHHapticEngine has lifecycle management, audio session conflicts with AVFoundation, and is designed for continuous/complex patterns, not discrete taps. |
| iPhone haptics (SwiftUI) | `.onChange` + UIKit generators | `.sensoryFeedback()` modifier | `.sensoryFeedback` cannot differentiate between point/game/match end -- it fires the same pattern for any trigger change. |
| Scoring rules | `ScoringRuleSet` struct on MatchState | Enum with `.standard21` / `.bwf15` cases | Struct is more extensible for future casual formats. Enum requires updating all switches when adding formats. |
| Scoring rules | Parameterized thresholds | Separate `BWF15Rules.swift` file with duplicated logic | Code duplication. The logic is identical; only thresholds differ. Parameterize, don't duplicate. |
| Multi-camera | Sequential multi-angle analysis | Simultaneous AVCaptureMultiCamSession | Simultaneous multi-cam limits FPS, requires Pro devices, and is complex. Sequential analysis works on all devices and validates the concept first. |
| Multi-camera | Import multiple videos | Multipeer Connectivity phone-to-phone | Multipeer adds pairing UX, time synchronization (critical for trajectory), and network reliability issues. Pre-recorded videos sidestep all of this. |

---

## Installation

### iOS App (NO new package dependencies)

```swift
// Package.swift -- NO CHANGES
// ScoringEngine package -- internal changes only, no new dependencies
// All v1.2 capabilities use built-in Apple frameworks:
//   - UIKit (UIFeedbackGenerator for haptics)
//   - AVFoundation (AVCaptureMultiCamSession, already linked)
```

### ScoringEngine Package

```swift
// ScoringEngine/Package.swift -- NO CHANGES
// Add ScoringRuleSet struct and update BWFRules.swift thresholds
// Add ThreeByFifteenScoringTests.swift test file
```

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| UIFeedbackGenerator for haptics | HIGH | Stable API since iOS 10. Well-documented. Already used pattern on watchOS side. |
| CoreHaptics avoidance rationale | HIGH | Apple HIG explicitly distinguishes feedback generators (discrete) from CoreHaptics (continuous/complex). |
| BWF 3x15 rules (15 pts, deuce 14, cap 17, switch at 8) | MEDIUM | Based on training data about BWF scoring experiments. The exact thresholds should be verified against official BWF announcement. PROJECT.md mentions "April 2026 vote" so rules may not be finalized yet. |
| ScoringRuleSet parameterization approach | HIGH | Standard pattern for configurable rules engines. No framework dependency. |
| AVCaptureMultiCamSession API | HIGH | Available since iOS 13, stable API. The `isMultiCamSupported` check and port-based connection pattern are well-documented. |
| Multi-cam FPS limitations | MEDIUM | Training data indicates reduced FPS in multi-cam mode, but exact limits vary by device and iOS version. Needs device profiling. |
| Sequential multi-angle as MVP | HIGH | Pure architectural decision. Uses only existing proven APIs (AVAssetReader, HawkEyePipeline). No new framework risk. |

---

## Sources

- Apple UIKit UIFeedbackGenerator documentation (training data knowledge, stable API since iOS 10)
- Apple CoreHaptics framework documentation (training data knowledge)
- Apple Human Interface Guidelines: Playing Haptics (training data knowledge)
- Apple AVFoundation AVCaptureMultiCamSession documentation (training data knowledge, stable API since iOS 13)
- Existing codebase: `WatchScoringView.swift` (existing haptic pattern), `VideoCaptureManager.swift`, `HawkEyePipeline.swift`, `BWFRules.swift`, `MatchState.swift`, `MatchEngine.swift`
- BWF scoring format experiments (training data knowledge -- MEDIUM confidence, verify against official BWF sources)

**Note:** WebSearch was unavailable during this research session. BWF 3x15 exact thresholds (deuce at 14, cap at 17, third-game switch at 8) are based on training data about BWF experimental formats. Verify these numbers against the official BWF announcement before implementing. All Apple API recommendations are HIGH confidence from well-established, stable frameworks.
