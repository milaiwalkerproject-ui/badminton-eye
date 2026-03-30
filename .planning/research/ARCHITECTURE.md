# Architecture Patterns: v1.3 Dual-Camera Capture, Audio Sync, Custom Scoring

**Domain:** iOS badminton scoring app with AI line calling
**Researched:** 2026-03-29
**Confidence:** HIGH (based on direct codebase analysis + iOS platform knowledge)

## Executive Summary

v1.3 introduces three features that each touch different architectural layers. Dual-camera capture requires the most invasive change (VideoCaptureManager must NOT be modified -- a new MultiCamCaptureManager is needed for AVCaptureMultiCamSession). Audio cross-correlation is a new standalone service that slots cleanly between capture and analysis. Custom scoring extends the already-parameterized ScoringRules struct with minimal engine changes but requires a new UI builder, SwiftData model, and CodableMatchState migration.

The key architectural insight: VideoCaptureManager currently owns a single AVCaptureSession. AVCaptureMultiCamSession is NOT a drop-in replacement -- it has different device requirements, different input/output topology, and different resource constraints. The recommended approach is to create a new MultiCamCaptureManager that composes two CircularFrameBuffers (one per camera), behind a CaptureCoordinator facade, while keeping the existing VideoCaptureManager intact as single-camera fallback for non-Pro devices.

## Current Architecture (As-Is)

```
MatchSetupView
  --> LiveMatchView / LiveMatchViewModel
        --> ScoringEngine (MatchState + MatchEngine) [separate SPM package]
              ScoringSystem enum: .standard21 | .threeByFifteen
              ScoringRules struct: parameterized thresholds (pointsToWin, deuce, cap, etc.)
              MatchEngine.apply: pure (MatchState, MatchEvent) -> MatchState
        --> VideoCaptureManager (single AVCaptureSession, back camera only)
              --> CircularFrameBuffer (10s rolling window, NSLock-synchronized)
        --> HawkEyePipeline (ShuttleDetecting protocol DI, frame-skip strategy)
              --> CoreMLShuttleDetector | PlaceholderShuttleDetector
              --> TrajectoryCalculator (homography + trajectory fitting)
        --> MultiAngleAnalysisView (sequential PhotosPicker import for 2nd angle)
              --> ResultFusionService (weighted confidence fusion of HawkEyeResult[])
```

### Key Characteristics
- **VideoCaptureManager:** Instantiated per challenge, owns one AVCaptureSession, one back camera, one CircularFrameBuffer (10s at up to 240fps). Delegate-based capture via AVCaptureVideoDataOutput on a single captureQueue.
- **HawkEyePipeline:** Analyzes one video URL at a time. Frame-skip interval of 4 at 240fps = 60 detections/sec. Max 150 frames analyzed.
- **MultiAngleAnalysisView:** Imports second angle AFTER primary analysis, via PhotosPicker. Sequential, not simultaneous. Uses a second HawkEyePipeline instance.
- **ResultFusionService:** Pure static function. Weighted average by confidence, 15% multi-view bonus, capped at 99%.
- **ScoringEngine:** Pure struct state machine in separate SPM package. ScoringSystem enum maps to ScoringRules static constants via `rules(for:)`. MatchEngine is a pure function with zero side effects.
- **CodableMatchState:** Manual Codable mirror of MatchState. `scoringSystem` is already optional (`ScoringSystem?`) for backward compat with v1.0/v1.1 JSON.

## Recommended Architecture (v1.3 To-Be)

```
MatchSetupView
  --> ScoringFormatPicker
        standard21 | threeByFifteen | .custom(CustomScoringConfig)
        "Create Custom Format" --> ScoringFormatBuilderView
  --> LiveMatchView / LiveMatchViewModel
        --> ScoringEngine (MatchState + MatchEngine) -- ScoringSystem gains .custom case
        --> CaptureCoordinator (NEW: facade over single-cam and multi-cam)
              --> VideoCaptureManager (UNCHANGED, single-cam fallback)
              --> MultiCamCaptureManager (NEW: AVCaptureMultiCamSession)
                    --> CircularFrameBuffer x2 (REUSED, one per camera)
                    --> Audio capture outputs (NEW: for cross-correlation)
        --> AudioSyncService (NEW: Accelerate/vDSP cross-correlation)
        --> HawkEyePipeline (UNCHANGED API, called once per angle)
        --> ResultFusionService (UNCHANGED)
        --> DualCameraAnalysisView (NEW: replaces sequential MultiAngleAnalysisView)
```

