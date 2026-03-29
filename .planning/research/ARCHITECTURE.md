# Architecture Patterns: v1.1 Hawk Eye Pro + Analytics

**Domain:** Sports AI + analytics for iOS app
**Researched:** 2026-03-29

## Recommended Architecture

### High-Level Component Map

```
[Camera 240fps] --> [Frame Dispatcher] --> [YOLO Detector] --> [Detection Buffer]
       |                                                              |
       v                                                              v
[AVAssetWriter] --> [Replay Video]            [TrajectoryCalculator] --> [HawkEyeResult]
                                                                              |
                                                                              v
[PersistedMatch] <-- [MatchEngine] --> [PersistedRally] --> [Analytics Charts]
```

### Component Boundaries

| Component | Responsibility | Communicates With |
|-----------|---------------|-------------------|
| `VideoCaptureManager` (refactored) | 240fps frame acquisition, format negotiation, device fallback | Frame Dispatcher, AVAssetWriter |
| `FrameDispatcher` (new) | Routes frames: every Nth to detector, all to writer | VideoCaptureManager, ShuttleDetector, AVAssetWriter |
| `ShuttleDetector` (new) | Wraps VNCoreMLRequest, runs YOLO on CVPixelBuffer, returns bounding boxes | FrameDispatcher, HawkEyePipeline |
| `HawkEyePipeline` (modified) | Orchestrates detection -> homography -> trajectory -> result | ShuttleDetector, TrajectoryCalculator |
| `TrajectoryCalculator` (unchanged) | Homography, curve fitting, in/out determination | HawkEyePipeline |
| `MatchAnalyticsStore` (new) | Queries PersistedRally data, computes aggregations | PersistedRally, Analytics views |
| `AnalyticsChartViews` (new) | Swift Charts views for each stat type | MatchAnalyticsStore |

### Data Flow: Challenge Analysis

```
1. User taps "Challenge"
2. VideoCaptureManager configures 240fps (or best available)
3. AVCaptureVideoDataOutput delivers CMSampleBuffer to delegate
4. FrameDispatcher:
   a. Every frame -> AVAssetWriter (records .mov for replay)
   b. Every 4th frame -> ShuttleDetector
5. ShuttleDetector runs VNCoreMLRequest -> [VNRecognizedObjectObservation]
6. Detections accumulated in buffer with frame timestamps
7. User taps "Stop" or 10s max reached
8. HawkEyePipeline receives detection buffer:
   a. Extracts bounding box centers as image-space points
   b. Applies homography (existing code) -> court-space points
   c. Fits trajectory (existing code) -> landing point
   d. Determines in/out (existing code) -> HawkEyeResult
9. UI animates trajectory and landing (existing views)
```

### Data Flow: Analytics

```
1. During live match, MatchEngine fires state transitions
2. LiveMatchViewModel intercepts score changes
3. New PersistedRally record created per rally:
   - matchId, gameNumber, rallyNumber, scorerSide, scores, timestamp
4. On analytics screen, MatchAnalyticsStore queries:
   - Recent matches for trend lines
   - Rally data for per-game charts
   - Head-to-head filtered by player pair
5. Swift Charts views render from computed data
```

## Patterns to Follow

### Pattern 1: Frame Pipeline with Back-Pressure

**What:** Decouple frame production (240fps camera) from frame consumption (60fps detection) using a dispatch queue with `alwaysDiscardsLateVideoFrames = true`.

**When:** Any time camera frame rate exceeds processing rate.

**Example:**
```swift
final class FrameDispatcher: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let detectionQueue = DispatchQueue(label: "detection", qos: .userInitiated)
    private let writerQueue = DispatchQueue(label: "writer", qos: .userInitiated)
    private var frameCount = 0
    private let detectionInterval = 4

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frameCount += 1

        // Always write for replay
        writerQueue.async { [weak self] in
            self?.assetWriter?.append(sampleBuffer)
        }

        // Detect on subset
        guard frameCount % detectionInterval == 0 else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        detectionQueue.async { [weak self] in
            self?.detector.detect(pixelBuffer: pixelBuffer,
                                 timestamp: sampleBuffer.presentationTimeStamp)
        }
    }
}
```

