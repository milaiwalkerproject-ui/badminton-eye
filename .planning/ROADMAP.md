# Roadmap: Badminton Eye

## Milestones

- [x] **v1.0 MVP** -- Phases 1-5 (shipped 2026-03-29)
- [x] **v1.1 Hawk Eye Pro + Analytics** -- Phases 6-9 (shipped 2026-03-29)
- [x] **v1.2 Haptic Scoring, BWF 3x15 & Multi-Camera** -- Phases 10-12 (shipped 2026-03-29)
- [x] **v1.3 Live Multi-Cam, Auto-Sync & Custom Scoring** -- Phases 13-15 (shipped 2026-03-29)
- [x] **v1.4 Test Coverage & Accessibility** -- Phases 16-17 (shipped 2026-03-29)
- [x] **v1.5 Watch Haptic Reliability** -- Phase 18 (shipped 2026-03-30)
- [x] **v1.6 Undo Edge Cases & Cross-Game Service Tests** -- Phases 19-20 (shipped 2026-03-30)
- [x] **v1.7 3×15 Service Continuity & Doubles Game-3 Tests** -- Phases 21-22 (shipped 2026-03-30)
- [x] **v1.8 Doubles & Mixed Deuce/Cap Coverage** -- Phases 23-24 (shipped 2026-03-30)
- [x] **v1.9 3×15 Undo & Mixed Doubles Boundary Tests** -- Phases 25-26 (shipped 2026-03-30)
- [ ] **v1.17 3×15 Games 3–4–5 Service Continuity Tests** -- Phase 40 (in progress)

## Phases

<details>
<summary>v1.0 MVP (Phases 1-5) -- SHIPPED 2026-03-29</summary>

- [x] Phase 1: Scoring Engine (3/3 plans)
- [x] Phase 2: Apple Watch Companion (3/3 plans)
- [x] Phase 3: Match Data and Player Profiles (3/3 plans)
- [x] Phase 4: Cloud Sync and Authentication (3/3 plans)
- [x] Phase 5: Hawk Eye AI and Premium (4/4 plans)

</details>

<details>
<summary>v1.1 Hawk Eye Pro + Analytics (Phases 6-9) -- SHIPPED 2026-03-29</summary>

- [x] **Phase 6: Match Analytics** - Statistics dashboard with win streaks, scoring patterns, and performance trends via Swift Charts
- [x] **Phase 7: Training Pipeline** - Python-based YOLO training workflow with annotation guide and CoreML export
- [x] **Phase 8: 240fps Video Capture** - Delegate-based high-frame-rate capture with circular buffer and slow-motion replay
- [x] **Phase 9: Real AI Integration** - Replace placeholder model with trained YOLO, wire through Vision framework and existing trajectory pipeline

</details>

### v1.2 Haptic Scoring, BWF 3x15 & Multi-Camera

**Milestone Goal:** Add haptic score feedback, support BWF's new 3x15 scoring format as a user option, and enable multi-camera Hawk Eye for higher confidence.

- [x] **Phase 10: BWF 3x15 Scoring Format** - Users can play matches using the new BWF best-of-5 games-to-15 scoring format
- [x] **Phase 11: Haptic Score Feedback** - Users feel tactile confirmation on every point, game point, and match point
- [x] **Phase 12: Multi-Camera Hawk Eye** - Users get higher-confidence Hawk Eye calls by providing a second camera angle

## Phase Details

<details>
<summary>v1.0 Phase Details (Phases 1-5) -- SHIPPED</summary>

See [v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md) for full phase details.

</details>

<details>
<summary>v1.1 Phase Details (Phases 6-9) -- SHIPPED</summary>

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
- [x] 06-02-PLAN.md -- Swift Charts trend and scoring pattern visualizations

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
- [x] 07-01-PLAN.md -- ShuttleDetecting protocol and HawkEyePipeline refactor
- [x] 07-02-PLAN.md -- Python training script, annotation guide, and README

### Phase 8: 240fps Video Capture
**Goal**: App captures court-side video at the highest frame rate the device supports for accurate shuttle tracking
**Depends on**: Phase 5 (refactors existing VideoCaptureManager from v1.0)
**Requirements**: CAP-01, CAP-02, CAP-03, CAP-04, CAP-05, CAP-06
**Success Criteria** (what must be TRUE):
  1. On a 240fps-capable device, video capture runs at 240fps with 720p HEVC recording
  2. On devices without high-FPS support, capture falls back to 30fps with a user-visible message explaining the limitation
  3. When the user triggers a Hawk Eye challenge, the last 10 seconds of frames are saved from the circular buffer
  4. User can view a slow-motion replay of captured 240fps footage in the trajectory replay screen
**Plans:** 2 plans
Plans:
- [x] 08-01-PLAN.md -- Refactor VideoCaptureManager to delegate-based 240fps capture with CircularFrameBuffer
- [x] 08-02-PLAN.md -- ChallengeVideoView buffer integration, FPS fallback banner, slow-motion replay

