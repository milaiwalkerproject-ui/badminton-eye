# Technology Stack: v1.3 Live Multi-Cam, Audio Sync & Custom Scoring

**Project:** Badminton Eye
**Researched:** 2026-03-29
**Scope:** NEW capabilities only for v1.3 milestone

## Existing Stack (DO NOT CHANGE)

Already validated: Swift 6, SwiftUI, SwiftData + CloudKit, WatchConnectivity, Core ML, StoreKit 2, ActivityKit, HealthKit, AVFoundation (240fps delegate capture via CircularFrameBuffer, sequential multi-angle via ResultFusionService), Vision framework VNCoreMLRequest, ScoringEngine Swift Package (pure struct state machine with parameterized ScoringRules, 44 tests), UIFeedbackGenerator haptics, HawkEyePipeline with AVAssetReader frame extraction. Zero external dependencies.

---

## Stack Additions

### 1. Simultaneous Dual-Camera Capture (AVCaptureMultiCamSession)

| Technology | Version | Purpose | Why This, Not That |
|------------|---------|---------|-----|
| `AVCaptureMultiCamSession` | iOS 13+ (subclass of AVCaptureSession) | Simultaneous frame capture from two physical cameras | The ONLY Apple API that delivers concurrent frames from multiple cameras. Standard `AVCaptureSession` accepts only one active video input. Verified via iOS SDK header: "A subclass of AVCaptureSession which supports simultaneous capture from multiple inputs of the same media type." |
| `AVCaptureDataOutputSynchronizer` | iOS 11+ | Synchronized frame delivery across both cameras | Aligns presentation timestamps from two `AVCaptureVideoDataOutput` instances into a single delegate callback. The first output in the array is the "primary" and drives timing. Without this, each camera fires its delegate independently with no timestamp alignment guarantee. |
| `AVCaptureDeviceInput.videoMinFrameDurationOverride` | iOS 13+ | Limit per-camera FPS to reduce hardware cost | Critical for multi-cam. Lets you use a high-FPS format (e.g., 240fps-capable) but only pay the hardware cost for the FPS you actually need (e.g., 60fps). Set to `CMTime(value: 1, timescale: 60)` to cap at 60fps per camera. |

**Source:** iOS SDK headers at `/Applications/Xcode.app/.../iPhoneOS.sdk/.../AVFoundation.framework/Headers/AVCaptureSession.h` and `AVCaptureDataOutputSynchronizer.h` (read directly, HIGH confidence).

#### Device Requirements and FPS Limitations

**`AVCaptureMultiCamSession.isMultiCamSupported`** is a class property that gates availability. From the SDK header: "intended to be used with multiple cameras and is only supported on platforms with sufficient hardware bandwidth, system memory, and thermal performance."

**Supported devices (iOS 17+ target):**

| Device | Multi-Cam | Usable Camera Pairs | Notes |
|--------|-----------|---------------------|-------|
| iPhone 11 Pro and later Pro models | YES | Wide + Ultra-Wide, Wide + Telephoto | All three rear cameras available |
| iPhone 11, 12, 13, 14, 15, 16 (non-Pro) | YES | Wide + Ultra-Wide | Two rear cameras |
| iPhone SE (3rd gen) | NO | Single rear camera only | No multi-cam hardware |
| iPad Pro (M1+) | YES | Wide + Ultra-Wide | Two rear cameras |
| iPad Air, iPad mini | NO (typically) | Usually single rear camera | Check `isMultiCamSupported` at runtime |

**FPS constraints in multi-cam mode:**

The `hardwareCost` property (float 0.0-1.0) determines whether a configuration is sustainable. Contributors from the SDK docs:
- Full-sensor (4:3) formats cost more than cropped (16:9) formats
- Higher max frame rate = higher cost
- Non-binned formats cost substantially more than binned formats

**Practical FPS limits (per camera, dual-cam simultaneous):**

