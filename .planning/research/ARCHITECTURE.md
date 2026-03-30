# Architecture Patterns: v1.3 Live Multi-Cam, Audio Sync & Custom Scoring

**Domain:** iOS badminton scoring app with AI video analysis
**Researched:** 2026-03-29

## Recommended Architecture

### Component Boundaries

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| `MultiCamCaptureManager` (NEW) | AVCaptureMultiCamSession lifecycle, dual-camera setup, format selection, hardwareCost/systemPressureCost monitoring | CircularFrameBuffer (x2), AVCaptureDataOutputSynchronizer, HawkEyePipeline |
| `AudioTemporalSync` (NEW) | PCM extraction from video files, vDSP cross-correlation, offset computation | HawkEyePipeline (provides offset for multi-angle analysis) |
| `ScoringFormatBuilderView` (NEW) | UI for creating/editing custom ScoringRules | CustomScoringFormat (SwiftData), MatchSetupView |
| `CustomScoringFormat` (NEW) | SwiftData model persisting user-defined formats | ScoringFormatBuilderView, MatchSetupView, CloudKit sync |
| `VideoCaptureManager` (UNCHANGED) | Single-camera capture (fallback) | CircularFrameBuffer, HawkEyePipeline |
| `ResultFusionService` (UNCHANGED) | Merge N HawkEyeResults with confidence weighting | HawkEyePipeline |
| `CircularFrameBuffer` (MINOR CHANGE) | Ring buffer of CMSampleBuffers | VideoCaptureManager, MultiCamCaptureManager |

### Data Flow: Live Dual-Camera Capture

```
                    AVCaptureMultiCamSession
                    /          |           \
        Wide Camera    Ultra-Wide Camera    Microphone
                    \          |           /
            AVCaptureDataOutputSynchronizer
                         |
            Single synchronized delegate callback
                    /         |          \
        Wide Buffer    Ultra Buffer    Audio Samples
                |              |
        flush() -> A.mp4   flush() -> B.mp4
                \              /
              HawkEyePipeline.analyze(videoURLs:)
                    /           \
        HawkEyeResult A    HawkEyeResult B
                    \           /
              ResultFusionService.fuse()
                       |
                Fused HawkEyeResult (higher confidence)
```

### Data Flow: Audio Cross-Correlation (Imported Videos)

```
        video_A.mp4              video_B.mp4
            |                        |
    AVAssetReader (audio)    AVAssetReader (audio)
            |                        |
      PCM Float32 @ 8kHz     PCM Float32 @ 8kHz
            \                       /
        AudioTemporalSync.findOffset()
                    |
            vDSP_conv (positive stride = correlation)
                    |
            Peak index -> TimeInterval offset
                    |
            Apply offset to video_B frame extraction
                    |
        HawkEyePipeline runs on both (offset-adjusted)
                    |
              ResultFusionService.fuse()
```

### Data Flow: Custom Scoring

```
    MatchSetupView
        |
    [Standard 21] [BWF 3x15] [Custom formats from SwiftData]
        |                           |
    ScoringRules.standard21    CustomScoringFormat.scoringRules
        |                           |
        +------ ScoringRules ------+
                    |
        MatchState.newSinglesMatch(scoringRules:)
                    |
        BWFRules uses scoringRules.pointsToWin, etc.
```

## Patterns to Follow

### Pattern 1: Dual-Mode Manager (Single-Cam / Multi-Cam)

**What:** Camera capture must operate in two modes. Single-cam uses existing AVCaptureSession. Multi-cam uses AVCaptureMultiCamSession with explicit connections.

**When:** Any feature with Pro-device-only capabilities alongside universal fallback.

```swift
enum CaptureMode: Sendable {
    case singleCamera
    case dualCamera
}

@Observable
final class MultiCamCaptureManager: NSObject, @unchecked Sendable {
    private(set) var mode: CaptureMode = .singleCamera

    // AVCaptureMultiCamSession IS-A AVCaptureSession
    // Single-cam fallback uses standard AVCaptureSession
    private var session: AVCaptureSession?

    func configure() {
        if AVCaptureMultiCamSession.isMultiCamSupported {
            session = configureMultiCam()
            mode = .dualCamera
        } else {
            session = configureSingleCam()
            mode = .singleCamera
        }
    }
}
```

**Rationale:** AVCaptureMultiCamSession is a subclass of AVCaptureSession, so preview layers and lifecycle code work identically. The mode enum drives UI (single vs dual preview) and buffer management (one vs two CircularFrameBuffers).

### Pattern 2: Standalone Stateless Service (AudioTemporalSync)

**What:** AudioTemporalSync is a pure function: two URLs in, TimeInterval out. No state, no delegates, no lifecycle.

**When:** Signal processing or computational services with deterministic input-to-output mapping.