### Component Boundaries

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| **CaptureCoordinator** | Decides single-cam vs multi-cam based on device capability; exposes uniform capture API | LiveMatchViewModel, MultiCamCaptureManager, VideoCaptureManager |
| **MultiCamCaptureManager** | Manages AVCaptureMultiCamSession with two camera inputs + two audio inputs | CaptureCoordinator, CircularFrameBuffer (x2), AudioSyncService |
| **AudioSyncService** | Computes temporal offset between two audio tracks via cross-correlation | MultiCamCaptureManager (provides audio buffers), CaptureCoordinator (receives offset for PTS adjustment) |
| **CustomScoringConfig** | Codable struct holding user-defined scoring parameters (lives in ScoringEngine SPM) | ScoringSystem enum, ScoringRules.rules(for:) |
| **CustomScoringFormat** | SwiftData model storing saved custom formats (lives in app target) | MatchSetupView, converts to/from CustomScoringConfig |
| **ScoringFormatBuilderView** | UI for creating/editing custom scoring rules with validation | CustomScoringFormat, MatchSetupView |
| **DualCameraAnalysisView** | Dual-camera preview + synchronized analysis trigger | CaptureCoordinator, HawkEyePipeline, ResultFusionService |

## New Component: MultiCamCaptureManager

### Why Not Extend VideoCaptureManager

The existing VideoCaptureManager is tightly bound to AVCaptureSession (singular). AVCaptureMultiCamSession differs in critical ways:

1. **Device requirement:** Only available on devices where `AVCaptureMultiCamSession.isMultiCamSupported` returns true (A12+ chip, iPhone XS and later). Practically useful on Pro models for dual back cameras (wide + ultra-wide).
2. **Input topology:** Requires separate AVCaptureDeviceInput per camera, each connected to its own AVCaptureVideoDataOutput via AVCaptureConnection. You cannot share one output across two inputs.
3. **Separate dispatch queues:** AVFoundation REQUIRES each AVCaptureVideoDataOutput in a multi-cam session to use its own dispatch queue. Sharing a queue causes dropped frames. The existing single `captureQueue` pattern in VideoCaptureManager cannot be reused.
4. **Resource budget:** At 240fps on two cameras simultaneously, the ISP pipeline will throttle or drop frames. Realistic target: 120fps per camera in multi-cam mode.
5. **Format constraints:** Each camera can have a different format, but the system balances resources. You must query `AVCaptureDevice.DiscoverySession` to find valid camera pairs.

### Recommended Implementation

```swift
/// Manages simultaneous dual-camera capture via AVCaptureMultiCamSession.
/// Falls back to nil (caller uses VideoCaptureManager) on unsupported devices.
@Observable
final class MultiCamCaptureManager: NSObject, @unchecked Sendable {

    // Two independent circular buffers, one per camera
    let primaryBuffer = CircularFrameBuffer(capacity: 10.0)
    let secondaryBuffer = CircularFrameBuffer(capacity: 10.0)

    // Audio sample accumulation for cross-correlation
    private var primaryAudioSamples: [CMSampleBuffer] = []
    private var secondaryAudioSamples: [CMSampleBuffer] = []
    private let audioLock = NSLock()

    private var multiCamSession: AVCaptureMultiCamSession?

    // Camera pair: wide-angle + ultra-wide (natural for court-side dual-angle)
    private let primaryType: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
    private let secondaryType: AVCaptureDevice.DeviceType = .builtInUltraWideCamera

    // SEPARATE dispatch queues per output (REQUIRED by AVFoundation for multi-cam)
    private let primaryVideoQueue = DispatchQueue(label: "multicam.video.primary", qos: .userInteractive)
    private let secondaryVideoQueue = DispatchQueue(label: "multicam.video.secondary", qos: .userInteractive)
    private let primaryAudioQueue = DispatchQueue(label: "multicam.audio.primary", qos: .userInteractive)
    private let secondaryAudioQueue = DispatchQueue(label: "multicam.audio.secondary", qos: .userInteractive)

    static var isSupported: Bool {
        AVCaptureMultiCamSession.isMultiCamSupported
    }

    var isRecording: Bool = false
    var primaryFPS: Double = 0
    var secondaryFPS: Double = 0
}
```

### Key Design Decisions

**Two CircularFrameBuffers, not one:** Each camera's frames have independent timestamps from different sensor clocks. They must be stored separately and aligned AFTER capture via audio cross-correlation. Interleaving them in one buffer would corrupt temporal ordering.

**Audio capture alongside video:** Each camera input gets a paired AVCaptureAudioDataOutput. The audio tracks enable cross-correlation sync. Both microphones hear the same ambient sound (shuttle hits, footsteps, crowd) but with a slight time offset based on microphone physical position. Cross-correlation finds this offset.

