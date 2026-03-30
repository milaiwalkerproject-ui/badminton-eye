# Feature Landscape: v1.2

**Domain:** Haptic feedback, BWF 3x15 scoring format, multi-camera Hawk Eye
**Researched:** 2026-03-29
**Scope:** New features only (haptic scoring feedback, BWF 3x15, multi-camera angles)

## Feature Area 1: Haptic Feedback During Scoring

### Table Stakes

| Feature | Why Expected | Complexity | Dependency |
|---------|--------------|------------|------------|
| Haptic pulse on score change (iPhone) | Every fitness/sports app with score tracking uses UIFeedbackGenerator; users notice its absence | Low | `LiveMatchViewModel.scorePoint()` — fire haptic after `MatchEngine.apply()` |
| Haptic pulse on score change (Watch) | WatchOS haptics are the primary feedback mechanism on a 45mm screen; critical for glanceable scoring | Low | `WatchMatchViewModel` — use `WKInterfaceDevice.play(.click)` |
| User toggle to enable/disable haptics | Some users find vibrations distracting during play; accessibility concern for sensory-sensitive users | Low | New `@AppStorage("hapticFeedbackEnabled")` bool, expose in `SettingsView` |
| Distinct haptic for game point vs regular point | Users need to know when the game is on the line without looking at the screen | Low | Conditional on `isDeuce` or score >= 20 — use `.notification(.warning)` vs `.impact(.medium)` |

### Differentiators

| Feature | Value Proposition | Complexity | Dependency |
|---------|-------------------|------------|------------|
| Match-end celebration haptic | Dramatic haptic burst on match completion; emotionally satisfying | Low | `UINotificationFeedbackGenerator.notificationOccurred(.success)` on `matchPhase == .complete` |
| Serving-side haptic cue | Short double-tap when serve switches to your side (configurable per player/side) | Medium | Requires knowing which "side" the user is on — new setting or prompt at match start |
| Watch-specific haptic differentiation | Use WatchOS-exclusive haptic types (`.directionUp` for score gain, `.directionDown` for opponent score) | Low | `WKInterfaceDevice` haptic types; watchOS 10+ supports these |
| Custom Core Haptics pattern for game win | Richer haptic using `CHHapticEngine` with custom intensity curve for game-end moments | Medium | Core Haptics framework; only on iPhone (not watchOS) |

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Continuous haptic during rallies | Battery drain, sensory overload, pointless | Only fire on discrete score events |
| Haptics on undo | Confusing — undo is a correction, not an event | Silent undo, or very subtle `.impact(.light)` at most |
| Haptic customization per-event type (full UI) | Over-engineering for v1.2; very few users would use granular controls | Ship with sensible defaults; toggle is on/off only |
| Audio feedback alongside haptics | Disruptive to players during matches; phones should be silent court-side | Haptic-only; audio is explicitly out of scope |

### Complexity Assessment

**Overall: LOW.** This is the simplest of the three features.

- iPhone: `UIImpactFeedbackGenerator` and `UINotificationFeedbackGenerator` — 2-3 lines of code per event type.
- Watch: `WKInterfaceDevice.current().play(_:)` — single line per event.
- The main work is deciding WHICH haptic for WHICH event, not the implementation.
- Core Haptics (custom patterns) adds ~50 lines but is optional for v1.2.
- Toggle: one `@AppStorage` property + one `Toggle` in `SettingsView`.

**Key dependency:** `LiveMatchViewModel.scorePoint()` is the single integration point on iPhone. `WatchMatchViewModel` is the Watch integration point. Both are already the sole places where score mutations happen, so adding haptics is a localized change.

---

## Feature Area 2: BWF 3x15 Scoring Format

### Exact Rules (BWF 3x15 Format)

Based on BWF's proposed alternative scoring system (trialed in various events since 2024):

- **Best of 5 games** (first to win 3 games wins the match)
- **Each game to 15 points** (not 21)
- **No deuce**: First to 15 wins the game outright (no 2-point lead required, no cap at 17)
- **Rally scoring**: Same as current BWF — every rally produces a point regardless of who served
- **Service rules**: Same rotation/court rules as standard BWF (server determined by who won previous rally)
- **Side switching**: Switch sides after each game; no mid-game switch (unlike 3x21 where you switch at 11 in the third game)
- **Interval**: 60-second interval between games (same as standard)

