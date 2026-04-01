# Milestones

## v1.14 — Analytics Localization & Accessibility

**Shipped:** 2026-03-31
**Phases:** 2 (35-36) | **Requirements:** 6/6 verified
**Tests:** 95 (unchanged — UI-only changes)

### Key Accomplishments

1. **Stats format keys wired** — `stats.winRateFormat` and `stats.streakFormat` now used in StatsView; the two keys that had been translated in all 9 languages since v1.0 but never consumed are now live
2. **StatsView empty state localized** — New `stats.playMore` and `stats.matchesOf` keys (all 9 languages) replace the last hardcoded English strings in StatsView
3. **StatsView VoiceOver** — Summary card wrapped in `accessibilityElement(children: .combine)` with a composed label covering wins, losses, win rate, and win streak
4. **WinRateTrendChart accessibility** — Chart area has `accessibilityLabel` describing the selected range and current win rate in the active language
5. **ScoringPatternsChart accessibility** — Chart area has `accessibilityLabel` listing average points scored and conceded per game

---

## v1.13 — Complete Format String Localizations

**Shipped:** 2026-03-31
**Phases:** 2 (33-34) | **Requirements:** 6/6 verified
**Tests:** 95 (unchanged — UI-only changes)

### Key Accomplishments

1. **Format string keys in all 9 languages** — Added `game.number`, `headtohead.matchesVs`, `player.deleteMessage`, `chart.last10/20/50` to en/ja/zh-Hans/ko/id/ms/hi/th/da with correct native translations
2. **MatchDetailView game rows** — Decoded scorecard "Game N" rows and fallback "Game 1/2/3" rows use `String(format: localized("game.number"), N)` — switching to Japanese shows "第1ゲーム" etc.
3. **HeadToHeadView opponent filter** — "Matches vs [name]" section header uses `String(format: localized("headtohead.matchesVs"), name)` instead of hardcoded English
4. **PlayerProfileView alert message** — Delete confirmation body uses `String(format: localized("player.deleteMessage"), name)` across all 9 languages
5. **WinRateTrendChart range picker** — TrendRange rawValues changed to stable identifiers; Picker labels resolved via `localizationKey` property at render time — switching to Chinese shows "最近10场/20场/50场"

---

---

## v1.12 — Localize HeadToHeadView, PlayerProfileView, MatchDetailView & Analytics Charts

**Shipped:** 2026-03-31
**Phases:** 1 (31-32) | **Requirements:** 7/7 verified
**Tests:** 95 (unchanged — UI-only changes)

### Key Accomplishments

1. **HeadToHeadView localization** — Navigation title, Opponents section, All Matches section, and empty-state text use `LocalizationManager`; existing `stats.wins`/`stats.losses` reused for W/L labels
2. **PlayerProfileView localization** — Section headers (Name, Photo), text field placeholder, toolbar Cancel/Save buttons, navigation title (New/Edit Player), photo actions (Choose/Remove), delete button, and alert title all use localized keys
3. **Analytics chart localization** — WinRateTrendChart card title, empty state, and x-axis label use localized keys; ScoringPatternsChart card title and empty state use localized keys
4. **MatchDetailView localization** — Navigation title, Share Scorecard / Export menu actions, Games summary row, and format badge (Singles/Doubles/Mixed via existing setup.* keys) all use localized keys
5. **21 new keys in all 9 languages** — `headtohead.*`, `player.*`, `common.cancel/save`, `chart.*`, `match.details/shareScorecard/export` added to en/ja/zh-Hans/ko/id/ms/hi/th/da with correct native translations

---

## v1.11 — Wire SettingsView, MatchSetupView & PlayerListView Localization

**Shipped:** 2026-03-31
**Phases:** 2 (29-30) | **Requirements:** 8/8 verified
**Tests:** 95 (unchanged — UI-only changes)

### Key Accomplishments

1. **SettingsView localization** — Premium, iCloud, haptic, and about sections now use `LocalizationManager` for all user-visible strings; language switcher reflects in every SettingsView label
2. **MatchSetupView localization** — Match format, scoring system, team section headers, Start Match button, and navigation title use localized keys; all 9 languages supported
3. **PlayerListView localization** — Navigation title, search prompt, swipe-action Edit button, and empty-state text use localized keys; 4 new keys (`players.search`, `players.edit`, `players.noPlayers`, `players.addFirst`) added to all 9 Localizable.strings files with correct native translations

---

---

