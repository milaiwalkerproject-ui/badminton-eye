# Requirements: Badminton Eye v1.5 — Watch Haptic Reliability

**Defined:** 2026-03-30
**Core Value:** Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time.

## v1.5 Requirements

### Watch Haptic Reliability

- [x] **HAP-W01**: WatchMatchViewModel is annotated @MainActor so all state mutations are main-actor-isolated
- [x] **HAP-W02**: When the iPhone scores a point and sends state to the Watch, the Watch plays a click haptic for a regular point
- [x] **HAP-W03**: When the iPhone scores a game-ending point, the Watch plays a success haptic
- [x] **HAP-W04**: When the iPhone ends the match, the Watch plays a notification haptic
- [x] **HAP-W05**: When the Watch user scores locally (online or offline), the Watch plays only one haptic (no double-haptic when iPhone echoes state back)
- [x] **HAP-W06**: Haptics respect the user's haptic toggle (AppStorage "hapticFeedbackEnabled")

## Out of Scope

| Feature | Reason |
|---------|--------|
| Unit tests for WatchMatchViewModel haptics | Requires WatchKit, cannot run in SPM test target |
| Custom haptic patterns | Standard WKHapticType set is sufficient |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| HAP-W01 | Phase 18 | Complete |
| HAP-W02 | Phase 18 | Complete |
| HAP-W03 | Phase 18 | Complete |
| HAP-W04 | Phase 18 | Complete |
| HAP-W05 | Phase 18 | Complete |
| HAP-W06 | Phase 18 | Complete |

**Coverage:**
- v1.5 requirements: 6 total
- Mapped to phases: 6
- Unmapped: 0

---
*Requirements defined: 2026-03-30*
