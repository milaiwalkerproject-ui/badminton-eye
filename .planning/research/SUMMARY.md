# Research Summary: v1.2 Haptic Scoring, BWF 3×15 & Multi-Camera

**Synthesized:** 2026-03-29
**Sources:** STACK.md, FEATURES.md, ARCHITECTURE.md, PITFALLS.md

## Stack Additions

- **UIImpactFeedbackGenerator / UINotificationFeedbackGenerator** — iPhone haptics (NOT CoreHaptics, conflicts with AVFoundation audio sessions)
- **WKInterfaceDevice.play()** — Watch haptics already exist, minor enhancements only
- **ScoringRules struct** — Parameterized thresholds replacing hardcoded 21/20/29/30/11 in BWFRules.swift
- **Sequential multi-angle analysis** — Reuse existing HawkEyePipeline twice, fuse results in new ResultFusionService
- **Zero new dependencies** — All Apple-native frameworks

## Feature Table Stakes

| Feature | Complexity | Key Dependency |
|---------|-----------|----------------|
| Haptic on score change (iPhone + Watch) | Low | LiveMatchViewModel / WatchMatchViewModel |
| Haptic toggle in Settings | Low | @AppStorage bool |
| Distinct game-point vs regular haptic | Low | isDeuce / score threshold checks |
| BWF 3×15 format picker in match setup | Medium | New ScoringSystem enum on MatchState |
| 5-game score persistence | Medium | PersistedMatch schema + CloudKit migration |
| Multi-angle video import | High | New MultiAngleAnalysisView + ResultFusionService |

## Critical Pitfalls

1. **Hardcoded magic numbers** — BWFRules.swift has 21/20/29/30/11 scattered. Extract to ScoringRules struct FIRST.
2. **CodableMatchState manual mirror** — Must add scoringSystem field with decodeIfPresent default. Miss = crash recovery loses format.
3. **CloudKit append-only** — New PersistedMatch fields MUST have defaults. Non-optional without default = silent data loss.
4. **Watch haptics threading** — WatchMatchViewModel not @MainActor; haptic calls from WCSession callbacks silently fail on background threads.
5. **Dual-buffer memory** — Two 240fps CircularFrameBuffers = ~8.6GB. Use asymmetric FPS (240 primary + 60 secondary).

## Build Order

1. **Phase 1: BWF 3×15 Scoring** — ScoringEngine refactor (ScoringRules struct), MatchState + persistence, UI picker. Pure/testable, no hardware deps.
2. **Phase 2: Haptic Feedback** — HapticFeedbackService, ViewModel integration, Settings toggle, Watch enhancements. Quick win after scoring stabilizes.
3. **Phase 3: Multi-Camera** — Sequential multi-angle MVP (user imports videos), ResultFusionService, confidence fusion. Highest complexity, device-dependent.

## Open Questions

- BWF 3×15 exact thresholds (deuce at 14? cap at 17?) — depends on April 25 vote
- AVCaptureMultiCamSession FPS limits on latest hardware — needs device testing
- Multi-camera: multiple phones or multiple lenses on one phone?