| Resolution | Single-Cam Max FPS | Dual-Cam Realistic FPS | Why |
|------------|-------------------|----------------------|-----|
| 720p | 240fps | 60fps | Hardware bandwidth halved across two sensors |
| 1080p | 120fps | 30-60fps | Higher resolution + dual sensor = tight budget |
| 4K | 60fps | Not sustainable | hardwareCost > 1.0 on most devices |

**Recommendation for Badminton Eye:** Run both cameras at 720p 60fps in multi-cam mode. This gives sufficient temporal resolution for shuttle tracking (shuttle moves ~5-10cm between 60fps frames at match speed) while keeping `hardwareCost` well under 1.0. Use `videoMinFrameDurationOverride` set to `CMTime(value: 1, timescale: 60)` on both inputs.

**CRITICAL: `multiCamSupported` format filter.** From the SDK header: "the device's activeFormat may only be set to one of the formats for which `multiCamSupported` returns YES." Not all formats are multi-cam-eligible. The format enumeration in `VideoCaptureManager.configureHighFPSFormat` must add a `format.isMultiCamSupported` filter when running in multi-cam mode.

**Note (iOS 26 change):** "In applications linked on or after iOS 26, this requirement is not enforced when only a single input device is used." This relaxation only applies to single-device use within an `AVCaptureMultiCamSession`, not dual-camera.

#### hardwareCost and systemPressureCost Monitoring

`AVCaptureMultiCamSession` exposes two critical properties not present on standard `AVCaptureSession`:

- **`hardwareCost`** (Float, 0.0-1.0): Static budget. If > 1.0, the session CANNOT start and fires `AVCaptureSessionRuntimeErrorNotification`. Reduce by: picking binned/cropped formats, lowering max FPS via `videoMinFrameDurationOverride`.

- **`systemPressureCost`** (Float, 0.0-1.0): Dynamic thermal/system load. If > 1.0, the session CAN run briefly but will eventually be interrupted with `AVCaptureSessionWasInterruptedNotification`. Monitor and throttle (reduce FPS, disable one camera) when approaching 1.0.

Both must be checked after configuration and monitored during capture.

#### AVCaptureDataOutputSynchronizer Details

From the SDK header (HIGH confidence):

```
AVCaptureDataOutputSynchronizer is initialized with an array of data outputs.
The first output in the array acts as the primary data output and determines
when the synchronized callback is delivered. When data is received for the
primary data output, it is held until all other data outputs have received
data with an equal or later presentation time stamp, or it has been determined
that there is no data for a particular output at the primary data output's pts.
```

The synchronizer delivers `AVCaptureSynchronizedDataCollection` objects. Extract per-camera data via:

```swift
let syncData = synchronizedDataCollection
let wideData = syncData[wideVideoOutput] as? AVCaptureSynchronizedSampleBufferData
let ultraData = syncData[ultraVideoOutput] as? AVCaptureSynchronizedSampleBufferData

// Check for dropped frames
if let wide = wideData, !wide.sampleBufferWasDropped {
    wideBuffer.append(wide.sampleBuffer)
}
if let ultra = ultraData, !ultra.sampleBufferWasDropped {
    ultraBuffer.append(ultra.sampleBuffer)
}
```

**Important:** The synchronizer overrides individual output delegates. Do NOT also set `setSampleBufferDelegate` on outputs managed by the synchronizer.

#### Session Configuration Pattern

Multi-cam requires explicit connection management (not the auto-connection used by standard `AVCaptureSession`):