**FPS reduction in multi-cam:** Target 120fps per camera (not 240fps). The frame-skip strategy in HawkEyePipeline already handles variable FPS gracefully (`effectiveSkipInterval` adjusts based on `nominalFPS >= 120`). At 120fps with frameSkipInterval=4, each camera yields 30 detections/sec -- more than sufficient for trajectory fitting.

**Wide + Ultra-Wide pairing:** The wide-angle and ultra-wide cameras on Pro iPhones are the natural pair. They capture overlapping but different perspectives of the court. Telephoto is less useful because its narrow FOV may miss the shuttle landing zone. Using front + back cameras is impractical for tripod-mounted court-side recording.

## New Component: CaptureCoordinator

A lightweight facade that decides which capture path to use and provides a uniform API:

```swift
/// Facade providing uniform capture API regardless of device capability.
@Observable
final class CaptureCoordinator: @unchecked Sendable {

    enum CaptureMode {
        case singleCamera    // Non-Pro devices, or user preference
        case dualCamera      // Pro devices with AVCaptureMultiCamSession
    }

    let mode: CaptureMode
    private(set) var singleCam: VideoCaptureManager?
    private(set) var multiCam: MultiCamCaptureManager?

    init(preferDualCamera: Bool = true) {
        if preferDualCamera && MultiCamCaptureManager.isSupported {
            self.mode = .dualCamera
            self.multiCam = MultiCamCaptureManager()
        } else {
            self.mode = .singleCamera
            self.singleCam = VideoCaptureManager()
        }
    }

    func startCapture() { ... }
    func stopCapture() { ... }

    /// Returns one or two captured video angles with optional audio for sync
    func saveBuffers() async throws -> [CapturedAngle] { ... }
}

/// Output from capture -- one per camera angle
struct CapturedAngle: Sendable {
    let videoURL: URL
    let audioURL: URL?          // nil for single-cam mode
    let cameraIdentifier: String // "wide", "ultrawide"
}
```

**Why a coordinator instead of a protocol:** VideoCaptureManager and MultiCamCaptureManager have fundamentally different output shapes (one video vs two videos + audio). A protocol would force awkward optional arrays. A coordinator with an enum mode is explicit and the calling code branches cleanly on `mode`.

**Why not replace MultiAngleAnalysisView's PhotosPicker flow:** The existing sequential import flow (MultiAngleAnalysisView) should be KEPT as an alternative for users who want to import video from a second phone or external camera. DualCameraAnalysisView is for the simultaneous on-device dual-cam path. The two are complementary, not replacement.

## New Component: AudioSyncService

### Cross-Correlation Algorithm

Audio cross-correlation computes the time offset where two audio signals are most similar. For two microphones recording the same environment:

1. Extract PCM float arrays from both audio tracks
2. Compute cross-correlation using Accelerate's `vDSP_conv`
3. Find the peak in the correlation output -- its index gives the sample offset
4. Convert sample offset to time: `offset_seconds = peak_index / sample_rate`

```swift
import Accelerate

/// Computes temporal offset between two audio tracks using
/// cross-correlation via Accelerate/vDSP.
struct AudioSyncService: Sendable {

    /// Returns the time offset (in seconds) that the secondary audio
    /// leads (+) or lags (-) the primary audio.
    static func computeOffset(
        primarySamples: [Float],
        secondarySamples: [Float],
        sampleRate: Double = 44100.0
    ) -> TimeInterval {
        let primaryCount = primarySamples.count
        let secondaryCount = secondarySamples.count
        guard primaryCount > 0, secondaryCount > 0 else { return 0 }

        let correlationLength = primaryCount + secondaryCount - 1
        var result = [Float](repeating: 0, count: correlationLength)

        // vDSP_conv computes cross-correlation
        primarySamples.withUnsafeBufferPointer { pBuf in
            secondarySamples.withUnsafeBufferPointer { sBuf in
                vDSP_conv(
                    pBuf.baseAddress!, 1,
                    sBuf.baseAddress! + (secondaryCount - 1), -1,
                    &result, 1,
                    vDSP_Length(correlationLength),
                    vDSP_Length(secondaryCount)
                )
            }
        }

        // Find peak index
        var maxVal: Float = 0
        var maxIdx: vDSP_Length = 0
        vDSP_maxvi(result, 1, &maxVal, &maxIdx, vDSP_Length(correlationLength))

        let sampleOffset = Int(maxIdx) - (secondaryCount - 1)
        return Double(sampleOffset) / sampleRate
    }
}
```

### Integration with the Pipeline

The audio offset adjusts temporal alignment BEFORE analysis, at the capture layer:

