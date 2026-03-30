# Phase 7: Training Pipeline - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase delivers the developer tooling for training a YOLO nano shuttle detection model: Python training script using Ultralytics with CoreML export, annotation guide for shuttlecock labeling, ShuttleDetecting protocol in the iOS codebase for model swappability, and a training README documenting dataset requirements.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure infrastructure phase. Key constraints from research:
- Use Ultralytics YOLO nano (smallest model, ~3.2M params) for Neural Engine compatibility
- Export to CoreML with NMS baked in via `export(format='coreml', nms=True)`
- ShuttleDetecting protocol must abstract detection so placeholder and real model are swappable
- Training data requirements: 2,000+ annotated images, diverse courts/lighting, motion blur cases
- Place training tooling in `scripts/training/` directory per CLAUDE.md file organization rules

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `HawkEyePipeline.swift` — has `generatePlaceholderPositions()` marked with TODO for Core ML replacement
- `TrajectoryCalculator.swift` — consumes shuttle positions, unchanged by this phase
- Existing Core ML placeholder in HawkEyePipeline

### Established Patterns
- Swift protocol abstractions for testability
- CLAUDE.md: use `/scripts` for utility scripts

### Integration Points
- ShuttleDetecting protocol defined in iOS codebase (new)
- Exported .mlmodel file drops into Xcode project
- HawkEyePipeline adopts ShuttleDetecting protocol in Phase 9

</code_context>

<specifics>
No specific requirements — infrastructure phase

</specifics>

<deferred>
None

</deferred>