```swift
let multiSession = AVCaptureMultiCamSession()
// sessionPreset is ALWAYS .inputPriority, cannot be changed

// 1. Add inputs with NO auto-connections
multiSession.addInputWithNoConnections(wideInput)
multiSession.addInputWithNoConnections(ultraInput)

// 2. Add outputs with NO auto-connections
multiSession.addOutputWithNoConnections(wideVideoOutput)
multiSession.addOutputWithNoConnections(ultraVideoOutput)

// 3. Create explicit port-based connections
let widePorts = wideInput.ports(for: .video,
    sourceDeviceType: .builtInWideAngleCamera,
    sourceDevicePosition: .back)
let wideConn = AVCaptureConnection(inputPorts: widePorts, output: wideVideoOutput)
multiSession.addConnection(wideConn)

let ultraPorts = ultraInput.ports(for: .video,
    sourceDeviceType: .builtInUltraWideCamera,
    sourceDevicePosition: .back)
let ultraConn = AVCaptureConnection(inputPorts: ultraPorts, output: ultraVideoOutput)
multiSession.addConnection(ultraConn)

// 4. Also add audio input + output for sync (see section 2)
multiSession.addInputWithNoConnections(audioInput)
multiSession.addOutputWithNoConnections(audioOutput)
let audioPorts = audioInput.ports(for: .audio, sourceDeviceType: nil, sourceDevicePosition: .unspecified)
let audioConn = AVCaptureConnection(inputPorts: audioPorts, output: audioOutput)
multiSession.addConnection(audioConn)

// 5. Set up synchronizer
let synchronizer = AVCaptureDataOutputSynchronizer(
    dataOutputs: [wideVideoOutput, ultraVideoOutput, audioOutput]
)
synchronizer.setDelegate(self, queue: captureQueue)

// 6. Check hardware cost BEFORE starting
print("Hardware cost: \(multiSession.hardwareCost)")
guard multiSession.hardwareCost <= 1.0 else {
    // Reduce format quality or FPS
    return
}
```

#### Graceful Fallback

When `AVCaptureMultiCamSession.isMultiCamSupported` returns `false`, fall back to the existing single-camera `AVCaptureSession` path (current `VideoCaptureManager`). The v1.2 sequential multi-angle workflow (record angle 1, then angle 2) remains the fallback for non-Pro devices. Gate the "Live Multi-Cam" UI behind a runtime check.

---

### 2. Audio Cross-Correlation for Temporal Alignment

| Technology | Version | Purpose | Why This, Not That |
|------------|---------|---------|-----|
| `AVAssetReader` + `AVAssetReaderTrackOutput` | AVFoundation, iOS 4+ | Extract raw PCM audio samples from video files | Already used in `HawkEyePipeline` for video frame extraction. Same pattern for audio track extraction. |
| `AVAudioPCMBuffer` / `AVAudioFormat` | AVFAudio, iOS 15+ | Structured PCM buffer for signal processing | Provides typed access to float channel data. Required format bridge between AVAssetReader output and vDSP. |
| `vDSP_conv` (Accelerate/vDSP) | iOS 4+ | Cross-correlation computation | SIMD-accelerated convolution/correlation on CPU. From the SDK header: "Commonly, this is called correlation if IF is positive and convolution if IF is negative." Pass positive stride for filter parameter to get correlation. No GPU overhead, no framework setup, runs in microseconds for audio-length signals. |
| `vDSP.correlate` (Swift overlay) | iOS 15+ (Swift Accelerate) | Swift-native cross-correlation | Modern Swift wrapper around `vDSP_conv` with positive stride. Cleaner API than C-bridged function. Use this if available. |

**Source:** iOS SDK vecLib/vDSP.h header lines 2282-2333 (read directly, HIGH confidence).

#### How Audio Cross-Correlation Works for Video Alignment

**Problem:** Two video clips from different cameras recorded the same event (shuttle hit, court sounds) but started recording at different times. We need to find the temporal offset between them.

**Solution:** Extract audio from both clips, compute cross-correlation to find the lag that maximizes similarity.

**Algorithm:**

1. Extract mono PCM float32 audio from both video files via `AVAssetReader`
2. Downsample to 8kHz (sufficient for correlation; reduces computation by 5.5x vs 44.1kHz)
3. Compute cross-correlation via `vDSP_conv` with positive filter stride
4. Find the sample index of the maximum correlation value
5. Convert sample offset to time offset: `offsetSeconds = peakIndex / sampleRate`
6. Apply offset when aligning frames from the two cameras

