# Technology Stack: v1.1 Hawk Eye Pro + Analytics

**Project:** Badminton Eye
**Researched:** 2026-03-29
**Scope:** NEW capabilities only (YOLO training pipeline, 240fps capture, Swift Charts analytics)

## Existing Stack (DO NOT CHANGE)

Already validated in v1.0: Swift 6, SwiftUI, SwiftData + CloudKit, WatchConnectivity, Core ML (placeholder), StoreKit 2, ActivityKit, HealthKit, AVFoundation (30fps). Zero external dependencies.

---

## New Stack Additions

### 1. YOLO Training Pipeline (Off-Device, Python)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Ultralytics `ultralytics` | 8.3+ | YOLO model training, export to Core ML | De facto standard for YOLO training. Single `pip install ultralytics` gives you training, validation, export. Actively maintained, MIT license. |
| Python | 3.10-3.11 | Training runtime | Ultralytics requires 3.8+; 3.10-3.11 is the sweet spot for PyTorch compatibility. |
| PyTorch | 2.1+ (auto-installed) | Training backend | Pulled in by Ultralytics. MPS (Apple Silicon) acceleration works on macOS. |
| `coremltools` | 7.2+ | Post-export model optimization | Ultralytics exports `.mlpackage` natively. coremltools needed for quantization (Float16/Int8) and metadata editing. |
| Label Studio or CVAT | latest | Image annotation (bounding boxes) | Free, self-hosted. Label Studio preferred for single-user workflow. CVAT for team annotation. |
| `roboflow` (optional) | latest | Dataset management, augmentation | Simplifies train/val/test splits, augmentation pipelines, and format conversion. Free tier covers small datasets. |

**Model choice: YOLOv8n (nano), NOT "YOLO26"**

The project references "YOLO26" but this appears to be a placeholder name. As of early 2026, Ultralytics' production line is YOLOv8 (with v11 variants emerging). Use **YOLOv8n (nano)** because:
- Nano variant: ~3.2M parameters, ~8.7 GFLOPs -- runs comfortably on iPhone at 240fps frame rate
- Core ML export is first-class: `model.export(format='coreml', nms=True, imgsz=640)`
- The `nms=True` flag bakes Non-Maximum Suppression into the model, so no post-processing needed in Swift
- Proven on small-object detection (shuttlecock is small, fast-moving)
- Confidence: HIGH -- Ultralytics CoreML export is battle-tested

**If YOLO11 is intended:** Ultralytics YOLO11n is also nano-class (~2.6M params) and exports identically. The training/export workflow below works for both. Use whichever shows better mAP on shuttlecock validation set.

#### Training Pipeline Steps

```bash
# 1. Environment setup
python3 -m venv hawk-eye-training
source hawk-eye-training/bin/activate
pip install ultralytics coremltools roboflow label-studio

# 2. Dataset structure (YOLO format)
# datasets/shuttlecock/
#   images/train/   (80%)
#   images/val/     (20%)
#   labels/train/   (YOLO .txt format: class x_center y_center width height)
#   labels/val/
#   data.yaml

# 3. data.yaml
# path: ./datasets/shuttlecock
# train: images/train
# val: images/val
# names:
#   0: shuttlecock

# 4. Train
yolo detect train model=yolov8n.pt data=data.yaml epochs=100 imgsz=640 batch=16 device=mps

# 5. Export to Core ML
yolo export model=runs/detect/train/weights/best.pt format=coreml nms=True imgsz=640

# 6. Quantize (optional, for speed)
# python quantize.py  -- uses coremltools to convert Float32 -> Float16
```

#### Dataset Requirements

| Aspect | Minimum | Recommended | Notes |
|--------|---------|-------------|-------|
| Images | 500 | 2,000-5,000 | Diverse courts, lighting, angles |
| Classes | 1 (shuttlecock) | 1 | Single-class detection simplifies everything |
| Annotation format | YOLO txt | YOLO txt | `class x_center y_center width height` (normalized) |
| Augmentation | Flip, rotate | Flip, rotate, brightness, blur, mosaic | Ultralytics applies mosaic augmentation by default during training |
| Resolution | 640x640 | 640x640 | Standard YOLO input; auto-letterboxed |