**Confidence: MEDIUM.** The exact rules have been discussed in BWF council meetings and trialed at events. The PROJECT.md notes "3x15 format may need adding after April 2026 vote," confirming BWF is actively considering adoption. The core rules (best-of-5, first-to-15, no deuce) are consistent across multiple reports. Side-switching details may vary — flag for verification when BWF publishes final rules.

### Table Stakes

| Feature | Why Expected | Complexity | Dependency |
|---------|--------------|------------|------------|
| Format selection at match setup | Users must choose 3x21 or 3x15 before starting; cannot change mid-match | Medium | `MatchSetupView` — add scoring format picker; `MatchState` needs a `ScoringFormat` enum |
| Correct 3x15 scoring logic | First to 15 wins game, best of 5, no deuce | Medium | `BWFRules.swift` — all computed properties (`isGameWon`, `isDeuce`, `isMatchComplete`, etc.) must branch on format |
| Score display adapts to format | Game count display must show up to 5 games; score targets reflect 15 not 21 | Low | `ScorePanel`, `WatchScoreDisplay`, `LiveActivity` — conditional on format |
| Match history records format | Persisted matches must record which format was used; history view shows it | Low | New field on `PersistedMatch`; `MatchHistoryView` displays it |
| Watch sync includes format | Watch must know the scoring format to display correctly | Low | `SyncPayload` already carries full state; just ensure `ScoringFormat` is in `MatchState` |

### Differentiators

| Feature | Value Proposition | Complexity | Dependency |
|---------|-------------------|------------|------------|
| Format comparison in stats | Show player stats filtered by format (some players may perform differently in 3x15 vs 3x21) | Medium | `MatchStatsViewModel` — filter by `scoringFormat` field |
| Auto-detect tournament format | If user plays in a tournament context, suggest the likely format | Low | Simple prompt/default, not actual detection |
| Live Activity adapts game count display | Dynamic Island shows "G3/5" for 3x15 vs "G2/3" for 3x21 | Low | `MatchActivityAttributes.ContentState` — add `totalGames` field |

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Mid-match format switching | Nonsensical — you cannot change rules during a match | Lock format selection once match starts |
| Custom point targets (e.g., "play to 11") | Scope creep; 3x21 and 3x15 are the only BWF-recognized formats | Support exactly two formats; add more only if BWF adopts them |
| 5x11 format (another BWF experiment) | Was trialed and rejected by BWF; unlikely to be adopted | Do not implement unless BWF resurrects it |
| Hybrid format (mix of 3x21 and 3x15 games) | Not a real thing; confuses users | Enforce one format per match |

### Complexity Assessment

**Overall: MEDIUM.** This is the most architecturally impactful feature because it touches the ScoringEngine package.

**ScoringEngine changes required:**

1. **New `ScoringFormat` enum** in `Types.swift`: `.standard21` and `.threeByFifteen`
2. **`MatchState` gains `scoringFormat` property** — must be Codable/Sendable
3. **`BWFRules.swift` rewrite** — every computed property must branch:
   - `isDeuce`: always `false` for 3x15
   - `isAtCap`: N/A for 3x15
   - `isGameWon`: `maxScore >= 15` (no lead requirement) for 3x15 vs existing logic for 3x21
   - `isMatchComplete`: `gamesWon >= 3` for 3x15 vs `>= 2` for 3x21
   - `shouldSwitchSides`: No mid-game switch for 3x15; only between games
4. **`MatchEngine.swift`** — new game initialization must account for best-of-5 game numbering
5. **Factory methods** on `MatchState` — new `.newSinglesMatch3x15(...)` or parameterize existing factories with `scoringFormat`
6. **`PersistedMatch`** gains `scoringFormat` field — SwiftData schema migration
7. **`CodableMatchState`** must encode/decode `scoringFormat`
8. **`MatchSetupView`** gains format picker UI
9. **Up to 5 game score fields** on `PersistedMatch` (currently only `game1Score`, `game2Score`, `game3Score` — need `game4Score`, `game5Score`)
10. **All tests** in ScoringEngineTests need 3x15 variants

**Key risk:** The ScoringEngine is a separate Swift Package. Changes here propagate to both iOS and watchOS targets. The pure-struct state machine design makes this safe to refactor (no side effects), but the test surface area doubles.

**Migration note:** Existing persisted matches with `nil` scoring format should default to `.standard21`.

---

## Feature Area 3: Multi-Camera Hawk Eye

### How Sports Analysis Apps Handle Multi-Camera

Professional sports analysis (Hawk-Eye Innovations, VAR in football, tennis line-calling) uses 8-12+ synchronized cameras. Consumer apps cannot replicate this, but there are practical approaches:

1. **Sequential capture from different angles** — user records one challenge from multiple phone positions (impractical during live play)
2. **Multi-device capture** — two iPhones recording simultaneously, synced post-hoc via audio timestamps or NTP
3. **AVCaptureMultiCamSession (iOS 13+)** — uses front + back cameras on a single device simultaneously (limited utility for court-side recording)
4. **Peer-to-peer sync** — MultipeerConnectivity or local network to coordinate recording start/stop across devices

For a badminton app where the phone is on a tripod court-side, the realistic approach is **multi-device with post-hoc synchronization** — two phones at different court angles, with one being the "primary" device running the app and the other being a "secondary" camera.

### Table Stakes

| Feature | Why Expected | Complexity | Dependency |
|---------|--------------|------------|------------|
| Support analyzing video from a second camera angle | Core value proposition — higher confidence from multiple perspectives | High | New `MultiCameraManager` service; extends `HawkEyePipeline` |
| Independent calibration per camera | Each camera position has different court perspective; reusing one calibration is wrong | Medium | `CalibrationProfile` needs camera identifier; `CourtCalibrationView` supports multiple profiles |
| Combined confidence score | Merge detections from multiple angles into single higher-confidence result | High | `TrajectoryCalculator` — triangulation or weighted average of landing points |
| Clear UX for "add second angle" | Users must understand how to set up a second camera without confusion | Medium | New onboarding/setup flow in Hawk Eye challenge UI |

### Differentiators

| Feature | Value Proposition | Complexity | Dependency |
|---------|-------------------|------------|------------|
| Temporal synchronization via audio correlation | Automatic alignment of two video feeds without manual sync | High | Cross-correlate audio waveforms from both videos to find time offset |
| Side-by-side replay from both angles | Show both camera views simultaneously during Hawk Eye replay | Medium | New split-view in `TrajectoryReplayView` |
| Confidence improvement visualization | Show user how much the second angle improved confidence (e.g., "72% -> 94%") | Low | Compare single-camera vs multi-camera confidence scores |
| AirDrop/local transfer of second video | Quick way to get video from second iPhone to primary device | Medium | Uses iOS sharing infrastructure; avoids needing custom networking |

### Anti-Features

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Real-time multi-device streaming | Massive complexity; network latency; thermal issues; overkill for challenge-based flow | Record independently, combine during analysis |
| AVCaptureMultiCamSession (front+back) | Front camera faces user, not the court; useless for shuttle tracking | Use separate devices at different court positions |
| More than 2 cameras | Diminishing returns; consumer use case does not justify 3+ device orchestration | Support exactly 2 angles; primary + secondary |
| Automatic camera discovery/pairing | MultipeerConnectivity is unreliable; Bluetooth pairing UX is poor | Manual video import (camera roll, AirDrop, Files) |
| Cloud-based video merge | Adds latency, server costs, breaks offline-first promise | All processing on-device |

### Complexity Assessment

**Overall: HIGH.** This is the most complex feature in v1.2 by a significant margin.

**Architecture changes required:**

1. **Video import flow** — secondary video comes from camera roll or AirDrop, not live capture. New `VideoImportView` using `PhotosPicker` or `UIDocumentPickerViewController`.
2. **Per-camera calibration storage** — `CalibrationProfile` needs a `cameraID` or `angle` identifier. Multiple profiles stored in SwiftData.
3. **Temporal alignment** — the two videos are not synchronized by default. Options:
   - **Audio cross-correlation** (best): Extract audio tracks, compute cross-correlation to find time offset. Uses `AVAudioPCMBuffer` and `vDSP`. HIGH complexity but robust.
   - **Manual sync point** (simpler): User marks a common event (e.g., shuttle impact sound) in both videos. MEDIUM complexity.
   - **Timestamp-based** (fragile): Rely on file creation timestamps. LOW complexity but unreliable (different devices, different clocks).
   - **Recommendation: Manual sync with audio cross-correlation as v1.3 upgrade.**
4. **Dual-pipeline analysis** — run `HawkEyePipeline.analyze()` on both videos independently, then merge results. The existing pipeline already returns `HawkEyeResult` with trajectory points and landing point.
5. **Result fusion** — Two landing points from two angles. Approaches:
   - **Weighted average** by confidence: simple, decent accuracy
   - **Geometric triangulation**: If calibrations map to real court coordinates, two independent landing estimates can be averaged in court-space. More accurate.
   - **Recommendation: Weighted average for v1.2, triangulation for v1.3.**