1. MultiCamCaptureManager captures frames + audio into two buffers
2. AudioSyncService computes offset from the two audio tracks
3. When flushing secondaryBuffer, adjust PTS timestamps by the computed offset
4. Both videos now share a common time base
5. HawkEyePipeline analyzes each video independently (UNCHANGED)
6. ResultFusionService fuses results (UNCHANGED)

**This is the cleanest integration point** because it keeps sync logic isolated to the capture layer and does not pollute the analysis pipeline. HawkEyePipeline has zero awareness of multi-cam or audio sync.

### Accuracy Expectations

At 44.1kHz audio sample rate, cross-correlation achieves sub-millisecond alignment accuracy (one sample = 0.023ms). At 120fps video, one frame = 8.3ms. Audio sync is therefore more than precise enough.

For shuttle tracking, even 2-3 frame alignment error would be acceptable since ResultFusionService fuses landing positions, not trajectory synchronization. But sub-frame accuracy from audio sync enables future features like 3D position triangulation.

## Scoring System Extension: Custom Rules

### Current State Analysis

The scoring system is well-designed for extension:

1. `ScoringRules` is already a parameterized struct with 6 fields: `pointsToWin`, `deuceThreshold`, `capScore`, `gamesToWin`, `maxGames`, `midGameSwitchPoint`
2. `ScoringSystem` enum maps to static `ScoringRules` instances via `rules(for:)`
3. `MatchEngine.apply` uses `state.scoringRules` for ALL threshold checks -- zero hardcoded numbers
4. `BWFRules.swift` computes game/match state purely from `scoringRules`

The only gap: `ScoringSystem` is a closed enum with `String` raw value. Adding `.custom` requires changing it from `RawRepresentable` to a custom Codable implementation.

### Recommended Extension

```swift
// In ScoringEngine/Sources/ScoringEngine/Types.swift

/// User-defined scoring parameters for custom formats
public struct CustomScoringConfig: Codable, Sendable, Equatable {
    public let name: String               // "Club Tournament", "Training", etc.
    public let pointsToWin: Int           // 11, 15, 21, etc.
    public let deuceEnabled: Bool         // some casual formats skip deuce
    public let deuceThreshold: Int?       // nil when deuceEnabled == false
    public let capScore: Int?             // nil = no cap (deuce until 2-point lead)
    public let gamesToWin: Int            // 1, 2, or 3
    public let maxGames: Int              // 1, 3, or 5
    public let midGameSwitchPoint: Int?   // nil = no mid-game switch

    public init(
        name: String, pointsToWin: Int, deuceEnabled: Bool = true,
        deuceThreshold: Int? = nil, capScore: Int? = nil,
        gamesToWin: Int = 2, maxGames: Int = 3, midGameSwitchPoint: Int? = nil
    ) { ... }
}

/// Scoring format: standard BWF 21-point, BWF 3x15, or user-defined custom.
public enum ScoringSystem: Codable, Sendable, Equatable {
    case standard21
    case threeByFifteen
    case custom(CustomScoringConfig)
}

// Drop the String rawValue -- use custom Codable instead
extension ScoringSystem {
    private enum CodingKeys: String, CodingKey { case type, config }

    public init(from decoder: Decoder) throws {
        // Backward compat: try decoding as plain string first (v1.0-v1.2 format)
        if let container = try? decoder.singleValueContainer(),
           let raw = try? container.decode(String.self) {
            switch raw {
            case "standard21": self = .standard21
            case "threeByFifteen": self = .threeByFifteen
            default: self = .standard21  // unknown string -> safe default
            }
            return
        }
        // New keyed format for .custom
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "standard21": self = .standard21
        case "threeByFifteen": self = .threeByFifteen
        case "custom":
            let config = try container.decode(CustomScoringConfig.self, forKey: .config)
            self = .custom(config)
        default: self = .standard21
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .standard21:
            var container = encoder.singleValueContainer()
            try container.encode("standard21")
        case .threeByFifteen:
            var container = encoder.singleValueContainer()
            try container.encode("threeByFifteen")
        case .custom(let config):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("custom", forKey: .type)
            try container.encode(config, forKey: .config)
        }
    }
}

extension ScoringRules {
    public static func rules(for system: ScoringSystem) -> ScoringRules {
        switch system {
        case .standard21: return .standard21
        case .threeByFifteen: return .threeByFifteen
        case .custom(let config):
            return ScoringRules(
                pointsToWin: config.pointsToWin,
                deuceThreshold: config.deuceEnabled
                    ? (config.deuceThreshold ?? config.pointsToWin - 1)
                    : config.pointsToWin + 999,   // effectively disabled
                capScore: config.capScore ?? config.pointsToWin + 999,
                gamesToWin: config.gamesToWin,
                maxGames: config.maxGames,
                midGameSwitchPoint: config.midGameSwitchPoint ?? -1
            )
        }
    }
}
```