```swift
struct AudioTemporalSync {
    struct SyncResult: Sendable {
        let offset: TimeInterval
        let confidence: Double  // peak-to-sidelobe ratio
    }

    static func findOffset(reference: URL, target: URL) async throws -> SyncResult
}
```

**Rationale:** Matches the existing ResultFusionService pattern (static fuse() method). Trivially testable with synthetic audio data. No mocking, no setup.

### Pattern 3: Validated Builder with Auto-Derived Fields

**What:** Custom scoring builder exposes 4 user-editable fields. Two fields (deuceThreshold, maxGames) are auto-derived from user inputs to prevent invalid states.

**When:** User-configurable parameters with mathematical constraints between them.

```swift
// User edits:      pointsToWin, capScore, gamesToWin, midGameSwitchPoint
// Auto-derived:    deuceThreshold = pointsToWin - 1
//                  maxGames = gamesToWin * 2 - 1
```

**Rationale:** Exposing all 6 ScoringRules fields would confuse users and enable invalid combinations. Auto-deriving 2 from 4 preserves the full ScoringRules parameterization while keeping the UI simple.

### Pattern 4: Explicit Port Connections for Multi-Cam

**What:** AVCaptureMultiCamSession requires addInputWithNoConnections + addOutputWithNoConnections + explicit AVCaptureConnection creation.

**When:** Always, when using AVCaptureMultiCamSession. The SDK enforces this.

```swift
// WRONG (auto-connection, works for AVCaptureSession, BROKEN for multi-cam):
// session.addInput(wideInput)
// session.addOutput(wideOutput)

// CORRECT (explicit connections):
session.addInputWithNoConnections(wideInput)
session.addOutputWithNoConnections(wideOutput)
let ports = wideInput.ports(for: .video,
    sourceDeviceType: .builtInWideAngleCamera,
    sourceDevicePosition: .back)
let connection = AVCaptureConnection(inputPorts: ports, output: wideOutput)
session.addConnection(connection)
```

**Rationale:** From SDK header: "AVCaptureMultiCamSession's sessionPreset is always AVCaptureSessionPresetInputPriority." Auto-connection would wire both inputs to the same output.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Modifying VideoCaptureManager for Multi-Cam

**What:** Adding multi-cam logic into the existing 219-line VideoCaptureManager.
**Why bad:** VideoCaptureManager is clean, tested, and handles single-cam perfectly. Adding dual-cam branches, synchronizer logic, and hardwareCost monitoring would double its size and mix concerns.
**Instead:** Create a NEW MultiCamCaptureManager class. Both classes share CircularFrameBuffer and HawkEyePipeline but own their own session lifecycle. A CaptureCoordinator facade can route to the appropriate manager.

### Anti-Pattern 2: Running vDSP on the Main Thread

**What:** Calling AudioTemporalSync.findOffset() synchronously because "vDSP is fast."
**Why bad:** vDSP_conv completes in <10ms, but PCM extraction via AVAssetReader takes 100-500ms. Blocking the main thread causes UI jank.
**Instead:** The entire findOffset() is async. PCM extraction and correlation both run on background tasks.

### Anti-Pattern 3: Using AVCaptureDataOutputSynchronizer AND Individual Delegates

**What:** Setting up the synchronizer while also calling setSampleBufferDelegate on individual outputs.
**Why bad:** From the SDK: "AVCaptureDataOutputSynchronizer overrides all the data outputs' delegates and callbacks." Individual delegates silently stop firing.
**Instead:** Use the synchronizer exclusively for all outputs in multi-cam mode.

### Anti-Pattern 4: Assuming Audio Track Exists

**What:** Calling AudioTemporalSync on videos without checking for audio tracks first.
**Why bad:** CircularFrameBuffer.flush() currently writes video-only .mp4 files. Imported videos may also lack audio. No audio = correlation throws.
**Instead:** Always guard with asset.loadTracks(withMediaType: .audio). Add audio capture to the multi-cam session for live recordings.

## Scalability Considerations

| Concern | Current (v1.3) | Future Consideration |
|---------|----------------|---------------------|
| Number of cameras | 2 (wide + ultra-wide) | AVCaptureMultiCamSession supports 3+ on Pro Max. Use arrays, not hard-coded pairs. |
| Custom format count | Dozens per user | SwiftData handles trivially |
| Audio clip length | 3-10 seconds | If >30s, switch to FFT-based correlation |
| Thermal management | Match-length recording | Monitor systemPressureCost; auto-degrade to single-cam |
| Buffer memory | 2 x 10s at 720p60 | Reduce to 5s per buffer in dual mode |

## Sources

- Existing codebase: VideoCaptureManager (219 LOC), CircularFrameBuffer (196 LOC), ResultFusionService (48 LOC), HawkEyePipeline (265 LOC), Types.swift
- iOS SDK headers: AVCaptureSession.h, AVCaptureDataOutputSynchronizer.h, AVCaptureInput.h, AVCaptureDevice.h, vDSP.h (all read directly from Xcode)
