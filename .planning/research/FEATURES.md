# Feature Landscape: v1.3 Live Multi-Cam, Audio Sync & Custom Scoring

**Domain:** iOS badminton scoring app with AI video analysis
**Researched:** 2026-03-29

## Table Stakes

Features users expect given the v1.2 sequential multi-angle foundation.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Simultaneous dual-camera recording | v1.2 introduced multi-angle; users expect live capture on Pro devices | High | AVCaptureMultiCamSession, new MultiCamCaptureManager, dual preview UI |
| Automatic video alignment | Manual alignment is poor UX; auto-sync expected | Medium | Audio cross-correlation via vDSP_conv, standalone service |
| Custom scoring format creation | v1.2 added 3x15; casual players expect flexibility | Medium | UI builder + SwiftData persistence |
| Graceful fallback for non-Pro devices | Users without dual cameras must not see broken features | Low | Runtime isMultiCamSupported check, hide dual-cam UI |
| Built-in format presets preserved | Standard 21 and BWF 3x15 must not regress | Low | Non-deletable presets in format picker |
| Per-lens calibration | Wide and ultra-wide have different FOV/distortion | Medium | CalibrationProfile needs cameraType field |
| hardwareCost monitoring | Session refuses to start if >1.0; must pre-check | Medium | Read multiSession.hardwareCost before startRunning() |

## Differentiators

Features that set the app apart from competing badminton apps.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Real-time dual-camera preview | See both camera angles live during recording | Medium | Two preview layers or Metal rendering |
| Confidence boost indicator | Show users that dual-camera increases Hawk Eye accuracy | Low | Display fused vs single-angle confidence |
| Sync quality indicator | Show alignment confidence so users trust auto-sync | Low | Peak-to-sidelobe ratio threshold |
| Saved custom presets | "Tuesday Night Rules", "Junior Training" reusable formats | Medium | CustomScoringFormat SwiftData model with name |
| Format sharing/import | Share custom formats with club members | Low | Export ScoringRules as JSON via share sheet |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Multi-device camera sync (two iPhones) | Multipeer Connectivity adds discovery, pairing, clock sync complexity | Import pre-recorded clips + audio cross-correlation for alignment |
| 240fps in multi-cam mode | Hardware bandwidth makes this impossible. Promising and failing is worse than not offering | Communicate "60fps per camera in dual mode"; single-cam retains 240fps |
| Front + back camera for two court angles | Front camera faces USER, useless for shuttle detection | Use back-side wide + ultra-wide only |
| Arbitrary serve rules editor | Service rotation is the most complex BWF rule; customizing creates edge case explosion | Lock serve rules to BWF standard regardless of scoring format |
| Mid-match rule changes | Changing rules during match corrupts game state and history | Lock scoring parameters once match starts |
| AI-based scoring rule suggestion | No training data, unclear value | Manual presets + custom builder |
| NTP-based clock sync between devices | 10-50ms accuracy, worse than audio correlation's sub-ms accuracy | Audio cross-correlation post-hoc |
| Recording both streams at 1080p | Doubles storage and thermal cost | Primary at 720p, secondary at 720p binned |

## Feature Dependencies

```
Custom Scoring Builder (standalone, no dependencies)

Audio Cross-Correlation Service (standalone, testable with files)
    |
    v
Live Dual-Camera Capture (uses audio sync for fallback import path)
    |
    v
Dual-Camera Hawk Eye Analysis (uses dual-cam capture + existing ResultFusionService)
```

## MVP Recommendation

Prioritize:
1. Custom scoring format builder -- all users benefit, lowest risk, self-contained
2. Audio cross-correlation service -- enables alignment for both dual-cam and imported clips
3. Dual-camera live capture -- Pro device users, highest value but highest risk

Defer:
- Saved custom presets: Add after validating builder UX
- Audio waveform visualization: Auto-alignment should "just work"
- Side-by-side dual-angle replay: Polish feature for v1.4
- Geometric triangulation (upgrade from weighted average fusion): v1.4+
- Format sharing/import: Wait for user demand

## Sources

- Existing codebase analysis (VideoCaptureManager, ResultFusionService, ScoringRules, MatchSetupView)
- iOS SDK headers for AVCaptureMultiCamSession constraints (read directly)
- PROJECT.md requirements and out-of-scope list