**Why `.custom(CustomScoringConfig)` instead of just exposing ScoringRules init:** The ScoringSystem enum is stored in MatchState and serialized via CodableMatchState. If we let users construct arbitrary ScoringRules directly, we lose the ability to serialize what system a match used. The `.custom(CustomScoringConfig)` case preserves this -- including the user-given name ("Club Tournament") for display.

### Backward Compatibility Strategy

The Codable implementation above handles three JSON shapes:
- **v1.0-v1.1:** `scoringSystem` field missing entirely -- CodableMatchState's `decodeIfPresent` defaults to `.standard21` (already implemented)
- **v1.2:** `"scoringSystem": "standard21"` or `"threeByFifteen"` as plain string -- decoded via `singleValueContainer`
- **v1.3:** `"scoringSystem": {"type": "custom", "config": {...}}` as keyed object -- decoded via `container(keyedBy:)`

All three decode correctly without migration. Old app versions encountering a `.custom` JSON will fail to decode (they expect a raw string), but old app versions cannot see v1.3 matches anyway because CloudKit schema is additive.

### Impact on CodableMatchState

Minimal. `CodableMatchState` already has `var scoringSystem: ScoringSystem?`. The optional handles backward compat. The only change is that `ScoringSystem` is no longer `RawRepresentable: String`, so its Codable is now custom. The `CodableMatchState` file itself needs zero modifications -- it delegates to `ScoringSystem`'s own Codable conformance.

### SwiftData Model for Saved Custom Formats

```swift
// In BadmintonEye/Models/CustomScoringFormat.swift

@Model
final class CustomScoringFormat {
    var id: UUID = UUID()
    var name: String = ""
    var pointsToWin: Int = 21
    var deuceEnabled: Bool = true
    var deuceThreshold: Int = 20
    var capScore: Int = 30
    var gamesToWin: Int = 2
    var maxGames: Int = 3
    var midGameSwitchPoint: Int = 11
    var isDefault: Bool = false   // user can mark one as default
    var createdAt: Date = Date()

    /// Convert to ScoringEngine's CustomScoringConfig
    func toConfig() -> CustomScoringConfig {
        CustomScoringConfig(
            name: name,
            pointsToWin: pointsToWin,
            deuceEnabled: deuceEnabled,
            deuceThreshold: deuceEnabled ? deuceThreshold : nil,
            capScore: deuceEnabled ? capScore : nil,
            gamesToWin: gamesToWin,
            maxGames: maxGames,
            midGameSwitchPoint: midGameSwitchPoint > 0 ? midGameSwitchPoint : nil
        )
    }
}
```

### Validation Rules for Custom Formats

The ScoringFormatBuilderView must enforce:
- `pointsToWin` in range 1...99
- If `deuceEnabled`: `deuceThreshold >= pointsToWin - 1` (deuce must be reachable)
- If `deuceEnabled`: `capScore > deuceThreshold` (cap must exceed deuce)
- `gamesToWin <= maxGames` and `gamesToWin > maxGames / 2` (majority required to win)
- `maxGames` is odd (1, 3, 5) -- even values create ambiguous draw states
- If `midGameSwitchPoint` set: must be `< pointsToWin`

## Data Flow

### Dual-Camera Capture Flow

```
User taps "Record Challenge"
  |
  v
CaptureCoordinator.startCapture()
  |
  +--> [dualCamera mode]
  |      MultiCamCaptureManager.startRecording()
  |        --> AVCaptureMultiCamSession starts
  |        --> primaryBuffer.append(frame)    via primaryVideoQueue
  |        --> secondaryBuffer.append(frame)  via secondaryVideoQueue
  |        --> primaryAudioSamples.append()   via primaryAudioQueue
  |        --> secondaryAudioSamples.append() via secondaryAudioQueue
  |
  +--> [singleCamera mode]
         VideoCaptureManager.startRecording()  (unchanged)

User taps "Challenge!" (or auto-trigger at 10s)
  |
  v
CaptureCoordinator.stopCapture()
CaptureCoordinator.saveBuffers()
  |
  +--> [dualCamera]
  |      1. Extract PCM from accumulated audio samples
  |      2. AudioSyncService.computeOffset(primary, secondary) -> TimeInterval
  |      3. primaryBuffer.flush(to: url1) -> primary.mp4
  |      4. secondaryBuffer.flush(to: url2, timeOffset: offset) -> secondary.mp4
  |      5. Return [CapturedAngle(primary), CapturedAngle(secondary)]
  |
  +--> [singleCamera]
         1. singleCam.saveBufferToDisk() -> url
         2. Return [CapturedAngle(url)]

For each CapturedAngle:
  HawkEyePipeline.analyze(videoURL: angle.videoURL, calibration: calibrationForCamera)
  |
  v
ResultFusionService.fuse([result1, result2]) -> HawkEyeResult
```