### Phase 9: Real AI Integration
**Goal**: Hawk Eye uses a trained YOLO model for real shuttle detection, replacing the placeholder
**Depends on**: Phase 7 (trained model), Phase 8 (240fps frame pipeline)
**Requirements**: AI-01, AI-02, AI-03, AI-04, AI-05
**Success Criteria** (what must be TRUE):
  1. Hawk Eye challenge uses VNCoreMLRequest with the trained YOLO model to detect shuttlecock positions in video frames
  2. Swapping between placeholder and real model requires only changing the ShuttleDetecting conformance (no pipeline changes)
  3. At 240fps, frame-skip strategy processes every Nth frame to sustain real-time detection without thermal throttling
  4. Detection results flow into the existing TrajectoryCalculator to produce landing spot predictions
**Plans:** 2 plans
Plans:
- [x] 09-01-PLAN.md -- CoreMLShuttleDetector + HawkEyePipeline real-frame analysis with frame-skip
- [x] 09-02-PLAN.md -- Detector selection wiring, fallback logic, and Demo Mode badge

</details>

### Phase 10: BWF 3x15 Scoring Format
**Goal**: Users can select and play a full match using BWF 3x15 scoring rules, with correct persistence, history display, and Watch sync
**Depends on**: Nothing (first phase of v1.2; builds on existing ScoringEngine from v1.0)
**Requirements**: FMT-01, FMT-02, FMT-03, FMT-04, FMT-05, FMT-06, FMT-07
**Success Criteria** (what must be TRUE):
  1. User sees a format picker (standard 21 vs 3x15) on the new match setup screen and can select either
  2. A 3x15 match plays correctly: games to 15, deuce at 14-all, best of 5 games determines the winner
  3. Existing v1.0/v1.1 matches open without errors and default to standard-21 format
  4. Match history clearly shows which scoring format was used for each match
  5. Apple Watch displays the chosen scoring format and syncs 3x15 match state correctly
**Plans**: 2 (TBD)

### Phase 11: Haptic Score Feedback
**Goal**: Users receive distinct haptic pulses on score changes during live play, configurable via a settings toggle that syncs across devices
**Depends on**: Phase 10 (haptic triggers fire on scoring events from either format)
**Requirements**: HAP-01, HAP-02, HAP-03, HAP-04, HAP-05
**Success Criteria** (what must be TRUE):
  1. User can find and toggle haptic feedback on/off in Settings (default is on)
  2. iPhone vibrates with a short tap on every point scored during a live match
  3. iPhone produces a distinct stronger vibration on game point and match point events
  4. Apple Watch delivers haptic feedback on score changes during a live match
  5. Changing the haptic toggle on iPhone reflects on Watch (and vice versa) after sync
**Plans**: 2 (TBD)

### Phase 12: Multi-Camera Hawk Eye
**Goal**: Users can import a second video angle for a Hawk Eye challenge and receive a fused, higher-confidence landing prediction
**Depends on**: Phase 10, Phase 11 (sequential build order; uses stable scoring + haptic foundation)
**Requirements**: CAM-01, CAM-02, CAM-03, CAM-04, CAM-05
**Success Criteria** (what must be TRUE):
  1. User can import a second video angle from their photo library during a Hawk Eye challenge
  2. Each video angle is analyzed independently and the user can see per-angle results
  3. The fused multi-angle result displays a single landing prediction with confidence higher than either angle alone
  4. Single-angle Hawk Eye challenges work exactly as before when no second angle is provided
**Plans**: 2 (TBD)

</details>

### v1.3 Live Multi-Cam, Auto-Sync & Custom Scoring

**Milestone Goal:** Upgrade multi-camera from sequential import to simultaneous live capture with automatic alignment, and let users define custom scoring formats.

- [x] **Phase 13: Custom Scoring Builder** - Users create and play matches with custom scoring rules
- [x] **Phase 14: Audio Cross-Correlation Sync** - Automatically align two separately-recorded videos by audio
- [x] **Phase 15: Live Dual-Camera Capture** - Simultaneous dual-camera via AVCaptureMultiCamSession

## Phase Details (v1.3)

### Phase 13: Custom Scoring Builder
**Goal**: Users can define custom scoring rules and play matches with them
**Depends on**: Nothing (builds on existing ScoringRules from v1.2)
**Requirements**: CUST-01, CUST-02, CUST-03, CUST-04, CUST-05
**Success Criteria** (what must be TRUE):
  1. User can select "Custom" scoring and configure points-to-win, deuce threshold, cap score, and number of games
  2. Invalid configurations are rejected with clear validation messages
  3. Custom format matches survive crash recovery, Watch sync, and CloudKit correctly
  4. Match history shows the custom format parameters for each custom match
  5. A v1.2 device receiving a custom-format match via CloudKit falls back to standard-21 without crash
**Plans**: 2 (TBD)

### Phase 14: Audio Cross-Correlation Sync
**Goal**: Two separately-recorded videos are automatically time-aligned using audio cross-correlation
**Depends on**: Nothing (testable with recorded files independent of camera work)
**Requirements**: SYNC-01, SYNC-02, SYNC-03, SYNC-04
**Success Criteria** (what must be TRUE):
  1. When two video files are imported, their audio tracks are extracted and cross-correlated to find the temporal offset
  2. The cross-correlation runs in under 100ms for 10-second clips using Accelerate/vDSP
  3. The computed offset is applied as PTS adjustment so HawkEyePipeline receives aligned frames without modification
  4. Low-confidence alignments prompt the user to set a manual sync point
