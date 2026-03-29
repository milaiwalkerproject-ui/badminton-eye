# Domain Pitfalls: v1.1 Hawk Eye Pro + Analytics

**Domain:** Sports AI shuttle tracking + 240fps capture + analytics
**Researched:** 2026-03-29

## Critical Pitfalls

Mistakes that cause rewrites, App Store rejections, or user trust collapse.

### Pitfall 1: Training on Insufficient or Biased Dataset

**What goes wrong:** Model trained on 200 images from one court, one lighting condition. Works great in testing. Fails on every other court.
**Why it happens:** Dataset collection is tedious. Temptation to "just ship it" with small dataset.
**Consequences:** Users get wrong in/out calls. Trust in Hawk Eye destroyed. Negative reviews. Feature becomes liability.
**Prevention:**
- Minimum 2,000 annotated images across 5+ different courts, 3+ lighting conditions (indoor fluorescent, outdoor daylight, outdoor evening)
- Include various shuttle types (feather and nylon -- different visual profiles)
- Include frames where shuttlecock is blurred (motion blur at speed) -- this is the real-world condition
- Validate mAP@0.5 > 0.85 on held-out test set before shipping
- Use Ultralytics built-in augmentation (mosaic, mixup, brightness jitter) during training
**Detection:** If mAP on validation set is below 0.80, do not ship. Collect more data.

### Pitfall 2: Memory Exhaustion from 240fps Frame Buffering

**What goes wrong:** Accumulating CVPixelBuffer references in an array causes 15-20GB memory spike in 10 seconds. App killed by OS.
**Why it happens:** Natural instinct to "collect all frames, then process." Works at 30fps (300 frames = 2.4GB, still dangerous). Fatal at 240fps.
**Consequences:** Crash during challenge recording. Data loss. Terrible user experience.
**Prevention:**
- NEVER retain CVPixelBuffer references beyond the delegate callback
- Use AVAssetWriter for disk persistence (streaming write, constant memory)
- Process detections in-flight, store only result structs (boundingBox + confidence + timestamp = ~40 bytes each)
- Set `alwaysDiscardsLateVideoFrames = true` on AVCaptureVideoDataOutput
**Detection:** Memory profiling in Instruments. If memory exceeds 200MB during capture, something is wrong.

### Pitfall 3: Neural Engine Contention Causing Frame Drops

**What goes wrong:** 240fps capture + YOLO inference + AVAssetWriter all competing for Neural Engine / GPU / CPU. Frames get dropped, detection gaps appear in trajectory.
**Why it happens:** Neural Engine has limited throughput. YOLO nano inference is ~4ms per frame, but scheduling overhead and contention can double this.
**Consequences:** Gaps in shuttle trajectory. Trajectory fitting produces inaccurate landing prediction. User sees "low confidence" on shots that should be clear.
**Prevention:**
- Skip frames: detect every 4th frame (60 detections/sec is plenty for shuttle trajectory)
- Monitor `ProcessInfo.ThermalState` -- reduce to every 8th frame if device is hot
- Use `.all` compute units (Neural Engine preferred, GPU fallback, CPU last resort)
- Profile with Instruments Core ML template on target device (not simulator)
- Consider `VNImageRequestHandler` with `.performRequests()` batch mode
**Detection:** If average detection latency exceeds 8ms, increase skip interval.

### Pitfall 4: Shipping Without Device-Specific Format Validation

**What goes wrong:** Code assumes 240fps is available. Crashes on iPhone SE, iPhone 13 mini, or older devices.
**Why it happens:** Developer tests on iPhone 15 Pro. Forgets to check other devices.
**Consequences:** App Store rejection (crash on supported device) or 1-star reviews from users with older phones.
**Prevention:**
- ALWAYS enumerate `device.formats` and find best available FPS
- Implement fallback chain: 240fps -> 120fps -> 60fps -> 30fps
- Show user what FPS they are getting: "Recording at 120fps (your device supports up to 120fps)"
- Adjust confidence scoring based on actual FPS (already partially done in `TrajectoryCalculator.computeConfidence`)
**Detection:** Test on at least 3 device tiers: Pro (240fps), standard (120fps), SE/older (30-60fps).