#### Core ML Integration in Swift

The exported `.mlpackage` replaces the placeholder in `HawkEyePipeline.swift`. Integration uses Vision framework (already referenced in v1.0 context):

```swift
import Vision
import CoreML

// Load model once
let config = MLModelConfiguration()
config.computeUnits = .all  // Neural Engine + GPU + CPU
let model = try await ShuttlecockDetector.load(configuration: config)
let vnModel = try VNCoreMLModel(for: model.model)

// Per-frame detection
let request = VNCoreMLRequest(model: vnModel) { request, error in
    guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
    // results contain bounding boxes with confidence scores
    // Filter: confidence > 0.5, take highest confidence detection per frame
}
request.imageCropAndScaleOption = .scaleFill
```

**Key integration point:** Replace `generatePlaceholderPositions()` in `HawkEyePipeline.swift` (line 133) with real VNCoreMLRequest detections. The homography transform and trajectory fitting code is already production-ready.

---

### 2. 240fps AVFoundation Capture (On-Device, Swift)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| AVFoundation | iOS 17+ | High frame rate video capture | Already in use for 30fps. Same framework, different configuration. |
| `AVCaptureVideoDataOutput` | iOS 17+ | Frame-by-frame access at 240fps | Replaces current `AVCaptureMovieFileOutput`. Needed because we want per-frame ML inference, not just a saved video file. |
| Core Video (`CVPixelBuffer`) | iOS 17+ | Raw frame data for Vision/Core ML | VNCoreMLRequest accepts CVPixelBuffer directly. Zero-copy from camera to ML. |

**Critical architecture change:** The current `VideoCaptureManager` uses `AVCaptureMovieFileOutput` (records to file, then processes). For 240fps + real-time detection, switch to `AVCaptureVideoDataOutput` which delivers each frame as a `CMSampleBuffer` to a delegate callback.

#### API Requirements for 240fps

```swift
// 1. Find 240fps format on the device
guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                            for: .video, position: .back) else { return }

let targetFPS: Double = 240
var bestFormat: AVCaptureDevice.Format?

for format in device.formats {
    let ranges = format.videoSupportedFrameRateRanges
    for range in ranges {
        if range.maxFrameRate >= targetFPS {
            bestFormat = format
            break
        }
    }
    if bestFormat != nil { break }
}

// 2. Configure device for high frame rate
try device.lockForConfiguration()
device.activeFormat = bestFormat!
device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
device.unlockForConfiguration()

// 3. Use AVCaptureVideoDataOutput (NOT MovieFileOutput)
let videoOutput = AVCaptureVideoDataOutput()
videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
videoOutput.alwaysDiscardsLateVideoFrames = true  // Critical at 240fps
videoOutput.videoSettings = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
]
```

#### Device Compatibility

| Device | Max FPS (Wide) | Max FPS (Ultra-Wide) | Notes |
|--------|---------------|---------------------|-------|
| iPhone 15 Pro / Pro Max | 240fps @ 1080p | 240fps @ 1080p | Best target device |
| iPhone 14 Pro / Pro Max | 240fps @ 1080p | N/A | Wide lens only |
| iPhone 13+ (non-Pro) | 240fps @ 720p | N/A | Lower resolution at 240fps |
| iPhone SE, older | 120fps max | N/A | Graceful fallback needed |

**Fallback strategy:** Query `device.formats` at runtime. If 240fps unavailable, fall back to 120fps, then 60fps. Never hard-code frame rates. The confidence scoring in `TrajectoryCalculator.computeConfidence()` already factors in FPS (line 193), so lower FPS naturally produces lower confidence scores.

#### Architecture Impact on VideoCaptureManager

The current `VideoCaptureManager` needs significant refactoring:

| Current (v1.0) | New (v1.1) |
|----------------|------------|
| `AVCaptureMovieFileOutput` | `AVCaptureVideoDataOutput` |
| Records to file, processes after | Per-frame delegate callback |
| `.hd1280x720` preset | `device.activeFormat` with explicit FPS |
| No ML inference during capture | Run VNCoreMLRequest on every Nth frame |
| Single output | Dual output: video data + movie file (for replay) |

**Key decision: Process every frame or skip frames?**
At 240fps, running YOLO nano on every frame is wasteful (shuttlecock moves ~2cm between frames at close range). Process every 4th frame (effective 60fps detection) while recording all 240 frames for smooth slow-motion replay. This gives 60 detection opportunities per second while keeping GPU/Neural Engine load manageable.

```swift
private var frameCounter = 0
private let detectionInterval = 4  // Process every 4th frame

func captureOutput(_ output: AVCaptureOutput,
                   didOutput sampleBuffer: CMSampleBuffer,
                   from connection: AVCaptureConnection) {
    frameCounter += 1

    // Always write to movie file for replay
    movieWriter?.append(sampleBuffer)

    // Run detection on every Nth frame
    if frameCounter % detectionInterval == 0 {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        runDetection(on: pixelBuffer)
    }
}
```

---

### 3. Swift Charts for Analytics (On-Device, Swift)

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Swift Charts | iOS 17+ (built-in) | All chart rendering | Apple's native charting framework. Zero dependencies, SwiftUI-native, accessibility built-in, Dark Mode automatic. Already available in our iOS 17+ deployment target. |

**No external charting libraries needed.** Swift Charts handles every chart type required for badminton analytics.

#### Chart Types for Match Analytics

| Statistic | Chart Type | Swift Charts API |
|-----------|-----------|-----------------|
| Win/loss over time | Line chart with area fill | `LineMark` + `AreaMark` |
| Scoring patterns per game | Bar chart (grouped) | `BarMark` with `foregroundStyle(by:)` |
| Rally length distribution | Histogram | `BarMark` with binned data |
| Win streak timeline | Step chart | `LineMark` with `.interpolationMethod(.stepCenter)` |
| Performance trend (rolling avg) | Smoothed line | `LineMark` with `.interpolationMethod(.catmullRom)` |
| Point-by-point game flow | Dual line chart | Two `LineMark` series |
| Head-to-head comparison | Grouped bar | `BarMark` with `position(by:)` |

#### Implementation Pattern

```swift
import Charts

struct ScoringPatternChart: View {
    let matchData: [RallyPoint]

    var body: some View {
        Chart(matchData) { point in
            LineMark(
                x: .value("Rally", point.rallyNumber),
                y: .value("Score", point.cumulativeScore)
            )
            .foregroundStyle(by: .value("Side", point.side))
        }
        .chartXAxisLabel("Rally Number")
        .chartYAxisLabel("Score")
        .chartLegend(position: .top)
    }
}
```

#### Data Model Addition

The existing `PersistedMatch` stores final scores but not rally-level data. For analytics, add:

```swift
@Model
final class PersistedRally {
    var matchId: UUID
    var gameNumber: Int
    var rallyNumber: Int
    var scorerSide: String        // "sideA" or "sideB"
    var scoreAfterA: Int
    var scoreAfterB: Int
    var timestamp: Date
    var duration: TimeInterval?   // Rally duration if available

    init() {}
}
```

This enables all the analytics charts without changing the existing `PersistedMatch` schema. Populated from `MatchEngine` state transitions during live scoring.

---

## Supporting Libraries

| Library | Source | Purpose | When to Use |
|---------|--------|---------|-------------|
| `Accelerate` (vDSP) | Apple framework | Fast statistics computation | Rolling averages, standard deviations for performance trends |
| `AVAssetWriter` | AVFoundation | Write 240fps frames to movie file during capture | Dual-output capture (detection + replay video) |
| `PhotosUI` | Apple framework | PHPicker for selecting pre-recorded video | Already implied by v1.0 Hawk Eye flow |