**Plans**: 2 (TBD)

### Phase 15: Live Dual-Camera Capture
**Goal**: Supported devices capture from two cameras simultaneously for real-time multi-angle Hawk Eye
**Depends on**: Phase 14 (audio sync for fallback import path)
**Requirements**: DCAM-01, DCAM-02, DCAM-03, DCAM-04, DCAM-05
**Success Criteria** (what must be TRUE):
  1. On A12+ devices, user can enable dual-camera mode in Hawk Eye settings
  2. Dual-camera runs at asymmetric FPS (primary 120fps + secondary 60fps) with synchronized timestamps
  3. Each camera writes to its own CircularFrameBuffer with hardwareCost monitoring
  4. At thermal throttle or on unsupported devices, app gracefully falls back to single-camera 240fps
  5. Existing single-camera 240fps mode is unchanged as the default
**Plans**: 2 (TBD)

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Scoring Engine | v1.0 | 3/3 | Complete | 2026-03-28 |
| 2. Apple Watch Companion | v1.0 | 3/3 | Complete | 2026-03-28 |
| 3. Match Data and Player Profiles | v1.0 | 3/3 | Complete | 2026-03-29 |
| 4. Cloud Sync and Authentication | v1.0 | 3/3 | Complete | 2026-03-29 |
| 5. Hawk Eye AI and Premium | v1.0 | 4/4 | Complete | 2026-03-29 |
| 6. Match Analytics | v1.1 | 2/2 | Complete | 2026-03-29 |
| 7. Training Pipeline | v1.1 | 2/2 | Complete | 2026-03-29 |
| 8. 240fps Video Capture | v1.1 | 2/2 | Complete | 2026-03-29 |
| 9. Real AI Integration | v1.1 | 2/2 | Complete | 2026-03-29 |
| 10. BWF 3x15 Scoring Format | v1.2 | 1/1 | Complete | 2026-03-29 |
| 11. Haptic Score Feedback | v1.2 | 1/1 | Complete | 2026-03-29 |
| 12. Multi-Camera Hawk Eye | v1.2 | 1/1 | Complete | 2026-03-29 |
| 13. Custom Scoring Builder | v1.3 | 1/1 | Complete | 2026-03-29 |
| 14. Audio Cross-Correlation Sync | v1.3 | 1/1 | Complete | 2026-03-29 |
| 15. Live Dual-Camera Capture | v1.3 | 1/1 | Complete | 2026-03-29 |

### v1.4 Test Coverage & Accessibility

**Milestone Goal:** Harden the scoring engine with comprehensive test coverage for custom scoring, Codable round-tripping, and validation, then add VoiceOver accessibility to the live match experience.

- [x] **Phase 16: Custom Scoring & Codable Tests** - Comprehensive ScoringEngine tests for custom rules, validation, Codable, and abandon
- [x] **Phase 17: VoiceOver Accessibility** - Accessibility labels and hints on LiveMatchView and ScorePanel

## Phase Details (v1.4)

### Phase 16: Custom Scoring & Codable Tests
**Goal**: ScoringEngine has complete test coverage for custom scoring rules, validation, Codable round-trips, and the abandon event
**Depends on**: Nothing (tests existing code)
**Requirements**: TEST-01, TEST-02, TEST-03, TEST-04, TEST-05, TEST-06
**Success Criteria** (what must be TRUE):
  1. Custom ScoringRules play a full match correctly through MatchEngine
  2. ScoringRules.isValid correctly identifies valid and invalid configurations
  3. ScoringSystem encodes and decodes for all three variants including custom
  4. v1.2 backward-compatible string decoding works
  5. Abandon event transitions to .abandoned phase
  6. Custom scoring with deuce/cap edge cases works correctly

### Phase 17: VoiceOver Accessibility
**Goal**: VoiceOver users can score a full match using accessibility labels and hints
**Depends on**: Nothing (modifies existing views)
**Requirements**: A11Y-01, A11Y-02, A11Y-03, A11Y-04
**Success Criteria** (what must be TRUE):
  1. ScorePanel announces team name, score, and serving status via VoiceOver
  2. Score tap zones have clear accessibility labels and hints
  3. Undo and End Match buttons have descriptive accessibility labels
  4. Game info is announced to VoiceOver