**Why vDSP, not FFT-based correlation:**

FFT-based correlation (multiply spectra in frequency domain) is theoretically faster for very long signals (O(n log n) vs O(n*m)). But for our use case:
- Audio clips are 3-10 seconds at 8kHz = 24,000-80,000 samples
- We only need to search a reasonable lag window (say +/- 5 seconds = 80,000 lags)
- `vDSP_conv` is SIMD-optimized on Apple Silicon and completes in <10ms for these sizes
- No FFT setup, windowing, or complex number handling needed
- Single function call, trivially testable

**If performance becomes an issue** (clips longer than 30 seconds), switch to FFT-based approach using `vDSP_fft_zrip` + element-wise multiply + `vDSP_fft_zrip` inverse. But this is premature optimization for 3-10 second challenge clips.

#### Audio Extraction Pattern

```swift
func extractAudioSamples(from videoURL: URL, sampleRate: Double = 8000) async throws -> [Float] {
    let asset = AVURLAsset(url: videoURL)
    guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
        throw AudioSyncError.noAudioTrack
    }

    let reader = try AVAssetReader(asset: asset)
    let outputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true,
        AVLinearPCMIsNonInterleaved: false,
        AVNumberOfChannelsKey: 1,
        AVSampleRateKey: sampleRate
    ]
    let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
    reader.add(output)
    reader.startReading()

    var samples = [Float]()
    while let buffer = output.copyNextSampleBuffer() {
        // Extract float samples from CMSampleBuffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { continue }
        let length = CMBlockBufferGetDataLength(blockBuffer)
        var data = Data(count: length)
        data.withUnsafeMutableBytes { ptr in
            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
        }
        let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        samples.append(contentsOf: floats)
    }
    return samples
}
```

#### Cross-Correlation via vDSP

```swift
import Accelerate

func findTemporalOffset(reference: [Float], target: [Float], sampleRate: Double) -> TimeInterval {
    // Cross-correlation: slide target over reference
    let correlationLength = reference.count + target.count - 1
    var result = [Float](repeating: 0, count: correlationLength)

    // vDSP_conv with positive stride on filter = correlation
    // A = reference (longer signal, padded), F = target (filter), C = output
    vDSP_conv(
        reference, 1,          // Input signal, stride +1
        target, 1,             // Filter, stride +1 (positive = correlation)
        &result, 1,            // Output
        vDSP_Length(correlationLength),  // Output length
        vDSP_Length(target.count)        // Filter length
    )

    // Find peak
    var maxVal: Float = 0
    var maxIdx: vDSP_Length = 0
    vDSP_maxvi(result, 1, &maxVal, &maxIdx, vDSP_Length(correlationLength))

    // Convert to time offset
    let lagSamples = Int(maxIdx) - (target.count - 1)
    return TimeInterval(lagSamples) / sampleRate
}
```

**Confidence calibration:** Compute peak-to-sidelobe ratio. If the correlation peak is less than 2x the mean correlation, the audio signals may not contain a common event (e.g., one camera was muted). In this case, fall back to manual alignment or timestamp-based estimation.

#### Integration with Live Multi-Cam

For **live simultaneous capture** (AVCaptureMultiCamSession), audio cross-correlation is NOT needed because `AVCaptureDataOutputSynchronizer` already provides timestamp-aligned frames from both cameras. The audio sync is needed for the **fallback workflow**: when users record from two separate devices/sessions and import both clips for multi-angle analysis.

For live multi-cam, include an `AVCaptureAudioDataOutput` in the synchronizer's data outputs array. This gives you audio samples that are already timestamp-synchronized with both video streams. The audio track serves as an embedded sync signal if you ever need to re-align the saved video files post-capture.

---

### 3. Custom Scoring Format Builder