### Custom Scoring Flow

```
MatchSetupView
  |
  Section("Scoring")
  +--> Picker: "Standard (21 pts)" | "BWF 3x15" | [saved custom formats...]
  |                                                   |
  |                                       "Create New Format" button
  |                                                   |
  |                                       ScoringFormatBuilderView (sheet)
  |                                         --> validates inputs
  |                                         --> saves CustomScoringFormat to SwiftData
  |                                         --> returns .custom(config)
  |
  +--> MatchState.newSinglesMatch(scoringSystem: selectedSystem)
         --> state.scoringRules returns ScoringRules (via rules(for:))
         --> MatchEngine.apply uses scoringRules -- ZERO changes to engine logic
```

## Refactoring Required

### Must Change

| File | Change | Risk |
|------|--------|------|
| `ScoringEngine/Types.swift` | ScoringSystem drops String rawValue, gains `.custom(CustomScoringConfig)` case, custom Codable | MEDIUM -- every `switch` on ScoringSystem needs a `.custom` case |
| `ScoringEngine/MatchState.swift` | `scoringRules` computed property now handles `.custom` via `ScoringRules.rules(for:)` -- this already works, no change needed | LOW |
| `MatchSetupView.swift` | Add custom format options to scoring Picker, navigation to builder | LOW -- additive UI |
| `MultiAngleAnalysisView.swift` | Keep as-is for sequential import path; add DualCameraAnalysisView as a sibling, not a replacement | LOW |

### Must Add (New Files)

| File | Component | Location |
|------|-----------|----------|
| `MultiCamCaptureManager.swift` | AVCaptureMultiCamSession dual-camera capture | `BadmintonEye/Services/` |
| `CaptureCoordinator.swift` | Facade over single/multi capture | `BadmintonEye/Services/` |
| `AudioSyncService.swift` | Cross-correlation via Accelerate/vDSP | `BadmintonEye/Services/` |
| `CustomScoringFormat.swift` | SwiftData model for saved user formats | `BadmintonEye/Models/` |
| `CustomScoringConfig.swift` | Plain Codable struct (or add to Types.swift) | `ScoringEngine/Sources/` |
| `ScoringFormatBuilderView.swift` | Form UI for creating custom scoring rules | `BadmintonEye/Views/` |
| `DualCameraAnalysisView.swift` | Simultaneous dual-camera preview + analysis | `BadmintonEye/Views/` |
| `DualCameraPreviewView.swift` | Side-by-side camera preview (UIViewRepresentable) | `BadmintonEye/Views/` |

### Should NOT Change

| File | Reason |
|------|--------|
| `VideoCaptureManager.swift` | Preserved as single-camera fallback; no modification needed |
| `HawkEyePipeline.swift` | Analyzes one video URL at a time; no awareness of multi-cam needed |
| `ResultFusionService.swift` | Already handles N results; works unchanged with 2 simultaneous results |
| `CircularFrameBuffer.swift` | Reused as-is; MultiCamCaptureManager instantiates two of them |
| `ShuttleDetecting.swift` | Protocol unchanged; detector implementations unchanged |
| `CoreMLShuttleDetector.swift` | Unchanged; works on any video frame |
| `MatchEngine.swift` | Already fully parameterized via `state.scoringRules` |
| `BWFRules.swift` | Already fully parameterized via `state.scoringRules` |
| `CodableMatchState.swift` | `ScoringSystem?` optional already handles backward compat; custom Codable is on the ScoringSystem type itself |

### CalibrationProfile: Minor Extension

Each camera in dual-cam mode has different intrinsics (field of view, distortion). The existing CalibrationProfile stores corners for one camera view. Add:

```swift
// Addition to CalibrationProfile
var cameraIdentifier: String?  // "wide", "ultrawide" -- nil for legacy single-cam profiles
```

This is a new optional field on an existing `@Model`, which SwiftData handles as a lightweight migration (no explicit migration plan needed -- new field defaults to nil).

## Patterns to Follow

### Pattern 1: Capability-Gated Features

AVCaptureMultiCamSession is not available on all devices. The feature must be invisible (not grayed out) on unsupported devices.

```swift
// In ChallengeVideoView or similar
if MultiCamCaptureManager.isSupported {
    Toggle("Dual Camera", isOn: $useDualCamera)
}
// On unsupported devices: toggle never appears, single-cam is the only path
```

### Pattern 2: Per-Camera CalibrationProfile