## Progress (updated)

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Scoring Engine | v1.0 | 3/3 | Complete | 2026-03-28 |
| 2. Apple Watch Companion | v1.0 | 3/3 | Complete | 2026-03-28 |
| 3. Match Data and Player Profiles | v1.0 | 3/3 | Complete | 2026-03-29 |
| 4. Cloud Sync and Authentication | v1.0 | 3/3 | Complete | 2026-03-29 |
| 5. Hawk Eye AI and Premium | v1.0 | 4/4 | Complete | 2026-03-29 |
| 6. Match Analytics | v1.1 | 2/2 | Complete | 2026-03-29 |
| 7. Training Pipeline | v1.1 | 2/2 | Complete | 2026-03-29 |
| 8. 240fps Video Capture | v1.1 | 2/2 | Complete | 2026-03-29 |
| 9. Real AI Integration | v1.1 | 2/2 | Complete | 2026-03-29 |
| 10. BWF 3x15 Scoring Format | v1.2 | 1/1 | Complete | 2026-03-29 |
| 11. Haptic Score Feedback | v1.2 | 1/1 | Complete | 2026-03-29 |
| 12. Multi-Camera Hawk Eye | v1.2 | 1/1 | Complete | 2026-03-29 |
| 13. Custom Scoring Builder | v1.3 | 1/1 | Complete | 2026-03-29 |
| 14. Audio Cross-Correlation Sync | v1.3 | 1/1 | Complete | 2026-03-29 |
| 15. Live Dual-Camera Capture | v1.3 | 1/1 | Complete | 2026-03-29 |
| 16. Custom Scoring & Codable Tests | v1.4 | 1/1 | Complete | 2026-03-29 |
| 17. VoiceOver Accessibility | v1.4 | 1/1 | Complete | 2026-03-29 |
| 18. Watch Haptic Reliability | v1.5 | 1/1 | Complete | 2026-03-30 |
| 19. Undo Edge Cases | v1.6 | 1/1 | Complete | 2026-03-30 |
| 20. Cross-Game Service Tests | v1.6 | 1/1 | Complete | 2026-03-30 |

### v1.6 Undo Edge Cases & Cross-Game Service Tests

**Milestone Goal:** Fill critical test coverage gaps: undo of match-winning points, undo during deuce, undo clearing mid-game switch state, and cross-game service continuity.

- [x] **Phase 19: Undo Edge Cases** - Three tests covering match-win undo, deuce undo, mid-switch undo
- [x] **Phase 20: Cross-Game Service Tests** - Two tests documenting service continuity across games

### v1.5 Watch Haptic Reliability

**Milestone Goal:** Fix the Watch haptics threading bug: mark WatchMatchViewModel @MainActor and play haptic feedback for iPhone-initiated score changes.

- [x] **Phase 18: @MainActor + Receive-Side Haptics** - WatchMatchViewModel is @MainActor-isolated; Watch plays haptic when iPhone scores

## Phase Details (v1.5)

### Phase 18: @MainActor + Receive-Side Haptics
**Goal**: Watch plays correct haptic feedback for both Watch-initiated and iPhone-initiated score changes, with no double-haptic
**Depends on**: Nothing (modifies WatchMatchViewModel and WatchScoringView)
**Requirements**: HAP-W01, HAP-W02, HAP-W03, HAP-W04, HAP-W05, HAP-W06
**Success Criteria** (what must be TRUE):
  1. WatchMatchViewModel is annotated @MainActor
  2. When iPhone sends a score update, Watch plays click/success/notification haptic as appropriate
  3. Watch-initiated scores still play exactly one haptic (no double on iPhone echo)
  4. Haptic toggle is respected

### v1.7 3×15 Service Continuity & Doubles Game-3 Tests

**Milestone Goal:** Close remaining cross-game service test gaps: who serves first in 3×15 games 2 and 3, doubles game 2→3 service reset, and undo across a game boundary in doubles.

- [x] **Phase 21: 3×15 Cross-Game Service** - Two tests verifying loser serves in game 2 and game 3 under 3×15 format
- [x] **Phase 22: Doubles Game-3 & Boundary Undo** - Test that doubles game 2→3 correctly resets rotation to loser's side, plus undo of first game-2 point restores cross-game state

## Phase Details (v1.7)

### Phase 21: 3×15 Cross-Game Service
**Goal**: ScoringEngine correctly resets service to the loser at each game transition under the 3×15 scoring format
**Depends on**: Nothing (tests existing code)
**Requirements**: SVC3X-01, SVC3X-02
**Success Criteria** (what must be TRUE):
  1. After sideA wins game 1 (15-0) in 3×15, sideB serves first in game 2 from the right court
  2. After sideB wins game 2 in 3×15, sideA (loser of game 2) serves first in game 3

### Phase 22: Doubles Game-3 & Boundary Undo
**Goal**: Doubles game 2→3 service reset is tested; undo across a game boundary in doubles is verified
**Depends on**: Nothing (tests existing code)
**Requirements**: DBLS3-01, UNDO-G-01
**Success Criteria** (what must be TRUE):
  1. After sideA wins game 1 and sideB wins game 2 (doubles), sideA serves first in game 3 with doublesRotation[0].side == .sideA
  2. Undoing the first point of game 2 restores the pre-first-point game-2 state: server, rotation, score all correct, game 1 still in games array