6. **UI changes** — `ChallengeVideoView` needs "Add Second Angle" button. `TrajectoryReplayView` needs optional split view.

**Key dependency:** `HawkEyePipeline` currently takes a single `videoURL` and `CalibrationProfile`. It needs to either:
- (a) Accept an array of `(videoURL, CalibrationProfile)` pairs and fuse internally, or
- (b) Be called twice independently, with a new `ResultFusionService` combining the two `HawkEyeResult` outputs.

Option (b) is cleaner — keeps the pipeline single-responsibility, adds fusion as a separate concern.

**Device requirements:** Second video must be importable. No requirement for a second device to have the app installed — any iPhone camera recording at reasonable quality works.

---

## Feature Dependencies (v1.2)

```
Haptic Feedback:
  @AppStorage toggle --> SettingsView UI
  LiveMatchViewModel.scorePoint() --> iPhone haptic trigger
  WatchMatchViewModel score handler --> Watch haptic trigger
  BWFRules (isDeuce, isGameWon, isMatchComplete) --> Haptic type selection

BWF 3x15:
  New ScoringFormat enum --> MatchState.scoringFormat property
  MatchState.scoringFormat --> BWFRules computed properties (branching logic)
  BWFRules changes --> MatchEngine (game transitions, best-of-5)
  ScoringFormat --> MatchSetupView (format picker)
  ScoringFormat --> CodableMatchState (encode/decode)
  ScoringFormat --> PersistedMatch (new field + game4/game5 scores)
  PersistedMatch schema change --> SwiftData migration
  ScoringFormat --> SyncPayload/WatchSync (format-aware display)
  ScoringFormat --> LiveActivity (game count display)
  All ScoringEngine changes --> New test suite for 3x15

Multi-Camera:
  Video import UI --> PhotosPicker / document picker
  Per-camera CalibrationProfile --> SwiftData (cameraID field)
  CourtCalibrationView --> Support multiple calibration profiles
  Temporal alignment service --> Audio cross-correlation or manual sync
  HawkEyePipeline (called twice) --> Two independent HawkEyeResult outputs
  New ResultFusionService --> Combines two results (weighted average)
  ChallengeVideoView --> "Add Second Angle" UI
  TrajectoryReplayView --> Optional split-view replay
```

**Cross-feature dependency:** BWF 3x15 changes to `MatchState` and `BWFRules` should land BEFORE haptic feedback integration, because haptic type selection depends on `isDeuce` / `isGameWon` — which behave differently in 3x15. If haptics ship first, it must account for the upcoming format branching.

## Implementation Priority

**Recommended order:**

1. **BWF 3x15 scoring** (FIRST) — Deepest architectural impact; touches ScoringEngine, the foundation everything else depends on. Changes here affect haptic logic and test surface. Ship this first to stabilize the engine.

2. **Haptic feedback** (SECOND) — Low complexity, but depends on stable scoring rules to know when to fire game-point vs regular haptics. After 3x15 lands, haptic integration is straightforward.

3. **Multi-camera Hawk Eye** (THIRD) — Highest complexity, most independent from the other two. Can be developed in parallel but should ship last because it needs the most testing and UX iteration.

## MVP Recommendation

**Must ship in v1.2:**
1. BWF 3x15 scoring with format picker at match setup
2. Haptic feedback toggle with 3 haptic types (regular point, game point, match end)
3. Multi-camera support with manual video import and weighted-average result fusion

**Defer to v1.3:**
- Audio cross-correlation for automatic temporal sync (ship manual sync point first)
- Geometric triangulation for result fusion (weighted average is sufficient)
- Core Haptics custom patterns (standard UIFeedbackGenerator is fine)
- Format comparison stats (filter stats by scoring format)
- Serving-side haptic cue (requires knowing which side the user is on)

## Sources

- Existing codebase analysis: `ScoringEngine/`, `VideoCaptureManager`, `HawkEyePipeline` (HIGH confidence)
- PROJECT.md requirements and constraints (HIGH confidence)
- BWF 3x15 scoring rules from training data on BWF council proposals and trial events (MEDIUM confidence — exact rules should be verified against BWF official publication after April 2026 vote)
- Apple haptics API knowledge: `UIFeedbackGenerator`, `WKInterfaceDevice`, Core Haptics framework (HIGH confidence)
- AVFoundation multi-camera and video processing APIs (HIGH confidence)
- Sports analysis multi-camera approaches from training data (MEDIUM confidence)