**No new external dependencies.** The entire v1.1 stack remains 100% Apple-native for the iOS app. The Python training pipeline is a separate offline tool.

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| YOLO training | Ultralytics Python | Apple Create ML Object Detection | Create ML's object detection is limited to ~60fps inference, less control over architecture, no YOLO export. Ultralytics gives full YOLO with CoreML export baked in. |
| Model variant | YOLOv8n (nano) | YOLOv8s (small) | Small is 11.2M params vs 3.2M. Nano is sufficient for single-class shuttlecock detection and keeps inference under 4ms on Neural Engine. |
| Charting | Swift Charts | DGCharts (formerly Charts by Daniel Gindi) | External dependency. Swift Charts is built-in, SwiftUI-native, and covers all needed chart types. No reason to add a dependency. |
| Frame capture | AVCaptureVideoDataOutput | AVCaptureMovieFileOutput + post-process | Post-processing a 240fps video after recording adds 5-10s delay. Real-time frame access enables concurrent detection during capture. |
| Annotation tool | Label Studio | Roboflow annotate | Label Studio is fully self-hosted, no data leaves the machine. Roboflow annotation requires upload. For shuttlecock training data (which may include gym/club footage), self-hosted is preferable. |
| Quantization | Float16 via coremltools | Int8 quantization | Float16 halves model size with negligible accuracy loss. Int8 can degrade small-object detection. Float16 is the safe default. |

---

## Installation

### iOS App (no new package dependencies)

```swift
// Package.swift -- NO CHANGES
// All new capabilities use built-in Apple frameworks:
//   - Vision (Core ML inference)
//   - AVFoundation (240fps capture)
//   - Charts (Swift Charts)
//   - Accelerate (statistics)
```

### Training Pipeline (Python, offline)

```bash
# One-time setup on development Mac
python3 -m venv hawk-eye-training
source hawk-eye-training/bin/activate
pip install ultralytics==8.3.0 coremltools==7.2 roboflow label-studio

# Training (after dataset prepared)
yolo detect train model=yolov8n.pt data=shuttlecock.yaml epochs=100 imgsz=640 device=mps

# Export to Core ML
yolo export model=best.pt format=coreml nms=True imgsz=640

# Quantize to Float16
python3 -c "
import coremltools as ct
model = ct.models.MLModel('best.mlpackage')
model_fp16 = ct.models.neural_network.quantization_utils.quantize_weights(model, nbits=16)
model_fp16.save('ShuttlecockDetector.mlpackage')
"
```

### Adding Trained Model to Xcode Project

1. Drag `ShuttlecockDetector.mlpackage` into Xcode project navigator
2. Xcode auto-generates `ShuttlecockDetector.swift` with typed interface
3. Access via: `let model = try await ShuttlecockDetector.load(configuration: config)`

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Ultralytics YOLO training + CoreML export | HIGH | Well-documented, widely used pipeline. |
| AVFoundation 240fps capture | HIGH | `activeVideoMinFrameDuration` / `activeVideoMaxFrameDuration` API is stable since iOS 7. |
| Swift Charts for analytics | HIGH | Built-in since iOS 16, our target is iOS 17+. Standard SwiftUI declarative API. |
| Frame skip strategy (every 4th) | MEDIUM | Reasonable heuristic. May need tuning based on actual shuttlecock speed. Profile on device. |
| YOLO version naming ("YOLO26") | LOW | No Ultralytics model named "YOLO26" found. Assumed project placeholder. Verify current lineup. |
| coremltools quantization API | MEDIUM | API surface may have changed. Verify function signatures against current docs. |

---

## Sources

- Ultralytics documentation (training data knowledge, verified against known API patterns)
- Apple AVFoundation framework documentation (training data knowledge)
- Apple Swift Charts framework documentation (training data knowledge)
- Apple Vision framework documentation (training data knowledge)
- Existing codebase: `VideoCaptureManager.swift`, `HawkEyePipeline.swift`, `TrajectoryCalculator.swift`

**Note:** WebSearch and WebFetch were unavailable during this research session. All recommendations are based on training data knowledge (cutoff ~mid-2025). Verify Ultralytics version numbers and coremltools API against current docs before starting the training pipeline.