## Progress (updated)

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Scoring Engine | v1.0 | 3/3 | Complete | 2026-03-28 |
| 2. Apple Watch Companion | v1.0 | 3/3 | Complete | 2026-03-28 |
| 3. Match Data and Player Profiles | v1.0 | 3/3 | Complete | 2026-03-29 |
| 4. Cloud Sync and Authentication | v1.0 | 3/3 | Complete | 2026-03-29 |
| 5. Hawk Eye AI and Premium | v1.0 | 4/4 | Complete | 2026-03-29 |
| 6. Match Analytics | v1.1 | 2/2 | Complete | 2026-03-29 |
| 7. Training Pipeline | v1.1 | 2/2 | Complete | 2026-03-29 |
| 8. 240fps Video Capture | v1.1 | 2/2 | Complete | 2026-03-29 |
| 9. Real AI Integration | v1.1 | 2/2 | Complete | 2026-03-29 |
| 10. BWF 3x15 Scoring Format | v1.2 | 1/1 | Complete | 2026-03-29 |
| 11. Haptic Score Feedback | v1.2 | 1/1 | Complete | 2026-03-29 |
| 12. Multi-Camera Hawk Eye | v1.2 | 1/1 | Complete | 2026-03-29 |
| 13. Custom Scoring Builder | v1.3 | 1/1 | Complete | 2026-03-29 |
| 14. Audio Cross-Correlation Sync | v1.3 | 1/1 | Complete | 2026-03-29 |
| 15. Live Dual-Camera Capture | v1.3 | 1/1 | Complete | 2026-03-29 |
| 16. Custom Scoring & Codable Tests | v1.4 | 1/1 | Complete | 2026-03-29 |
| 17. VoiceOver Accessibility | v1.4 | 1/1 | Complete | 2026-03-29 |
| 18. Watch Haptic Reliability | v1.5 | 1/1 | Complete | 2026-03-30 |
| 19. Undo Edge Cases | v1.6 | 1/1 | Complete | 2026-03-30 |
| 20. Cross-Game Service Tests | v1.6 | 1/1 | Complete | 2026-03-30 |
| 21. 3×15 Cross-Game Service | v1.7 | 1/1 | Complete | 2026-03-30 |
| 22. Doubles Game-3 & Boundary Undo | v1.7 | 1/1 | Complete | 2026-03-30 |

### v1.8 Doubles & Mixed Deuce/Cap Coverage

**Milestone Goal:** Fill remaining deuce/cap and mid-game-switch coverage gaps for doubles and mixed doubles — DeuceAndCapTests previously only exercised singles.

- [x] **Phase 23: Doubles Deuce, Cap & Mid-Game Switch** - Five tests covering deuce at 20-20, 21-20 not a win, cap at 30-29, mid-game switch at 11, and undo during deuce
- [x] **Phase 24: Mixed Doubles Game-3 Service** - One test confirming loser of game 2 serves first in game 3 for mixed doubles

## Phase Details (v1.8)

### Phase 23: Doubles Deuce, Cap & Mid-Game Switch
**Goal**: DoublesScoringTests has explicit coverage for deuce, cap, mid-game switch, and undo-during-deuce
**Depends on**: Nothing (tests existing code)
**Requirements**: DUB-DCE-01, DUB-DCE-02, DUB-DCE-03, DUB-MID-01, DUB-UND-01
**Success Criteria** (what must be TRUE):
  1. isDeuce is true at 20-20 in a doubles match
  2. 21-20 does not complete the game (2-point lead required)
  3. 30-29 completes the game (cap rule)
  4. shouldSwitchSidesFlag is true when either side reaches 11 in doubles game 3
  5. Undo at 21-20 in doubles reverts to 20-20 with the correct server

### Phase 24: Mixed Doubles Game-3 Service
**Goal**: MixedDoublesScoringTests confirms cross-game service continuity through game 3
**Depends on**: Nothing (tests existing code)
**Requirements**: MXD-G3-01
**Success Criteria** (what must be TRUE):
  1. After sideA wins game 1 and sideB wins game 2 in mixed doubles, sideA serves first in game 3

## Progress (updated)

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Scoring Engine | v1.0 | 3/3 | Complete | 2026-03-28 |
| 2. Apple Watch Companion | v1.0 | 3/3 | Complete | 2026-03-28 |
| 3. Match Data and Player Profiles | v1.0 | 3/3 | Complete | 2026-03-29 |
| 4. Cloud Sync and Authentication | v1.0 | 3/3 | Complete | 2026-03-29 |
| 5. Hawk Eye AI and Premium | v1.0 | 4/4 | Complete | 2026-03-29 |
| 6. Match Analytics | v1.1 | 2/2 | Complete | 2026-03-29 |
| 7. Training Pipeline | v1.1 | 2/2 | Complete | 2026-03-29 |
| 8. 240fps Video Capture | v1.1 | 2/2 | Complete | 2026-03-29 |
| 9. Real AI Integration | v1.1 | 2/2 | Complete | 2026-03-29 |
| 10. BWF 3x15 Scoring Format | v1.2 | 1/1 | Complete | 2026-03-29 |
| 11. Haptic Score Feedback | v1.2 | 1/1 | Complete | 2026-03-29 |
| 12. Multi-Camera Hawk Eye | v1.2 | 1/1 | Complete | 2026-03-29 |
| 13. Custom Scoring Builder | v1.3 | 1/1 | Complete | 2026-03-29 |
| 14. Audio Cross-Correlation Sync | v1.3 | 1/1 | Complete | 2026-03-29 |
| 15. Live Dual-Camera Capture | v1.3 | 1/1 | Complete | 2026-03-29 |
| 16. Custom Scoring & Codable Tests | v1.4 | 1/1 | Complete | 2026-03-29 |
| 17. VoiceOver Accessibility | v1.4 | 1/1 | Complete | 2026-03-29 |
| 18. Watch Haptic Reliability | v1.5 | 1/1 | Complete | 2026-03-30 |
| 19. Undo Edge Cases | v1.6 | 1/1 | Complete | 2026-03-30 |
| 20. Cross-Game Service Tests | v1.6 | 1/1 | Complete | 2026-03-30 |
| 21. 3×15 Cross-Game Service | v1.7 | 1/1 | Complete | 2026-03-30 |
| 22. Doubles Game-3 & Boundary Undo | v1.7 | 1/1 | Complete | 2026-03-30 |
| 23. Doubles Deuce, Cap & Mid-Game Switch | v1.8 | 1/1 | Complete | 2026-03-30 |
| 24. Mixed Doubles Game-3 Service | v1.8 | 1/1 | Complete | 2026-03-30 |