When calibrating in dual-cam mode, the user calibrates each camera angle separately. CourtCalibrationView runs once per camera. Query by camera identifier at analysis time:

```swift
let calibrations = calibrationProfiles.filter { $0.venueName == venue }
let wideCal = calibrations.first { $0.cameraIdentifier == "wide" || $0.cameraIdentifier == nil }
let ultraWideCal = calibrations.first { $0.cameraIdentifier == "ultrawide" }
```

### Pattern 3: Struct-First Scoring Extension

The ScoringEngine SPM package has zero external dependencies. Custom scoring MUST stay within this boundary:
- `CustomScoringConfig` is a plain Codable struct in the SPM package
- No SwiftData, no UIKit, no SwiftUI imports in ScoringEngine
- The SwiftData model (`CustomScoringFormat`) lives in the app target and converts to/from `CustomScoringConfig` via a `toConfig()` method

### Pattern 4: Sync Logic at Capture Layer, Not Analysis Layer

Audio cross-correlation and PTS adjustment happen in CaptureCoordinator/MultiCamCaptureManager. By the time videos reach HawkEyePipeline, they are temporally aligned. This keeps the analysis pipeline simple and testable with any video file, regardless of source.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Making VideoCaptureManager Support Both Session Types

**What:** Adding if/else branches inside VideoCaptureManager to handle either AVCaptureSession or AVCaptureMultiCamSession.
**Why bad:** AVCaptureMultiCamSession has fundamentally different setup (multiple inputs, multiple outputs, separate queues per output). Cramming both paths into one class creates a 400+ line file with interleaved logic, violating the <500 line constraint and making both paths fragile.
**Instead:** Separate classes behind CaptureCoordinator facade.

### Anti-Pattern 2: Synchronizing Frames by Video Timestamp Alone

**What:** Attempting to align two camera feeds by matching CMSampleBuffer presentation timestamps.
**Why bad:** Each camera sensor has its own clock domain. Timestamps from two different AVCaptureDeviceInputs are NOT on a shared time base in multi-cam mode. Offsets can be tens of milliseconds -- significant at 120fps (8.3ms per frame).
**Instead:** Use audio cross-correlation. Both microphones record the same ambient sound, providing a ground-truth alignment signal independent of video clock domains.

### Anti-Pattern 3: Running Both Cameras at 240fps

**What:** Configuring both cameras in multi-cam mode at maximum frame rate.
**Why bad:** The ISP pipeline on even A17 Pro chips cannot sustain 240fps x 2 cameras. You will get thermal throttling within 30-60 seconds, dropped frames, and potential session interruption via `AVCaptureSession.wasInterruptedNotification`.
**Instead:** Cap multi-cam at 120fps per camera. HawkEyePipeline's frame-skip strategy already handles variable FPS (`effectiveSkipInterval` adjusts based on `nominalFPS >= 120`).

### Anti-Pattern 4: Storing Custom Rules as Freeform JSON

**What:** Storing custom scoring rules as a raw JSON string in MatchState instead of a typed struct.
**Why bad:** Loses compile-time safety, makes validation ad-hoc, breaks when fields are added.
**Instead:** `CustomScoringConfig` as a Codable struct with associated value in the ScoringSystem enum.

### Anti-Pattern 5: Breaking ScoringSystem's Codable Contract

**What:** Changing ScoringSystem from String rawValue to keyed Codable without backward compat.
**Why bad:** All v1.0-v1.2 persisted matches encode scoringSystem as `"standard21"` or `"threeByFifteen"` (plain strings). A keyed-only decoder crashes on existing data.
**Instead:** The custom `init(from decoder:)` tries `singleValueContainer` first (old format), falls back to `container(keyedBy:)` (new format).

## Scalability Considerations

| Concern | v1.2 (current) | v1.3 Dual-Cam | Future |
|---------|----------------|---------------|--------|
| Memory per challenge | ~300MB (10s @ 240fps, 720p, 1 buffer) | ~400MB (10s @ 120fps x 2, 720p, 2 buffers) | Disk-backed ring buffer for 3+ cameras |
| Analysis time | ~3-5s per angle | ~6-10s (two sequential analyses) | Parallel pipeline instances on different cores |
| Storage per challenge | ~15MB HEVC | ~30MB (two videos) | Temp storage; cleaned up after analysis |
| CalibrationProfiles | 1 per venue | 2 per venue (per camera) | N per venue; venue-camera relationship model |
| Scoring formats | 2 built-in | 2 built-in + N user-created | SwiftData query, no scaling concern |

### Thermal Management

