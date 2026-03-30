# Requirements: Badminton Eye v1.3 — Live Multi-Cam, Auto-Sync & Custom Scoring

**Defined:** 2026-03-29
**Core Value:** Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time.

## v1.3 Requirements

### Custom Scoring Formats

- [ ] **CUST-01**: User can select "Custom" in the scoring system picker on match setup and define points-to-win, deuce threshold, cap score, and number of games
- [ ] **CUST-02**: Custom scoring rules are validated (points > 0, deuce < points, cap > deuce, games is odd 1-5)
- [ ] **CUST-03**: ScoringRules conforms to Codable so custom configurations survive crash recovery, Watch sync, and CloudKit
- [ ] **CUST-04**: Custom format matches display correctly in match history and stats views
- [ ] **CUST-05**: Devices running v1.2 that receive a "custom" scoring system via CloudKit fall back to standard-21 without crashing

### Simultaneous Dual-Camera Capture

- [ ] **DCAM-01**: On supported devices (A12+), user can enable dual-camera mode in Hawk Eye settings
- [ ] **DCAM-02**: Dual-camera uses AVCaptureMultiCamSession with asymmetric FPS (primary 120fps + secondary 60fps)
- [ ] **DCAM-03**: Each camera writes to its own CircularFrameBuffer with synchronized timestamps
- [ ] **DCAM-04**: On unsupported devices or at thermal throttle, app falls back to single-camera with user notification
- [ ] **DCAM-05**: Existing single-camera 240fps mode remains available and unchanged as the default

### Audio Cross-Correlation Sync

- [ ] **SYNC-01**: When two separately-recorded videos are imported, audio tracks are cross-correlated to find temporal offset
- [ ] **SYNC-02**: Cross-correlation uses Accelerate/vDSP for hardware-accelerated computation
- [ ] **SYNC-03**: Computed offset is applied as PTS adjustment before frame analysis, keeping HawkEyePipeline unchanged
- [ ] **SYNC-04**: If audio correlation confidence is below threshold, user is prompted to set manual sync point

## Future Requirements

### Advanced Multi-Camera (v2+)

- **DCAM-F1**: Multi-device camera orchestration (two iPhones)
- **DCAM-F2**: Real-time frame-level sync between devices via local network
- **DCAM-F3**: Split-view replay showing both angles simultaneously

## Out of Scope

| Feature | Reason |
|---------|--------|
| Multi-device networking | Too complex for v1.3; single-device multi-cam sufficient |
| 240fps in multi-cam mode | Hardware limitation — multi-cam caps at ~120fps per camera |
| Voice score announcements | User requested haptic only in v1.2 |
| Custom format sharing between users | Social features deferred to v2+ |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CUST-01 | Phase 13 | Pending |
| CUST-02 | Phase 13 | Pending |
| CUST-03 | Phase 13 | Pending |
| CUST-04 | Phase 13 | Pending |
| CUST-05 | Phase 13 | Pending |
| DCAM-01 | Phase 14 | Pending |
| DCAM-02 | Phase 14 | Pending |
| DCAM-03 | Phase 14 | Pending |
| DCAM-04 | Phase 14 | Pending |
| DCAM-05 | Phase 14 | Pending |
| SYNC-01 | Phase 15 | Pending |
| SYNC-02 | Phase 15 | Pending |
| SYNC-03 | Phase 15 | Pending |
| SYNC-04 | Phase 15 | Pending |

**Coverage:**
- v1.3 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0

---
*Requirements defined: 2026-03-29*