### v1.9 3×15 Undo & Mixed Doubles Boundary Tests

**Milestone Goal:** Fill the undo coverage gaps for the 3×15 scoring format and add missing undo/mid-switch tests for mixed doubles — ThreeByFifteenTests has zero undo tests, MixedDoublesScoringTests has no undo or mid-switch coverage.

- [x] **Phase 25: 3×15 Undo Edge Cases** - Three undo tests for 3×15 format: deuce undo, mid-switch undo in 5th game, cross-game boundary undo
- [x] **Phase 26: Mixed Doubles Undo & Mid-Switch** - Undo across game-1 boundary in mixed doubles; game-3 mid-switch at 11 points

## Phase Details (v1.9)

### Phase 25: 3×15 Undo Edge Cases
**Goal**: ThreeByFifteenTests has undo coverage equivalent to what UndoTests provides for standard singles
**Depends on**: Nothing (tests existing code)
**Requirements**: THX-UND-01, THX-UND-02, THX-UND-03
**Success Criteria** (what must be TRUE):
  1. Undo at 15-14 in 3×15 reverts to 14-14 with isDeuce true
  2. Undo of the 8-point trigger in the 5th game clears hasSwitchedInThirdGame and shouldSwitchSidesFlag
  3. Undo of the first point of 3×15 game 3 restores server, score, and completed games correctly

### Phase 26: Mixed Doubles Undo & Mid-Switch
**Goal**: MixedDoublesScoringTests has undo-across-game-boundary and game-3 mid-switch coverage
**Depends on**: Nothing (tests existing code)
**Requirements**: MXD-UND-01, MXD-MID-01
**Success Criteria** (what must be TRUE):
  1. Undo of the first point of mixed doubles game 2 restores the pre-game-end state (server, rotation, score, game 1 still in games array)
  2. In mixed doubles game 3, shouldSwitchSidesFlag fires when total points reach 11 (same threshold as standard doubles)

## Progress (updated)

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Scoring Engine | v1.0 | 3/3 | Complete | 2026-03-28 |
| 2. Apple Watch Companion | v1.0 | 3/3 | Complete | 2026-03-28 |
| 3. Match Data and Player Profiles | v1.0 | 3/3 | Complete | 2026-03-29 |
| 4. Cloud Sync and Authentication | v1.0 | 3/3 | Complete | 2026-03-29 |
| 5. Hawk Eye AI and Premium | v1.0 | 4/4 | Complete | 2026-03-29 |
| 6. Match Analytics | v1.1 | 2/2 | Complete | 2026-03-29 |
| 7. Training Pipeline | v1.1 | 2/2 | Complete | 2026-03-29 |
| 8. 240fps Video Capture | v1.1 | 2/2 | Complete | 2026-03-29 |
| 9. Real AI Integration | v1.1 | 2/2 | Complete | 2026-03-29 |
| 10. BWF 3x15 Scoring Format | v1.2 | 1/1 | Complete | 2026-03-29 |
| 11. Haptic Score Feedback | v1.2 | 1/1 | Complete | 2026-03-29 |
| 12. Multi-Camera Hawk Eye | v1.2 | 1/1 | Complete | 2026-03-29 |
| 13. Custom Scoring Builder | v1.3 | 1/1 | Complete | 2026-03-29 |
| 14. Audio Cross-Correlation Sync | v1.3 | 1/1 | Complete | 2026-03-29 |
| 15. Live Dual-Camera Capture | v1.3 | 1/1 | Complete | 2026-03-29 |
| 16. Custom Scoring & Codable Tests | v1.4 | 1/1 | Complete | 2026-03-29 |
| 17. VoiceOver Accessibility | v1.4 | 1/1 | Complete | 2026-03-29 |
| 18. Watch Haptic Reliability | v1.5 | 1/1 | Complete | 2026-03-30 |
| 19. Undo Edge Cases | v1.6 | 1/1 | Complete | 2026-03-30 |
| 20. Cross-Game Service Tests | v1.6 | 1/1 | Complete | 2026-03-30 |
| 21. 3×15 Cross-Game Service | v1.7 | 1/1 | Complete | 2026-03-30 |
| 22. Doubles Game-3 & Boundary Undo | v1.7 | 1/1 | Complete | 2026-03-30 |
| 23. Doubles Deuce, Cap & Mid-Game Switch | v1.8 | 1/1 | Complete | 2026-03-30 |
| 24. Mixed Doubles Game-3 Service | v1.8 | 1/1 | Complete | 2026-03-30 |
| 25. 3×15 Undo Edge Cases | v1.9 | 1/1 | Complete | 2026-03-30 |
| 26. Mixed Doubles Undo & Mid-Switch | v1.9 | 1/1 | Complete | 2026-03-30 |