Multi-cam 120fps capture for 10 seconds is within thermal budget on A12+ devices. Risk is if users leave capture running longer. Mitigations:
- Hard cap at 10 seconds (`maxDuration` -- already exists, preserve it)
- Monitor `AVCaptureSession.wasInterruptedNotification` and fall back to single-cam if interrupted
- Show thermal warning if `ProcessInfo.processInfo.thermalState >= .serious`

### CircularFrameBuffer Modification for Audio Sync

The existing `flush(to:codec:width:height:fps:)` method writes frames with their original PTS. For the secondary buffer in dual-cam mode, a `timeOffset` parameter is needed:

```swift
// Addition to CircularFrameBuffer
func flush(
    to outputURL: URL,
    codec: AVVideoCodecType,
    width: Int, height: Int, fps: Double,
    timeOffset: CMTime = .zero  // NEW: shift all PTS by this amount
) async throws -> URL
```

This is a backward-compatible additive change (default `.zero` preserves existing behavior). The offset is applied when appending pixel buffers to the writer adaptor.

## Component Dependency Graph

```
CustomScoringConfig (new, in ScoringEngine SPM)
         |
    ScoringSystem (modified: gains .custom case)
         |
    +----+----+
    |         |
MatchState  ScoringRules.rules(for:) (modified)
(unchanged   |
 except      BWFRules.swift (unchanged -- already parameterized)
 Codable)    |
    |        MatchEngine.apply (unchanged)
    |
CodableMatchState (unchanged -- delegates to ScoringSystem Codable)
    |
CustomScoringFormat (new, SwiftData @Model in app target)
    |
ScoringFormatBuilderView (new)
    |
MatchSetupView (modified: adds custom format picker)


CaptureCoordinator (new)
    |
    +---> VideoCaptureManager (unchanged, single-cam)
    |
    +---> MultiCamCaptureManager (new)
              |
              +---> CircularFrameBuffer x2 (reused)
              |
              +---> AudioSyncService (new)

DualCameraAnalysisView (new)
    |
    +---> CaptureCoordinator
    +---> HawkEyePipeline (unchanged, called per angle)
    +---> ResultFusionService (unchanged)

MultiAngleAnalysisView (preserved as sequential import alternative)
CalibrationProfile (minor: add cameraIdentifier optional field)
```

## Build Order Recommendation

### Phase 1: Custom Scoring (lowest risk, highest independence)

Touches only the ScoringEngine SPM package + UI. Zero interaction with camera/ML pipeline. Can be built and shipped independently.

1. Add `CustomScoringConfig` struct to `Types.swift`
2. Change `ScoringSystem` enum: drop String rawValue, add `.custom` case, custom Codable with backward compat
3. Update `ScoringRules.rules(for:)` to handle `.custom`
4. Add `CustomScoringFormat` SwiftData model
5. Build `ScoringFormatBuilderView` with validation
6. Update `MatchSetupView` scoring picker
7. Exhaustive unit tests (clone existing test suites with custom thresholds)

### Phase 2: Dual-Camera Capture (highest complexity)

New capture infrastructure. Requires device testing (cannot validate multi-cam in simulator).

1. Build `MultiCamCaptureManager` with AVCaptureMultiCamSession
2. Build `CaptureCoordinator` facade
3. Add `timeOffset` parameter to `CircularFrameBuffer.flush()`
4. Add `cameraIdentifier` to `CalibrationProfile`
5. Build `DualCameraPreviewView` (UIViewRepresentable for side-by-side preview)
6. Build `DualCameraAnalysisView`
7. Integration test with real dual-cam device

### Phase 3: Audio Cross-Correlation Sync (depends on Phase 2)

Requires MultiCamCaptureManager's audio outputs to exist.

1. Build `AudioSyncService` with vDSP cross-correlation
2. Wire into `CaptureCoordinator.saveBuffers()` -- compute offset, apply to secondary flush
3. Unit test with synthetic audio signals (known offset, verify recovery)
4. Integration test with real dual-cam recordings

## Sources

- Direct codebase analysis: all 55 Swift source files, ScoringEngine SPM package, test suites
- Apple AVFoundation AVCaptureMultiCamSession documentation (training data, MEDIUM confidence -- API introduced iOS 13 / WWDC 2019 session 249, stable since)
- Apple Accelerate/vDSP documentation for cross-correlation (training data, HIGH confidence -- stable API since iOS 4, `vDSP_conv` well-established)
- ScoringEngine internal analysis (HIGH confidence -- direct code reading, all parameterization verified)

**Note:** WebSearch was unavailable during this research. AVCaptureMultiCamSession specifics (especially `supportedMultiCamDeviceSets` and per-device FPS limits) should be verified against current Apple documentation during implementation. The audio cross-correlation approach via vDSP is well-established and unlikely to have changed.
