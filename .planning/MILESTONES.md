# Milestones

## v1.5 — Watch Haptic Reliability

**Shipped:** 2026-03-30
**Phases:** 1 (18) | **Requirements:** 6/6 verified
**Tests:** 75 (9 suites)

### Key Accomplishments

1. **@MainActor WatchMatchViewModel** — Explicit main-actor isolation resolves the threading concern; state mutations are now compiler-enforced on the main thread
2. **Receive-side haptics** — Watch plays click/success/notification haptics when iPhone scores, fixing the silent-update gap
3. **No double-haptic** — Watch-initiated scores skip the receive-side haptic when iPhone echoes state back (wasLocallyUpdated guard)

### Archive

- [v1.5-ROADMAP.md](milestones/v1.5-ROADMAP.md)
- [v1.5-REQUIREMENTS.md](milestones/v1.5-REQUIREMENTS.md)

---

## v1.4 — Test Coverage & Accessibility

**Shipped:** 2026-03-29
**Phases:** 2 (16-17) | **Requirements:** 10/10 verified
**Tests:** 75 (9 suites)

### Key Accomplishments

1. **Custom scoring engine tests** — CustomScoringTests covering custom rules, validation, Codable round-trips, backward compat, and abandon
2. **VoiceOver accessibility** — ScorePanel, LiveMatchView score tap zones, Undo/End Match buttons, and game info overlay all have accessibility labels and hints

### Archive

- [v1.4-ROADMAP.md](milestones/v1.4-ROADMAP.md)
- [v1.4-REQUIREMENTS.md](milestones/v1.4-REQUIREMENTS.md)

---

## v1.3 — Live Multi-Cam, Auto-Sync & Custom Scoring

**Shipped:** 2026-03-29
**Phases:** 3 (13-15) | **Requirements:** 14/14 verified
**Tests:** 53 (8 suites)

### Key Accomplishments

1. **Custom scoring builder** — ScoringFormatBuilderView with validation, Codable ScoringRules, backward-compatible ScoringSystem encoding
2. **Audio cross-correlation sync** — AudioTemporalSync using Accelerate/vDSP for sub-100ms alignment of separate video recordings
3. **Live dual-camera capture** — MultiCamCaptureManager with AVCaptureMultiCamSession, asymmetric FPS, thermal throttle fallback

### Archive

- [v1.3-ROADMAP.md](milestones/v1.3-ROADMAP.md)
- [v1.3-REQUIREMENTS.md](milestones/v1.3-REQUIREMENTS.md)

---

## v1.2 — Haptic Scoring, BWF 3×15 & Multi-Camera

**Shipped:** 2026-03-29
**Phases:** 3 (10-12) | **Requirements:** 17/17 verified
**Tests:** 53 (8 suites)

### Key Accomplishments

1. **BWF 3×15 scoring** — Parameterized ScoringRules struct, best-of-5, deuce at 14, cap at 17, 9 new tests
2. **Haptic feedback** — HapticFeedbackService (point/game-point/match), Settings toggle, Watch support
3. **Multi-camera Hawk Eye** — Sequential multi-angle via PhotosPicker, ResultFusionService with confidence fusion

### Archive

- [v1.2-ROADMAP.md](milestones/v1.2-ROADMAP.md)
- [v1.2-REQUIREMENTS.md](milestones/v1.2-REQUIREMENTS.md)
- [v1.2-MILESTONE-AUDIT.md](milestones/v1.2-MILESTONE-AUDIT.md)

---

## v1.1 — Hawk Eye Pro + Analytics

**Shipped:** 2026-03-29
**Phases:** 4 (6-9) | **Plans:** 8 | **Requirements:** 20/20 verified
**Timeline:** 2026-03-29

### Key Accomplishments

1. **Match analytics** — Stats dashboard with win rate, streaks, Swift Charts trend/scoring pattern visualizations
2. **Training pipeline** — Python YOLO training script, annotation guide, CoreML export, ShuttleDetecting protocol
3. **240fps video capture** — Delegate-based AVCaptureVideoDataOutput, CircularFrameBuffer, HEVC recording, slow-motion replay
4. **Real AI integration** — CoreMLShuttleDetector with VNCoreMLRequest, frame-skip strategy, detector auto-selection

### Tech Debt

- Dataset collection needed (2,000+ annotated images) before real model training
- On-device 240fps + YOLO thermal profiling untested on hardware
- BWF 3×15 format pending April 2026 vote

### Archive

- [v1.1-ROADMAP.md](milestones/v1.1-ROADMAP.md)
- [v1.1-REQUIREMENTS.md](milestones/v1.1-REQUIREMENTS.md)
- [v1.1-MILESTONE-AUDIT.md](milestones/v1.1-MILESTONE-AUDIT.md)

---

## v1.0 — Badminton Eye MVP

**Shipped:** 2026-03-29
**Phases:** 5 | **Plans:** 16 | **Commits:** 61
**LOC:** 6,812 Swift | **Files:** 55 source files
**Timeline:** 2 days (2026-03-28 → 2026-03-29)
**Tests:** 44 tests, 7 suites, all passing

### Key Accomplishments

1. **BWF-compliant scoring engine** — Pure Swift 6 package with 44 exhaustive tests covering singles, doubles, mixed doubles (2026 rule), deuce, 30-pt cap, service rotation, and undo
2. **Apple Watch companion** — Real-time bidirectional sync via WatchConnectivity, independent offline scoring with SIGKILL-safe UserDefaults persistence, HealthKit workout integration
3. **Match data & player profiles** — Date-grouped history, player profiles with photo picker, head-to-head records, court-themed scorecard sharing, CSV/PDF export
4. **Cloud sync & authentication** — Apple Sign-In, CloudKit cross-device sync, local-only mode, Live Activity on lock screen and Dynamic Island
5. **Hawk Eye AI challenge system** — Court calibration (4-corner tap), video capture, placeholder Core ML shuttle detection, animated trajectory replay with confidence indicator, StoreKit 2 premium subscription

### Tech Debt

- Placeholder Core ML model (needs real YOLO26 training)
- 30fps only (240fps deferred to v2)
- WatchConnectivity reliability untested on real hardware
- BWF 3x15 format pending April 2026 vote

### Archive

- [v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md)
- [v1.0-REQUIREMENTS.md](milestones/v1.0-REQUIREMENTS.md)
- [v1.0-MILESTONE-AUDIT.md](milestones/v1.0-MILESTONE-AUDIT.md)
