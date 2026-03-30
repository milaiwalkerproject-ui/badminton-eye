# Phase 9: Real AI Integration - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase replaces the placeholder shuttle detection with a real YOLO Core ML model integration via the ShuttleDetecting protocol from Phase 7. Creates CoreMLShuttleDetector using Vision framework VNCoreMLRequest, implements frame-skip strategy for 240fps, and tunes confidence thresholds. Falls back to PlaceholderShuttleDetector when no .mlmodel file is bundled.

</domain>

<decisions>
## Implementation Decisions

### AI Integration
- Lazy-load model on first challenge — avoid startup cost. Cache in memory after first load.
- Frame-skip: process every 4th frame at 240fps = 60 detections/sec. Configurable constant for tuning.
- Confidence threshold: 0.5 minimum from YOLO — lower detections discarded. Configurable constant.
- Fallback: use PlaceholderShuttleDetector with "Demo Mode" badge when no .mlmodel file bundled — app still works.

### Claude's Discretion
- VNCoreMLRequest configuration details
- Model file naming and bundle location
- Demo Mode badge styling
- Frame-skip constant naming

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ShuttleDetecting.swift` — protocol from Phase 7 with `detect(pixelBuffer:)` async method
- `PlaceholderShuttleDetector.swift` — fallback implementation from Phase 7
- `HawkEyePipeline.swift` — accepts ShuttleDetecting via initializer injection (Phase 7 refactor)
- `VideoCaptureManager.swift` — provides 240fps frames via CircularFrameBuffer (Phase 8)
- `TrajectoryCalculator.swift` — consumes shuttle positions, unchanged

### Established Patterns
- Protocol-based dependency injection (ShuttleDetecting)
- @Observable service singletons
- Vision framework for Core ML inference

### Integration Points
- New CoreMLShuttleDetector conforms to ShuttleDetecting
- HawkEyePipeline initialized with CoreMLShuttleDetector (or Placeholder fallback)
- Frame-skip logic in HawkEyePipeline's analyze method
- Demo Mode badge in TrajectoryReplayView when using placeholder

</code_context>

<specifics>
None — straightforward protocol conformance integration

</specifics>

<deferred>
None

</deferred>