| Technology | Version | Purpose | Why This, Not That |
|------------|---------|---------|-----|
| `ScoringRules` struct (existing) | ScoringEngine package | Parameterized scoring thresholds | Already exists with `pointsToWin`, `deuceThreshold`, `capScore`, `gamesToWin`, `maxGames`, `midGameSwitchPoint`. The struct is already designed for arbitrary values -- just needs UI to create custom instances. |
| SwiftUI `Form` + `Stepper` | iOS 17+ | Builder UI for custom rules | Native SwiftUI controls. Steppers for integer values with min/max bounds. No custom controls needed. |
| SwiftData `@Model` | iOS 17+ | Persist custom scoring formats | New `CustomScoringFormat` model stores user-created rule sets with a name. Syncs via CloudKit like other models. |
| `@AppStorage` | iOS 17+ | Remember last-used format selection | Store the selected format ID so the picker defaults to the user's preferred format. |

**No new frameworks needed.** The existing `ScoringRules` struct already parameterizes all scoring thresholds. The work is UI and persistence, not API.

#### Current ScoringRules Struct (from Types.swift)

```swift
public struct ScoringRules: Sendable, Equatable {
    public let pointsToWin: Int        // 21 or 15
    public let deuceThreshold: Int     // 20 or 14
    public let capScore: Int           // 30 or 17
    public let gamesToWin: Int         // 2 or 3
    public let maxGames: Int           // 3 or 5
    public let midGameSwitchPoint: Int // 11 or 8
}
```

This is already fully parameterized. The builder UI creates a `ScoringRules` instance with user-chosen values.

#### Validation Rules for Custom Formats

The builder must enforce these invariants:

| Field | Min | Max | Constraint |
|-------|-----|-----|------------|
| `pointsToWin` | 5 | 50 | Must be > 0 |
| `deuceThreshold` | `pointsToWin - 1` | `pointsToWin - 1` | Always one less than pointsToWin (standard deuce rule) |
| `capScore` | `pointsToWin` | `pointsToWin + 15` | Must be >= pointsToWin. Set equal to pointsToWin to disable deuce (first to X wins). |
| `gamesToWin` | 1 | 5 | Determines "best of" |
| `maxGames` | `gamesToWin` | `gamesToWin * 2 - 1` | Must be odd for a decisive best-of series |
| `midGameSwitchPoint` | 0 | `pointsToWin / 2` | Set to 0 to disable mid-game side switch |

**`deuceThreshold` should auto-calculate** as `pointsToWin - 1`. Exposing it separately in the UI would confuse users. The builder shows: "Points to win", "Score cap (max score)", "Games to win", and "Switch sides at" -- four values, not six.

#### Persistence Model

```swift
@Model
final class CustomScoringFormat {
    var name: String                // "Casual 11-point", "Tournament 25"
    var pointsToWin: Int
    var capScore: Int
    var gamesToWin: Int
    var midGameSwitchPoint: Int
    var createdDate: Date
    var isDefault: Bool             // User's preferred default

    var scoringRules: ScoringRules {
        ScoringRules(
            pointsToWin: pointsToWin,
            deuceThreshold: pointsToWin - 1,
            capScore: capScore,
            gamesToWin: gamesToWin,
            maxGames: gamesToWin * 2 - 1,
            midGameSwitchPoint: midGameSwitchPoint
        )
    }
}
```

#### ScoringSystem Enum Extension

The existing `ScoringSystem` enum (`.standard21`, `.threeByFifteen`) must be extended or replaced to support custom formats. Two options:

**Option A (Recommended): Add `.custom(ScoringRules)` case**

```swift
public enum ScoringSystem: Codable, Sendable, Equatable {
    case standard21
    case threeByFifteen
    case custom(ScoringRules)

    public var rules: ScoringRules {
        switch self {
        case .standard21: return .standard21
        case .threeByFifteen: return .threeByFifteen
        case .custom(let rules): return rules
        }
    }
}
```

This requires making `ScoringRules` conform to `Codable` (add `Codable` to the struct -- all properties are `Int`, so automatic synthesis works). The `ScoringSystem.rules(for:)` static method becomes the `rules` computed property.

