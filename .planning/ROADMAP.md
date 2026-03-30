# Roadmap: Badminton Eye

## Milestones

- ✅ **v1.0 MVP** -- Phases 1-5 (shipped 2026-03-29)
- **v1.1 Hawk Eye Pro + Analytics** -- Phases 6-9 (in progress)

## Phases

<details>
<summary>v1.0 MVP (Phases 1-5) -- SHIPPED 2026-03-29</summary>

- [x] Phase 1: Scoring Engine (3/3 plans)
- [x] Phase 2: Apple Watch Companion (3/3 plans)
- [x] Phase 3: Match Data and Player Profiles (3/3 plans)
- [x] Phase 4: Cloud Sync and Authentication (3/3 plans)
- [x] Phase 5: Hawk Eye AI and Premium (4/4 plans)

</details>

### v1.1 Hawk Eye Pro + Analytics

**Milestone Goal:** Make Hawk Eye production-ready with real AI shuttle detection and 240fps capture, and add match analytics for competitive players.

- [ ] **Phase 6: Match Analytics** - Statistics dashboard with win streaks, scoring patterns, and performance trends via Swift Charts
- [ ] **Phase 7: Training Pipeline** - Python-based YOLO training workflow with annotation guide and CoreML export
- [ ] **Phase 8: 240fps Video Capture** - Delegate-based high-frame-rate capture with circular buffer and slow-motion replay
- [ ] **Phase 9: Real AI Integration** - Replace placeholder model with trained YOLO, wire through Vision framework and existing trajectory pipeline

## Phase Details

### Phase 6: Match Analytics
**Goal**: Competitive players can analyze their performance through statistics and trend charts
**Depends on**: Phase 5 (uses existing PersistedMatch data from v1.0)
**Requirements**: STAT-01, STAT-02, STAT-03, STAT-04, STAT-05
**Success Criteria** (what must be TRUE):
  1. User can open a "Stats" tab and see their overall win rate, win/loss counts, and current win streak
  2. User can view a line chart of their win rate over their last 10, 20, or 50 matches
  3. User can view per-game point distribution patterns across games 1, 2, and 3
  4. All analytics compute from existing match data with no data migration required
**Plans:** 2 plans
Plans:
- [x] 06-01-PLAN.md -- MatchStatsViewModel + Stats tab + summary card
- [ ] 06-02-PLAN.md -- Swift Charts trend and scoring pattern visualizations

### Phase 7: Training Pipeline
**Goal**: Developer can train a YOLO nano model on badminton footage and export a production CoreML model
**Depends on**: Nothing (runs in parallel with Phase 6)
**Requirements**: TRAIN-01, TRAIN-02, TRAIN-03, TRAIN-04
**Success Criteria** (what must be TRUE):
  1. Running the Python training script on an annotated dataset produces a .mlmodel file
  2. Exported .mlmodel integrates with HawkEyePipeline via the ShuttleDetecting protocol without code changes
  3. Annotation guide exists documenting bounding box labeling for shuttlecocks including motion blur cases
  4. Training README specifies dataset requirements (2,000+ images, diverse courts/lighting)
**Plans:** 2 plans
Plans:
- [ ] 07-01-PLAN.md -- ShuttleDetecting protocol and HawkEyePipeline refactor
- [ ] 07-02-PLAN.md -- Python training script, annotation guide, and README

### Phase 8: 240fps Video Capture
**Goal**: App captures court-side video at the highest frame rate the device supports for accurate shuttle tracking
**Depends on**: Phase 5 (refactors existing VideoCaptureManager from v1.0)
**Requirements**: CAP-01, CAP-02, CAP-03, CAP-04, CAP-05, CAP-06
**Success Criteria** (what must be TRUE):
  1. On a 240fps-capable device, video capture runs at 240fps with 720p HEVC recording
  2. On devices without high-FPS support, capture falls back to 30fps with a user-visible message explaining the limitation
  3. When the user triggers a Hawk Eye challenge, the last 10 seconds of frames are saved from the circular buffer
  4. User can view a slow-motion replay of captured 240fps footage in the trajectory replay screen
**Plans**: TBD

### Phase 9: Real AI Integration
**Goal**: Hawk Eye uses a trained YOLO model for real shuttle detection, replacing the placeholder
**Depends on**: Phase 7 (trained model), Phase 8 (240fps frame pipeline)
**Requirements**: AI-01, AI-02, AI-03, AI-04, AI-05
**Success Criteria** (what must be TRUE):
  1. Hawk Eye challenge uses VNCoreMLRequest with the trained YOLO model to detect shuttlecock positions in video frames
  2. Swapping between placeholder and real model requires only changing the ShuttleDetecting conformance (no pipeline changes)
  3. At 240fps, frame-skip strategy processes every Nth frame to sustain real-time detection without thermal throttling
  4. Detection results flow into the existing TrajectoryCalculator to produce landing spot predictions
**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Scoring Engine | v1.0 | 3/3 | Complete | 2026-03-28 |
| 2. Apple Watch Companion | v1.0 | 3/3 | Complete | 2026-03-28 |
| 3. Match Data and Player Profiles | v1.0 | 3/3 | Complete | 2026-03-29 |
| 4. Cloud Sync and Authentication | v1.0 | 3/3 | Complete | 2026-03-29 |
| 5. Hawk Eye AI and Premium | v1.0 | 4/4 | Complete | 2026-03-29 |
| 6. Match Analytics | v1.1 | 1/2 | In Progress | - |
| 7. Training Pipeline | v1.1 | 0/2 | Not started | - |
| 8. 240fps Video Capture | v1.1 | 0/? | Not started | - |
| 9. Real AI Integration | v1.1 | 0/? | Not started | - |