### v1.10 Localize Remaining Views

**Milestone Goal:** Wire existing Localizable.strings keys to views that hardcode English, and add new keys for game-over/match-end flows — enabling the language switcher to work across the full app.

- [x] **Phase 27: Wire Existing Keys** - MatchHistoryView, StatsView, LiveMatchView use existing history/stats/match keys
- [x] **Phase 28: New Keys + Game/Match End** - Add game.over/game.continue/match.new/match.games to all 9 language files; wire GameEndOverlay and MatchEndView

## Phase Details (v1.10)

### Phase 27: Wire Existing Keys
**Goal**: MatchHistoryView, StatsView, and LiveMatchView use LocalizationManager for their UI strings instead of hardcoded English
**Depends on**: Nothing (modifies existing views)
**Requirements**: LOC-01, LOC-02, LOC-03
**Success Criteria** (what must be TRUE):
  1. Switching to Japanese in Settings causes MatchHistoryView to show "試合履歴" as its title
  2. StatsView shows "勝ち" and "負け" labels when Japanese is active
  3. LiveMatchView game label reads "ゲーム 1" in Japanese

### Phase 28: New Keys + Game/Match End
**Goal**: GameEndOverlay and MatchEndView use localized strings; all 9 Localizable.strings files include new game/match-end keys
**Depends on**: Phase 27 (establishes localization pattern in views)
**Requirements**: LOC-04, LOC-05, LOC-06
**Success Criteria** (what must be TRUE):
  1. All 9 Localizable.strings files contain game.over, game.continue, match.new, match.games keys
  2. GameEndOverlay "Game Over" title and button labels use localized keys
  3. MatchEndView "New Match" button and "Games" tally row use localized keys

## Progress (updated)

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Scoring Engine | v1.0 | 3/3 | Complete | 2026-03-28 |
| 2. Apple Watch Companion | v1.0 | 3/3 | Complete | 2026-03-28 |
| 3. Match Data and Player Profiles | v1.0 | 3/3 | Complete | 2026-03-29 |
| 4. Cloud Sync and Authentication | v1.0 | 3/3 | Complete | 2026-03-29 |
| 5. Hawk Eye AI and Premium | v1.0 | 4/4 | Complete | 2026-03-29 |
| 6. Match Analytics | v1.1 | 2/2 | Complete | 2026-03-29 |
| 7. Training Pipeline | v1.1 | 2/2 | Complete | 2026-03-29 |
| 8. 240fps Video Capture | v1.1 | 2/2 | Complete | 2026-03-29 |
| 9. Real AI Integration | v1.1 | 2/2 | Complete | 2026-03-29 |
| 10. BWF 3x15 Scoring Format | v1.2 | 1/1 | Complete | 2026-03-29 |
| 11. Haptic Score Feedback | v1.2 | 1/1 | Complete | 2026-03-29 |
| 12. Multi-Camera Hawk Eye | v1.2 | 1/1 | Complete | 2026-03-29 |
| 13. Custom Scoring Builder | v1.3 | 1/1 | Complete | 2026-03-29 |
| 14. Audio Cross-Correlation Sync | v1.3 | 1/1 | Complete | 2026-03-29 |
| 15. Live Dual-Camera Capture | v1.3 | 1/1 | Complete | 2026-03-29 |
| 16. Custom Scoring & Codable Tests | v1.4 | 1/1 | Complete | 2026-03-29 |
| 17. VoiceOver Accessibility | v1.4 | 1/1 | Complete | 2026-03-29 |
| 18. Watch Haptic Reliability | v1.5 | 1/1 | Complete | 2026-03-30 |
| 19. Undo Edge Cases | v1.6 | 1/1 | Complete | 2026-03-30 |
| 20. Cross-Game Service Tests | v1.6 | 1/1 | Complete | 2026-03-30 |
| 21. 3×15 Cross-Game Service | v1.7 | 1/1 | Complete | 2026-03-30 |
| 22. Doubles Game-3 & Boundary Undo | v1.7 | 1/1 | Complete | 2026-03-30 |
| 23. Doubles Deuce, Cap & Mid-Game Switch | v1.8 | 1/1 | Complete | 2026-03-30 |
| 24. Mixed Doubles Game-3 Service | v1.8 | 1/1 | Complete | 2026-03-30 |
| 25. 3×15 Undo Edge Cases | v1.9 | 1/1 | Complete | 2026-03-30 |
| 26. Mixed Doubles Undo & Mid-Switch | v1.9 | 1/1 | Complete | 2026-03-30 |
| 27. Wire Existing Localization Keys | v1.10 | 1/1 | Complete | 2026-03-31 |
| 28. New Keys + Game/Match End | v1.10 | 1/1 | Complete | 2026-03-31 |
| 29. SettingsView & MatchSetupView Localization | v1.11 | 1/1 | Complete | 2026-03-31 |
| 30. PlayerListView Localization | v1.11 | 1/1 | Complete | 2026-03-31 |
| 31. HeadToHeadView, PlayerProfileView & STR-01 Keys | v1.12 | 1/1 | Complete | 2026-03-31 |
| 32. Analytics Charts & MatchDetailView Localization | v1.12 | 1/1 | Complete | 2026-03-31 |
| 33. Format String Keys + MatchDetailView & HeadToHeadView | v1.13 | 1/1 | Complete | 2026-03-31 |
| 34. PlayerProfileView Alert & TrendRange Display Names | v1.13 | 1/1 | Complete | 2026-03-31 |