**Option B: Bypass enum, use ScoringRules directly everywhere.** Replace `ScoringSystem` parameter in factory methods with `ScoringRules`. Simpler but loses the named presets.

**Recommendation: Option A.** Preserves backward compatibility with existing `.standard21`/`.threeByFifteen` code paths while enabling arbitrary custom rules.

#### MatchSetupView Integration

The current `MatchSetupView` has a `Picker` for `ScoringSystem` with two options. Extend to:

1. Show built-in formats (Standard 21, BWF 3x15) as first items
2. Show user's saved custom formats below a divider
3. Add a "Create Custom Format" button that presents the builder sheet
4. Selected format resolves to a `ScoringRules` instance passed to `MatchState` factory

#### Watch Sync Impact

`CodableMatchState` already serializes `ScoringRules` (since v1.2). Custom rules will serialize identically to built-in rules -- the Watch receives the same struct with different numbers. No Watch changes needed. The Watch display is score-agnostic (shows current score, game number) and adapts automatically.

---

## Supporting Libraries (Already Available)

| Library | Source | Purpose | Notes |
|---------|--------|---------|-------|
| `Accelerate` (vDSP) | Apple framework | Audio cross-correlation | Not currently linked. Add `import Accelerate` where needed. Framework is always available on iOS, no linking step required. |
| `AVFoundation` | Already linked | Multi-cam session, audio extraction | `AVCaptureMultiCamSession`, `AVCaptureDataOutputSynchronizer`, `AVAssetReader` for audio PCM extraction. All already available. |
| `AVFAudio` | Subset of AVFoundation | PCM buffer types | `AVAudioPCMBuffer`, `AVAudioFormat` for structured audio data. Available via `import AVFoundation`. |
| `SwiftUI` | Already linked | Custom scoring builder UI | Form, Stepper, Slider controls. No new imports. |
| `SwiftData` | Already linked | Persist custom scoring formats | New `CustomScoringFormat` model. |

**No new external dependencies.** The v1.3 stack remains 100% Apple-native with zero third-party packages.

---

## Integration Points with Existing Code

### Dual-Camera Capture

| Existing File | Change Needed |
|---------------|---------------|
| `VideoCaptureManager.swift` | Major refactor: add `AVCaptureMultiCamSession` path. New `startDualCameraRecording()` method alongside existing `startRecording()`. Gate behind `AVCaptureMultiCamSession.isMultiCamSupported`. Use `addInputWithNoConnections` / `addOutputWithNoConnections` / explicit `AVCaptureConnection`. |
| `CircularFrameBuffer.swift` | No changes. Instantiate TWO instances (one per camera) in the multi-cam `VideoCaptureManager`. |
| `HawkEyePipeline.swift` | Add `analyze(videoURLs: [URL], calibrations: [CalibrationProfile])` overload. Runs pipeline on each URL, passes results to `ResultFusionService.fuse()`. |
| `ResultFusionService.swift` | No changes needed. Already designed to fuse N results with weighted confidence averaging. |
| `ChallengeVideoView.swift` | Add dual-preview UI showing both camera feeds. Toggle between single-cam and dual-cam modes. |
| `CalibrationProfile.swift` | Need two calibration profiles (one per camera). Add a `cameraPosition` field or create a paired calibration model. |
| `MultiAngleAnalysisView.swift` | Extend to show live dual-cam preview instead of just sequential import. |

### Audio Cross-Correlation

| Existing File | Change Needed |
|---------------|---------------|
| NEW: `AudioTemporalSync.swift` | New service. Extracts PCM audio from two video URLs, computes cross-correlation via vDSP, returns `TimeInterval` offset. |
| `ResultFusionService.swift` | Accept optional temporal offset to time-shift one result's trajectory before fusion. Currently merges `trajectoryPoints` without temporal alignment -- needs offset-aware merge. |
| `HawkEyePipeline.swift` | Multi-angle overload calls `AudioTemporalSync` before running per-video analysis, applies offset to frame timestamps. |

