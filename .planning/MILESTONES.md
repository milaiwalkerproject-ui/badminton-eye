# Milestones

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