## v1.10 — Localize Remaining Views

**Shipped:** 2026-03-31
**Phases:** 2 (27-28) | **Requirements:** 6/6 verified
**Tests:** 95 (unchanged — UI-only changes)

### Key Accomplishments

1. **Localization wire-up** — MatchHistoryView, StatsView, and LiveMatchView now call `LocalizationManager.shared` for `history.title`, `history.noMatches`, `stats.title`, `stats.wins`, `stats.losses`, and `match.game` — language switcher in Settings now reflects in these views
2. **New keys in all 9 languages** — `game.over`, `game.continue`, `match.new`, and `match.games` added to en/ja/zh-Hans/ko/id/ms/hi/th/da Localizable.strings with correct native translations
3. **Game/match-end localization** — GameEndOverlay and MatchEndView use localized strings for their key user-facing text (game number header, undo/continue buttons, new-match CTA, games tally row)

### Archive

- [v1.10-REQUIREMENTS.md](.planning/REQUIREMENTS.md)

---

## v1.9 — 3×15 Undo & Mixed Doubles Boundary Tests

**Shipped:** 2026-03-30
**Phases:** 2 (25-26) | **Requirements:** 5/5 verified
**Tests:** 95 (9 suites, +5 from v1.8)

### Key Accomplishments

1. **3×15 deuce undo** — Undo at 15-14 in 3×15 reverts to 14-14 with isDeuce preserved
2. **3×15 mid-switch undo** — Undo of the 8th-point trigger in 5th game clears hasSwitchedInThirdGame and shouldSwitchSidesFlag
3. **3×15 cross-game undo** — Undo of first point of game 3 restores server, score, and 2-game completed list
4. **Mixed doubles boundary undo** — Undo of first point of game 2 restores pre-game-end state (server, rotation, scores, game 1 still complete)
5. **Mixed doubles game-3 mid-switch** — shouldSwitchSidesFlag fires at 11 total points in mixed doubles game 3 (same threshold as standard doubles)

### Archive

- [v1.9-REQUIREMENTS.md](.planning/REQUIREMENTS.md)

---

## v1.8 — Doubles & Mixed Deuce/Cap Coverage

**Shipped:** 2026-03-30
**Phases:** 2 (23-24) | **Requirements:** 6/6 verified
**Tests:** 90 (9 suites, +6 from v1.7)

### Key Accomplishments

1. **Doubles deuce/cap tests** — Three tests verifying deuce at 20-20, 21-20 not a win, and cap at 30-29 in doubles context
2. **Doubles mid-game switch** — Test verifying shouldSwitchSidesFlag triggers at 11 points in doubles game 3
3. **Doubles undo during deuce** — Test verifying undo at 21-20 in doubles reverts to 20-20 with correct server restored
4. **Mixed doubles game-3 service** — Test documenting loser of game 2 serves first in game 3 for mixed doubles

### Archive

- [v1.8-REQUIREMENTS.md](.planning/REQUIREMENTS.md)

---

## v1.7 — 3×15 Service Continuity & Doubles Game-3 Tests

**Shipped:** 2026-03-30
**Phases:** 2 (21-22) | **Requirements:** 4/4 verified
**Tests:** 84 (9 suites, +4 from v1.6)

### Key Accomplishments

1. **3×15 cross-game service** — Two tests verifying loser serves in game 2 and game 3 under 3×15 format (same resetServiceForNewGame code path, now explicitly covered)
2. **Doubles game-3 service** — Test documenting that loser of game 2 in doubles serves first in game 3 with correct doublesRotation reset
3. **Doubles boundary undo** — Test verifying that undoing the first point of game 2 fully restores the cross-game-boundary state (server, rotation, score, completed-game list)

### Archive

- [v1.7-REQUIREMENTS.md](.planning/REQUIREMENTS.md)

---

## v1.6 — Undo Edge Cases & Cross-Game Service Tests

**Shipped:** 2026-03-30
**Phases:** 2 (19-20) | **Requirements:** 5/5 verified
**Tests:** 80 (9 suites, +5 from v1.5)

### Key Accomplishments

1. **Undo edge cases** — Three tests covering match-winning point undo, deuce-state undo, and mid-game switch flag clearing on undo
2. **Cross-game service continuity** — Two tests documenting that the loser of each game serves first in the next game (phases 2 and 3)

### Archive

- [v1.6-REQUIREMENTS.md](.planning/REQUIREMENTS.md)

---

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