### Custom Scoring Builder

| Existing File | Change Needed |
|---------------|---------------|
| `ScoringEngine/Types.swift` | Add `Codable` to `ScoringRules`. Add `.custom(ScoringRules)` case to `ScoringSystem`. |
| `MatchSetupView.swift` | Replace two-item `Picker` with list showing built-ins + custom formats + "Create New" button. |
| `SwiftDataModels.swift` | Add `CustomScoringFormat` `@Model`. |
| `CodableMatchState.swift` | Already encodes `ScoringRules` via `MatchState`. Adding `Codable` to `ScoringRules` is the only change needed. |
| NEW: `ScoringFormatBuilderView.swift` | Sheet with Steppers for pointsToWin, capScore, gamesToWin, midGameSwitchPoint. Validates constraints. Saves to SwiftData. |
| `SettingsView.swift` | Add "Manage Scoring Formats" navigation link to list/edit/delete custom formats. |

---

## What NOT to Add

| Technology | Why NOT |
|------------|---------|
| **Multipeer Connectivity** | For syncing two iPhones' cameras over local network. Massive complexity (discovery, pairing, clock sync, NAT traversal). Audio cross-correlation achieves the same temporal alignment after the fact, with zero network code. |
| **FFT-based correlation (vDSP_fft_zrip)** | Premature optimization. Direct `vDSP_conv` correlation completes in <10ms for 10-second clips at 8kHz. FFT only needed for clips >30 seconds, which challenge recordings never are. |
| **AVCaptureMovieFileOutput** | For recording multi-cam to disk. Tempting but locks you into Apple's file format choices and prevents real-time frame access. Stay with `AVCaptureVideoDataOutput` + `CircularFrameBuffer` + `AVAssetWriter` for full control. |
| **Third-party audio processing (AudioKit, etc.)** | A single `vDSP_conv` call replaces an entire audio library. Zero benefit to adding a dependency for one function call. |
| **CoreML for audio alignment** | ML-based audio fingerprinting (Shazam-style) is overkill. Cross-correlation is a deterministic, exact solution. No training data, no model, no uncertainty. |
| **ARKit for camera pose estimation** | Could theoretically auto-detect camera angles for calibration. But ARKit conflicts with AVCaptureSession for camera access, requires LiDAR for good results, and the manual 4-corner calibration already works. |
| **NTP/PTP time sync between devices** | For synchronizing two separate phones' clocks before recording. Network time sync adds complexity and still has ms-level jitter. Audio cross-correlation achieves sub-millisecond alignment accuracy after the fact. |
| **Custom SwiftUI components library** | The scoring builder uses standard Form/Stepper/Slider. No need for custom UI framework for 4 numeric inputs. |

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Multi-cam API | `AVCaptureMultiCamSession` | Two separate `AVCaptureSession` instances | Cannot run two standard sessions simultaneously. Apple only supports one active capture session per process. `AVCaptureMultiCamSession` is the designated solution. |
| Frame synchronization | `AVCaptureDataOutputSynchronizer` | Manual timestamp matching in delegate callbacks | Synchronizer handles dropped frames, late data, and timestamp alignment automatically. Manual matching requires building all that logic from scratch. |
| Audio correlation | `vDSP_conv` (Accelerate) | FFT-based spectral correlation | Direct correlation is simpler, fast enough (<10ms for our signal lengths), and requires no windowing/zero-padding. FFT wins only at >100K samples. |
| Audio correlation | `vDSP_conv` | Manual sample-by-sample loop | 100x slower without SIMD. vDSP uses NEON/AMX on Apple Silicon. |
| Custom scoring persistence | SwiftData `@Model` | `@AppStorage` JSON | SwiftData provides CloudKit sync (custom formats sync across devices), query/sort, and consistency with existing data layer. JSON in AppStorage does not sync and is fragile. |
| Custom scoring UI | SwiftUI Form + Stepper | Custom drag-based builder | Steppers with labeled constraints are clearer for numeric rule configuration. Drag interfaces are pretty but imprecise for exact numbers like "21 points to win." |
| ScoringSystem extension | `.custom(ScoringRules)` enum case | Replace enum with ScoringRules everywhere | Enum preserves named presets (Standard 21, BWF 3x15) for quick selection. Pure struct loses semantic meaning of well-known formats. |

