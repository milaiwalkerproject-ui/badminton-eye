# Research Summary: v1.1 Hawk Eye Pro + Analytics

**Domain:** Sports AI (computer vision + analytics) for native iOS badminton app
**Researched:** 2026-03-29
**Overall confidence:** HIGH (core APIs are stable Apple frameworks; training pipeline is well-established)

## Executive Summary

The v1.1 milestone adds three capabilities to the existing Badminton Eye app: real YOLO-based shuttle detection replacing the placeholder model, 240fps high-frame-rate capture for improved tracking accuracy, and Swift Charts-powered match analytics. The good news is that the iOS app requires zero new external dependencies -- all three features use built-in Apple frameworks (Vision, AVFoundation, Charts). The only new tooling is a Python-based training pipeline (Ultralytics + coremltools) that runs offline on the developer's machine.

The biggest architectural change is in `VideoCaptureManager.swift`, which must switch from `AVCaptureMovieFileOutput` (record-then-process) to `AVCaptureVideoDataOutput` (per-frame delegate callbacks) to enable concurrent ML inference during 240fps capture. This is a significant refactor but follows well-documented AVFoundation patterns. The existing `HawkEyePipeline.swift` homography and trajectory code is production-ready and needs only the placeholder detection swap.

The training pipeline is the highest-risk area: not because of tooling (Ultralytics YOLO export to CoreML is mature), but because of dataset quality. Shuttlecock detection on varied courts, lighting conditions, and camera angles requires 2,000+ annotated images for reliable accuracy. Dataset collection and annotation will likely be the bottleneck, not model training.

Swift Charts for analytics is the lowest-risk addition. The framework is built-in, SwiftUI-native, and the data model extension (rally-level persistence) is straightforward. This feature can be developed in parallel with the AI work.

## Key Findings

**Stack:** Zero new iOS dependencies. Ultralytics Python pipeline for offline YOLO training + CoreML export. Swift Charts (built-in) for analytics.
**Architecture:** VideoCaptureManager refactor from MovieFileOutput to VideoDataOutput is the critical path. Frame-skip strategy (detect every 4th frame at 240fps = 60 detections/sec) balances accuracy with performance.
**Critical pitfall:** Dataset quality is the bottleneck. A perfectly trained model on bad data produces confident wrong answers. Invest in diverse, well-annotated training images before optimizing the model.

## Implications for Roadmap

Based on research, suggested phase structure:

1. **Analytics Foundation** - Lowest risk, can ship independently
   - Addresses: Rally-level data persistence, Swift Charts views, performance trends
   - Avoids: Dependency on AI model or 240fps capture

2. **Training Pipeline Setup** - Long lead time, start early
   - Addresses: Dataset collection, annotation workflow, YOLO training, CoreML export
   - Avoids: Blocked by iOS code changes; runs in parallel

3. **240fps Capture Refactor** - Significant code change, test thoroughly
   - Addresses: VideoCaptureManager rewrite, device format enumeration, fallback logic
   - Avoids: Needs real model for end-to-end testing (pair with phase 2 output)

4. **Real Model Integration** - Ties everything together
   - Addresses: Replace placeholder detection, VNCoreMLRequest pipeline, confidence tuning
   - Avoids: Depends on trained model from phase 2 and 240fps capture from phase 3

**Phase ordering rationale:**
- Analytics has zero dependencies on AI/camera work -- ship it first for user value
- Training pipeline has longest calendar time (dataset collection) -- start immediately in parallel
- 240fps capture is testable with placeholder model but needs real model for validation
- Integration phase naturally comes last as it depends on all prior work

**Research flags for phases:**
- Phase 2 (Training Pipeline): Needs deeper research on shuttlecock dataset availability (public datasets, synthetic data generation)
- Phase 3 (240fps Capture): Standard AVFoundation patterns, unlikely to need further research
- Phase 4 (Integration): May need research on Neural Engine scheduling (concurrent capture + inference)

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All Apple-native on iOS side. Ultralytics is industry standard for YOLO. |
| Features | HIGH | Table stakes for sports AI apps are well-understood. |
| Architecture | HIGH | AVFoundation 240fps and Vision/CoreML patterns are mature. |
| Pitfalls | MEDIUM | Dataset quality risks are real but mitigation strategies are known. Neural Engine contention at 240fps needs on-device profiling. |

## Gaps to Address

- Verify current Ultralytics model naming (YOLO11 vs YOLOv8 vs newer) -- web search was unavailable
- Confirm coremltools quantization API for current version (may have changed)
- Investigate public shuttlecock detection datasets (Badminton-2023, ShuttleNet, etc.)
- Profile Neural Engine throughput: can it sustain 60 YOLO nano inferences/sec during 240fps capture?
- Determine if `AVAssetWriter` can simultaneously record 240fps while `AVCaptureVideoDataOutput` delivers frames for detection
