# Requirements: Badminton Eye v1.2 — Haptic Scoring, BWF 3×15 & Multi-Camera

**Defined:** 2026-03-29
**Core Value:** Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time.

## v1.2 Requirements

### BWF 3×15 Scoring Format

- [ ] **FMT-01**: User can choose between standard 21-point and BWF 3×15 scoring format when setting up a new match
- [ ] **FMT-02**: In 3×15 mode, games are played to 15 points with deuce at 14 and a cap score
- [ ] **FMT-03**: In 3×15 mode, best-of-5 games determines the match winner
- [ ] **FMT-04**: ScoringEngine uses parameterized ScoringRules struct (not hardcoded thresholds) so both formats share the same logic paths
- [ ] **FMT-05**: Existing matches (v1.0/v1.1) decode correctly with default standard-21 format — no data migration required
- [ ] **FMT-06**: Match history and stats views display the scoring format used for each match
- [ ] **FMT-07**: Apple Watch sync correctly transmits and displays the chosen scoring format

### Haptic Feedback

- [ ] **HAP-01**: User can toggle haptic feedback on/off in Settings (default: on)
- [ ] **HAP-02**: On iPhone, a haptic pulse fires on each point scored (UIImpactFeedbackGenerator)
- [ ] **HAP-03**: On iPhone, a distinct haptic fires on game point and match point (UINotificationFeedbackGenerator)
- [ ] **HAP-04**: On Apple Watch, haptic feedback fires on score changes using WKInterfaceDevice haptic types
- [ ] **HAP-05**: Haptic toggle preference syncs between iPhone and Watch

### Multi-Camera Hawk Eye

- [ ] **CAM-01**: User can import a second video angle for a Hawk Eye challenge (sequential multi-angle analysis)
- [ ] **CAM-02**: Each video angle is analyzed independently through the existing HawkEyePipeline
- [ ] **CAM-03**: Results from multiple angles are fused into a single higher-confidence landing prediction
- [ ] **CAM-04**: Confidence score reflects the benefit of multiple angles (higher than single-angle)
- [ ] **CAM-05**: Single-angle Hawk Eye continues to work unchanged when no second angle is provided

## Future Requirements

### Multi-Camera Enhancements (v1.3+)

- **CAM-F1**: Simultaneous live multi-camera capture via AVCaptureMultiCamSession
- **CAM-F2**: Audio cross-correlation for automatic temporal alignment between angles
- **CAM-F3**: On-screen multi-angle split view during replay

### Scoring Enhancements (v1.3+)

- **FMT-F1**: Custom scoring formats (user-defined points per game, number of games)
- **FMT-F2**: Tournament mode with bracket management

## Out of Scope

| Feature | Reason |
|---------|--------|
| Voice score announcements | User requested haptic only — no TTS/speech synthesis |
| CoreHaptics custom patterns | Conflicts with AVFoundation audio sessions during Hawk Eye; UIFeedbackGenerator sufficient |
| Simultaneous multi-cam capture | Requires AVCaptureMultiCamSession (Pro devices only), FPS limits — defer to v1.3 |
| Real-time multi-camera streaming | Network sync complexity, thermal constraints — sequential import is MVP |
| Per-rally event model | Requires SwiftData migration beyond scoring format — defer to v2+ |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| FMT-01 | Phase 10 | Pending |
| FMT-02 | Phase 10 | Pending |
| FMT-03 | Phase 10 | Pending |
| FMT-04 | Phase 10 | Pending |
| FMT-05 | Phase 10 | Pending |
| FMT-06 | Phase 10 | Pending |
| FMT-07 | Phase 10 | Pending |
| HAP-01 | Phase 11 | Pending |
| HAP-02 | Phase 11 | Pending |
| HAP-03 | Phase 11 | Pending |
| HAP-04 | Phase 11 | Pending |
| HAP-05 | Phase 11 | Pending |
| CAM-01 | Phase 12 | Pending |
| CAM-02 | Phase 12 | Pending |
| CAM-03 | Phase 12 | Pending |
| CAM-04 | Phase 12 | Pending |
| CAM-05 | Phase 12 | Pending |

**Coverage:**
- v1.2 requirements: 17 total
- Mapped to phases: 17
- Unmapped: 0

---
*Requirements defined: 2026-03-29*