---

## Installation

### iOS App (NO new package dependencies)

```swift
// No Package.swift changes
// No new Swift packages
// New framework imports in specific files:
//   import Accelerate  (in AudioTemporalSync.swift only)
//   AVFoundation already linked (AVCaptureMultiCamSession, AVCaptureDataOutputSynchronizer)
```

### ScoringEngine Package

```swift
// ScoringEngine/Package.swift -- NO CHANGES
// Types.swift: Add Codable to ScoringRules, extend ScoringSystem enum
// No new dependencies
```

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| AVCaptureMultiCamSession API surface | HIGH | Read directly from iOS SDK headers. Class hierarchy, properties (hardwareCost, systemPressureCost), and isMultiCamSupported property all verified. |
| AVCaptureDataOutputSynchronizer | HIGH | Full header read. Delegate protocol, synchronized data collection, and per-output data types (AVCaptureSynchronizedSampleBufferData) all documented. |
| Multi-cam device requirements | MEDIUM | A12+ / iPhone 11+ requirement is from training data. The `isMultiCamSupported` runtime check is the authoritative gate. Exact per-device FPS limits need real device profiling. |
| Multi-cam FPS limitations | MEDIUM | SDK documents hardwareCost contributors (format, FPS, binning) but does not specify exact per-device limits. "720p 60fps dual-cam" recommendation needs hardware validation. |
| videoMinFrameDurationOverride | HIGH | Read directly from AVCaptureInput.h SDK header with full documentation. |
| vDSP_conv for cross-correlation | HIGH | Function signature and semantics read from vDSP.h SDK header line 2284. "correlation if IF is positive" documented at line 2331. |
| Audio extraction via AVAssetReader | HIGH | Same pattern as existing video frame extraction in HawkEyePipeline. Well-established API. |
| ScoringRules custom builder | HIGH | Struct already fully parameterized. Codable conformance is trivial (all Int fields). SwiftData persistence is identical to existing models. |
| ScoringSystem enum extension | HIGH | Standard Swift associated-value enum pattern. Codable synthesis for enums with associated values requires Swift 5.5+, which is well within our Swift 6 target. |

---

## Sources

- **iOS SDK Headers (HIGH confidence, read directly):**
  - `AVCaptureSession.h`: AVCaptureMultiCamSession class, hardwareCost, systemPressureCost, isMultiCamSupported (lines 815-870)
  - `AVCaptureDataOutputSynchronizer.h`: Full synchronizer API, delegate protocol, synchronized data types (all 359 lines)
  - `AVCaptureInput.h`: videoMinFrameDurationOverride property (line 274-283)
  - `AVCaptureDevice.h`: Format.multiCamSupported property (line 3535-3542)
  - `vDSP.h` (vecLib): vDSP_conv function signature and correlation/convolution semantics (lines 2282-2333)
  - `AVAudioBuffer.h` (AVFAudio): AVAudioPCMBuffer availability (line 60+)

- **Existing Codebase (verified by reading):**
  - `VideoCaptureManager.swift`: Current single-session capture, format enumeration
  - `CircularFrameBuffer.swift`: Ring buffer design, flush-to-disk via AVAssetWriter
  - `ResultFusionService.swift`: Weighted confidence fusion, already supports N results
  - `HawkEyePipeline.swift`: AVAssetReader frame extraction pattern
  - `Types.swift`: ScoringRules struct, ScoringSystem enum
  - `BWFRules.swift`: Rule computations using parameterized ScoringRules
  - `MatchSetupView.swift`: Current scoring system picker UI