### Pattern 2: Protocol-Based Detector for Testability

**What:** Define shuttle detection behind a protocol so tests can inject mock detections.

**When:** Any ML inference component that needs unit testing.

**Example:**
```swift
protocol ShuttleDetecting: Sendable {
    func detect(pixelBuffer: CVPixelBuffer, timestamp: CMTime) async -> [ShuttleObservation]
}

struct ShuttleObservation {
    let boundingBox: CGRect  // Normalized 0-1
    let confidence: Float
    let timestamp: CMTime
}

// Production implementation
final class CoreMLShuttleDetector: ShuttleDetecting { ... }

// Test mock
final class MockShuttleDetector: ShuttleDetecting {
    var stubbedObservations: [ShuttleObservation] = []
    func detect(pixelBuffer: CVPixelBuffer, timestamp: CMTime) async -> [ShuttleObservation] {
        stubbedObservations
    }
}
```

### Pattern 3: Computed Analytics with Caching

**What:** Compute analytics aggregations lazily and cache results keyed by date range.

**When:** Analytics queries over hundreds of matches and thousands of rallies.

**Example:**
```swift
@Observable
final class MatchAnalyticsStore {
    private var cache: [String: Any] = [:]

    func winRate(last nMatches: Int) -> Double {
        let key = "winRate-\(nMatches)"
        if let cached = cache[key] as? Double { return cached }

        let matches = fetchRecentMatches(limit: nMatches)
        let wins = matches.filter { $0.winnerSide == "sideA" }.count
        let rate = Double(wins) / Double(max(matches.count, 1))
        cache[key] = rate
        return rate
    }

    func invalidateCache() { cache.removeAll() }
}
```

## Anti-Patterns to Avoid

### Anti-Pattern 1: Running Detection on Main Thread

**What:** Calling VNCoreMLRequest synchronously on the main thread.
**Why bad:** 240fps frame delivery + ML inference on main thread = UI freeze, dropped frames, watchdog kill.
**Instead:** All detection on dedicated `DispatchQueue` with `.userInitiated` QoS. Results dispatched to `@MainActor` for UI.

### Anti-Pattern 2: Retaining All 240fps Frames in Memory

**What:** Storing CVPixelBuffers in an array for batch processing after recording.
**Why bad:** 240fps x 10s = 2,400 frames x ~8MB each = ~19GB. OOM crash.
**Instead:** Stream frames through pipeline. Write to disk via AVAssetWriter. Retain only detection result structs.

### Anti-Pattern 3: Hard-Coding Frame Rates

**What:** Setting `activeVideoMinFrameDuration = CMTime(1, 240)` without checking device capabilities.
**Why bad:** Crashes on devices that don't support 240fps for the selected format.
**Instead:** Enumerate `device.formats`, find best match, fall back gracefully.

### Anti-Pattern 4: Single God-Object for Capture + Detection + Pipeline

**What:** Putting camera setup, frame handling, ML inference, and trajectory computation in one class.
**Why bad:** Untestable, violates SRP, impossible to mock for unit tests.
**Instead:** Separate into VideoCaptureManager, FrameDispatcher, ShuttleDetector, HawkEyePipeline.

## Scalability Considerations

| Concern | Current (v1.0) | v1.1 | Future |
|---------|----------------|------|--------|
| Frame processing | None (placeholder) | 60 detections/sec via frame skip | Adaptive skip rate based on thermal state |
| Model size | No model | ~6MB (YOLOv8n Float16) | Could shrink with Int8 if accuracy holds |
| Rally data storage | Not persisted | ~100 bytes/rally, ~2KB/match | 1000 matches = ~2MB. Negligible. |
| Analytics computation | None | In-memory aggregation with caching | SwiftData `#Predicate` queries scale to 10K+ |
| Thermal management | N/A | Monitor `ProcessInfo.thermalState` | Auto-reduce to 120fps if `.serious` or `.critical` |

## Sources

- Existing codebase: `VideoCaptureManager.swift`, `HawkEyePipeline.swift`, `TrajectoryCalculator.swift`
- Apple AVFoundation capture pipeline patterns (training data knowledge)
- Apple Vision framework VNCoreMLRequest patterns (training data knowledge)
