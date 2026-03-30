---
phase: 08-240fps-video-capture
plan: 01
subsystem: video-capture
tags: [avfoundation, 240fps, hevc, circular-buffer, delegate-capture]
dependency_graph:
  requires: []
  provides: [CircularFrameBuffer, delegate-based-capture, high-fps-format-selection]
  affects: [VideoCaptureManager, ChallengeVideoView]
tech_stack:
  added: [AVAssetWriter-HEVC, AVCaptureVideoDataOutput-delegate]
  patterns: [ring-buffer-eviction, format-enumeration, delegate-capture]
key_files:
  created:
    - BadmintonEye/BadmintonEye/Services/CircularFrameBuffer.swift
  modified:
    - BadmintonEye/BadmintonEye/Services/VideoCaptureManager.swift
decisions:
  - Thread-safe NSLock for CircularFrameBuffer (not actor, since called from AVFoundation callback queue)
  - 10 Mbps bitrate for HEVC output to preserve high-FPS motion clarity
  - Height filter 720-750px to avoid selecting 1080p+ formats (bandwidth optimization)
  - Fallback to any format >= 720p if no exact 720p format has high FPS
metrics:
  completed: 2026-03-30
  tasks_completed: 2
  tasks_total: 2
---

# Phase 8 Plan 01: Delegate-Based 240fps Capture with CircularFrameBuffer Summary

Refactored VideoCaptureManager from AVCaptureMovieFileOutput to AVCaptureVideoDataOutput delegate pattern with device format enumeration for highest FPS at 720p, HEVC recording via AVAssetWriter, and a 10-second circular frame buffer.

## Tasks Completed

| Task | Name | Files | Status |
|------|------|-------|--------|
| 1 | Create CircularFrameBuffer | CircularFrameBuffer.swift | Done |
| 2 | Refactor VideoCaptureManager to delegate-based 240fps capture | VideoCaptureManager.swift | Done |

## Task Details

### Task 1: Create CircularFrameBuffer

Created `CircularFrameBuffer.swift` implementing a thread-safe ring buffer of CMSampleBuffers:
- `append(_ sampleBuffer:)` adds frames and evicts stale entries beyond capacity window
- `flush(to:codec:width:height:fps:)` writes all buffered frames to an HEVC .mp4 via AVAssetWriter with pixel buffer adaptor
- `bufferedDuration` computed property returns current buffer time span
- `isEmpty` and `clear()` for state inspection and cleanup
- NSLock-based thread safety for concurrent append from capture queue
- Custom `FlushError` enum with descriptive error messages

### Task 2: Refactor VideoCaptureManager to Delegate-Based 240fps Capture

Rewrote VideoCaptureManager internals while preserving the public interface for ChallengeVideoView compatibility:

**Removed:**
- AVCaptureMovieFileOutput and movieOutput property
- AVCaptureFileOutputRecordingDelegate conformance
- sessionPreset (activeFormat now controls resolution)

**Added:**
- `currentFPS` and `maxAvailableFPS` observable properties for UI display
- `circularBuffer` (CircularFrameBuffer with 10s capacity)
- `videoDataOutput` (AVCaptureVideoDataOutput with delegate)
- `captureQueue` (dedicated DispatchQueue at .userInteractive QoS)
- `configureHighFPSFormat(for:)` enumerates device formats, filters for 720p, selects highest FPS (240 > 120 > 60 > 30)
- `saveBufferToDisk()` async method flushes circular buffer to HEVC .mp4
- AVCaptureVideoDataOutputSampleBufferDelegate conformance feeding frames to circular buffer

**Preserved interface:**
- `capturedVideoURL`, `isRecording`, `recordingDuration`, `session`, `startRecording()`, `stopRecording()`, `cleanup()`

## Requirements Addressed

- **CAP-01**: VideoCaptureManager uses AVCaptureVideoDataOutput with delegate callbacks
- **CAP-02**: Format enumeration selects highest FPS at 720p (240 > 120 > 60 > 30)
- **CAP-03**: HEVC codec at 720p resolution via AVAssetWriter
- **CAP-04**: CircularFrameBuffer retains last 10 seconds, flushes to disk on demand

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing] Added fallback format search**
- **Found during:** Task 2
- **Issue:** Some devices may not have formats with height exactly 720 but do have 1280x720+ formats at high FPS
- **Fix:** Added secondary search pass that accepts any format >= 720p if the strict 720p-only pass finds nothing
- **Files modified:** VideoCaptureManager.swift

## Decisions Made

1. **NSLock over Actor for CircularFrameBuffer** -- Buffer is called from AVFoundation's delegate callback queue (not Swift concurrency). NSLock provides the lowest-overhead thread safety for this hot path.
2. **10 Mbps bitrate for HEVC** -- High enough to preserve motion detail at 240fps without excessive file size for a 10-second clip.
3. **Height filter <= 750px** -- Targets 720p formats specifically, avoiding 1080p+ to reduce capture bandwidth on the image pipeline.
4. **Fallback format search** -- If no strict 720p format has high FPS, a broader search (any format >= 720p) ensures high FPS is still selected on unusual device format lists.
