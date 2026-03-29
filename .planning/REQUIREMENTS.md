# Requirements: Badminton Eye v1.1 — Hawk Eye Pro + Analytics

**Defined:** 2026-03-29
**Core Value:** Make Hawk Eye production-ready with real AI shuttle detection and 240fps capture, and add match analytics for competitive players.

## v1.1 Requirements

### Real AI Shuttle Detection

- [ ] **AI-01**: App uses a trained YOLO Core ML model (not placeholder) to detect shuttlecock positions in video frames
- [ ] **AI-02**: ShuttleDetecting protocol abstracts detection so placeholder and real model are swappable without pipeline changes
- [ ] **AI-03**: Model runs on-device via Vision framework VNCoreMLRequest with no cloud dependency
- [ ] **AI-04**: Frame-skip strategy processes every Nth frame at high FPS to balance accuracy with Neural Engine throughput
- [ ] **AI-05**: Detection results feed into existing TrajectoryCalculator for landing spot prediction

### 240fps Video Capture

- [ ] **CAP-01**: VideoCaptureManager uses AVCaptureVideoDataOutput with delegate-based frame handling (not MovieFileOutput)
- [ ] **CAP-02**: App enumerates device formats and selects highest available frame rate (240fps preferred, falls back to 120fps, then 30fps)
- [ ] **CAP-03**: Video recorded at 720p HEVC for optimal file size and ML input compatibility
- [ ] **CAP-04**: Circular buffer retains last 10 seconds of frames, flushed to disk on challenge trigger
- [ ] **CAP-05**: Graceful fallback: devices without high-FPS support use 30fps with clear user messaging
- [ ] **CAP-06**: Slow-motion replay of captured 240fps footage in TrajectoryReplayView

### Match Analytics

- [ ] **STAT-01**: User can view match statistics dashboard showing wins, losses, win rate, and current win streak
- [ ] **STAT-02**: User can view performance trend chart (win rate over last 10/20/50 matches) using Swift Charts
- [ ] **STAT-03**: User can view per-game scoring patterns (point distribution across games 1, 2, 3)
- [ ] **STAT-04**: Analytics data computed from existing PersistedMatch and game-level scores (no new data model required for v1.1)
- [ ] **STAT-05**: Analytics views accessible from a new "Stats" tab in the main TabView

### Training Pipeline (Developer Tooling)

- [ ] **TRAIN-01**: Python training script using Ultralytics YOLO nano with CoreML export
- [ ] **TRAIN-02**: Annotation guide documenting shuttlecock labeling requirements (bounding boxes, motion blur handling)
- [ ] **TRAIN-03**: Exported .mlmodel file integrates with existing HawkEyePipeline via ShuttleDetecting protocol
- [ ] **TRAIN-04**: Training README with dataset requirements (2,000+ annotated images, diverse courts/lighting)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Multi-camera fusion | Requires device networking and frame sync — too much scope, defer to v1.2 |
| Per-rally event model | Requires SwiftData migration — game-level aggregation sufficient for v1.1 analytics |
| Social leaderboards | Backend infrastructure required — defer to v2+ |
| Real-time live detection during play | Thermal/battery concerns — keep challenge-based flow |
| Custom model training by users | Massively complex UX — ship one well-trained model |
| Score announcements (voice/haptic) | Nice-to-have — defer to v1.2 |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| AI-01 | — | Pending |
| AI-02 | — | Pending |
| AI-03 | — | Pending |
| AI-04 | — | Pending |
| AI-05 | — | Pending |
| CAP-01 | — | Pending |
| CAP-02 | — | Pending |
| CAP-03 | — | Pending |
| CAP-04 | — | Pending |
| CAP-05 | — | Pending |
| CAP-06 | — | Pending |
| STAT-01 | — | Pending |
| STAT-02 | — | Pending |
| STAT-03 | — | Pending |
| STAT-04 | — | Pending |
| STAT-05 | — | Pending |
| TRAIN-01 | — | Pending |
| TRAIN-02 | — | Pending |
| TRAIN-03 | — | Pending |
| TRAIN-04 | — | Pending |

**Coverage:**
- v1.1 requirements: 20 total
- Mapped to phases: 0
- Unmapped: 20

---
*Requirements defined: 2026-03-29*