---

### v1.13 Complete Format String Localizations

**Milestone Goal:** Add `game.number`, `headtohead.matchesVs`, `player.deleteMessage`, and `chart.last10/20/50` format string keys to all 9 language files, and wire each view to use them.

- [x] **Phase 33: Format Keys + MatchDetailView/HeadToHeadView** — Add 6 format string keys to all 9 Localizable.strings; wire MatchDetailView "Game N" rows and HeadToHeadView "Matches vs" header
- [x] **Phase 34: PlayerProfileView Alert + TrendRange Labels** — Wire PlayerProfileView delete alert message; add `localizationKey` to `TrendRange` and wire Picker; build + test

## Phase Details (v1.13)

### Phase 33: Format Keys + MatchDetailView/HeadToHeadView
**Goal**: All 9 Localizable.strings files contain the 6 new format string keys; MatchDetailView and HeadToHeadView use them
**Depends on**: Nothing
**Requirements**: FMT-01, FMT-02, FMT-03, FMT-04
**Success Criteria**:
  1. Switching to Japanese: MatchDetailView decoded rows show "第1ゲーム", "第2ゲーム"
  2. Switching to Japanese: MatchDetailView fallback rows show "第1ゲーム" etc.
  3. Switching to Danish: HeadToHeadView opponent filter section shows "Kampe mod [name]"

### Phase 34: PlayerProfileView Alert + TrendRange Labels
**Goal**: PlayerProfileView alert message is localized; WinRateTrendChart range picker uses localized labels; build passes with 95 tests
**Depends on**: Phase 33 (language file additions)
**Requirements**: FMT-05, FMT-06
**Success Criteria**:
  1. Switching to Chinese: delete alert message shows "这将从您的球员列表中永久删除 [name]。"
  2. Switching to Japanese: range picker shows "直近10試合", "直近20試合", "直近50試合"
  3. All 95 tests pass; build succeeds

---

### v1.14 Analytics Localization & Accessibility

**Milestone Goal:** Wire the two existing-but-unused `stats.winRate` / `stats.streak` localization keys, add four new format-string keys for remaining hardcoded English in StatsView, and give VoiceOver users a meaningful experience on the Stats screen and both analytics charts.

- [x] **Phase 35: Stats Localization Wire-up** — Add 4 new keys to all 9 language files; replace 5 hardcoded strings in StatsView
- [x] **Phase 36: Analytics VoiceOver Accessibility** — Accessibility labels on StatsView summary card, WinRateTrendChart, ScoringPatternsChart

## Phase Details (v1.14)

### Phase 35: Stats Localization Wire-up
**Goal**: StatsView has no hardcoded English strings; four new format keys cover win rate, streak, play-more prompt, and match-count progress
**Depends on**: Nothing
**Requirements**: STAT-01, STAT-02, STAT-03
**Success Criteria**:
  1. Switching to Japanese: win rate label shows "勝率 X%"
  2. Switching to Chinese: streak badge shows "连胜 N 场"
  3. Empty state text is fully localized across all 9 languages

### Phase 36: Analytics VoiceOver Accessibility
**Goal**: VoiceOver users receive meaningful descriptions for StatsView summary card and both analytics charts
**Depends on**: Phase 35
**Requirements**: ACC-01, ACC-02, ACC-03
**Success Criteria**:
  1. StatsView summary card reads as a single combined element (wins, losses, win rate, streak)
  2. WinRateTrendChart chart has an accessibility label summarising current win rate
  3. ScoringPatternsChart chart has an accessibility label describing per-game scoring data
  4. All 95 tests pass; build succeeds

---
| 35. Stats Localization Wire-up | v1.14 | 1/1 | Complete | 2026-03-31 |
| 36. Analytics VoiceOver Accessibility | v1.14 | 1/1 | Complete | 2026-03-31 |

---
*Roadmap updated: 2026-03-31 — v1.14 shipped*
