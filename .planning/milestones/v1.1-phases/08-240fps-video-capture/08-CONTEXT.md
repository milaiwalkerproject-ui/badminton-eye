# Phase 8: 240fps Video Capture - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase refactors VideoCaptureManager from AVCaptureMovieFileOutput to AVCaptureVideoDataOutput with delegate-based frame handling, adds device format enumeration for 240fps/120fps/30fps fallback, implements a circular buffer for 10-second pre-roll capture, and adds slow-motion replay to TrajectoryReplayView.

</domain>

<decisions>
## Implementation Decisions

### Capture Architecture
- Post-recording batch processing: record all frames via AVAssetWriter, process after challenge trigger. Simpler integration with existing HawkEyePipeline.
- Circular buffer: in-memory ring of compressed CMSampleBuffers, 10-second window. Flush to temp file on challenge trigger.
- Resolution: 720p HEVC — sufficient for ML model input (320-416px), 8x less data than 1080p
- Device capability: enumerate AVCaptureDevice.formats, pick highest FPS at 720p. Display current FPS in capture UI.

### Fallback & Replay UX
- Fallback banner in capture view: "Recording at 30fps — For best results, use iPhone 12 or newer."
- Slow-mo: 240fps plays at 30fps = 8x slower. Tap to toggle normal/slow-mo.
- Enhance existing TrajectoryReplayView with slow-mo toggle when 240fps footage available. 30fps shows normal speed.
- Storage cleanup: delete temp circular buffer file after challenge completes. Keep only analyzed segment.

### Claude's Discretion
- AVAssetWriter configuration details
- Circular buffer memory management specifics
- Slow-mo toggle animation

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `VideoCaptureManager.swift` — existing 30fps capture using AVCaptureMovieFileOutput (to be refactored)
- `ChallengeVideoView.swift` — video capture/select UI (needs circular buffer integration)
- `TrajectoryReplayView.swift` — trajectory visualization (needs slow-mo toggle)
- `HawkEyePipeline.swift` — consumes video URL, unchanged in this phase

### Established Patterns
- @Observable service singletons
- AVFoundation with @preconcurrency import for Swift 6

### Integration Points
- VideoCaptureManager refactored in-place (same file, new internals)
- ChallengeVideoView gets circular buffer "save last 10s" instead of record/stop
- TrajectoryReplayView gets slow-mo playback toggle

</code_context>

<specifics>
## Specific Ideas
- FPS badge showing "240fps" / "120fps" / "30fps" in capture UI
- Smooth slow-mo toggle with animation

</specifics>

<deferred>
None

</deferred>