## Moderate Pitfalls

### Pitfall 5: SwiftData Migration Breaking CloudKit Sync

**What goes wrong:** Adding `PersistedRally` model to SwiftData schema triggers migration. CloudKit containers may not handle the migration cleanly.
**Prevention:**
- Use lightweight migration (additive only -- new model, no changes to existing `PersistedMatch`)
- Test CloudKit sync after schema change on fresh install AND upgrade from v1.0
- Never rename or delete existing SwiftData model properties
- Add `PersistedRally` as a new standalone model, NOT a relationship on `PersistedMatch` (CloudKit has relationship limitations)

### Pitfall 6: Chart Performance with Large Datasets

**What goes wrong:** Swift Charts becomes sluggish when rendering 10,000+ data points (e.g., all rallies from 500+ matches).
**Prevention:**
- Pre-aggregate data before charting (weekly averages, not every rally)
- Limit visible data range with picker (last 7 days, 30 days, 90 days, all time)
- Use `.chartXVisibleDomain()` for scrollable charts with fixed viewport
- Profile with Instruments SwiftUI template

### Pitfall 7: Model File Size Bloating App Bundle

**What goes wrong:** Full YOLO model (Float32) is 25MB+. With multiple variants, app size balloons.
**Prevention:**
- Use Float16 quantization: YOLOv8n goes from ~12MB to ~6MB
- Ship single model variant (nano only)
- Consider On-Demand Resources if model exceeds 10MB (download on first Hawk Eye use)
- Check App Store size limits (200MB over cellular)

### Pitfall 8: AVAssetWriter Setup Race Condition

**What goes wrong:** AVAssetWriter not ready when first frame arrives. First 10-50 frames lost. Slow-motion replay starts with a jump.
**Prevention:**
- Start AVAssetWriter BEFORE starting capture session
- Use `startWriting()` + `startSession(atSourceTime:)` with the first frame's presentation timestamp
- Buffer first frame and use its timestamp for session start

## Minor Pitfalls

### Pitfall 9: Confidence Score Calibration Mismatch

**What goes wrong:** YOLO model outputs confidence 0.0-1.0. Pipeline confidence also 0.0-1.0. Users see "85% confident" but actual accuracy is 60%.
**Prevention:** Calibrate confidence against ground truth. Use separate "system confidence" that factors in: model confidence, number of detections, trajectory fit R-squared, FPS, and margin from line.

### Pitfall 10: Dark Mode Chart Legibility

**What goes wrong:** Chart colors that look great in light mode become invisible in dark mode.
**Prevention:** Use semantic colors (`Color.accentColor`, `Color.secondary`) not hard-coded RGB. Test all charts in both modes.

### Pitfall 11: Thermal Throttling During Extended Recording

**What goes wrong:** 240fps capture at 1080p generates significant heat. After 2-3 challenges in quick succession, device throttles camera FPS.
**Prevention:** Monitor `ProcessInfo.thermalState`. If `.serious`, warn user. If `.critical`, automatically reduce to 120fps. Show current capture quality in UI.

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Training pipeline setup | Insufficient dataset (Pitfall 1) | Set minimum 2,000 images gate before training |
| 240fps capture refactor | Memory exhaustion (Pitfall 2) | Streaming architecture from day one |
| 240fps capture refactor | Device compatibility (Pitfall 4) | Test on 3+ device tiers |
| Model integration | Neural Engine contention (Pitfall 3) | Frame skip + thermal monitoring |
| Analytics data model | CloudKit migration (Pitfall 5) | Additive-only schema change |
| Analytics charts | Chart performance (Pitfall 6) | Pre-aggregate, limit visible range |
| App Store submission | Model file size (Pitfall 7) | Float16 quantization |

## Sources

- Existing codebase analysis (`VideoCaptureManager.swift` uses MovieFileOutput pattern that must change)
- AVFoundation high-frame-rate capture known issues (training data knowledge)
- Core ML deployment best practices (training data knowledge)
- SwiftData + CloudKit migration constraints (training data knowledge)
