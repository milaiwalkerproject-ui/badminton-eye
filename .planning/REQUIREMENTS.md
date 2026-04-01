# Requirements: Badminton Eye v1.13 — Complete Format String Localizations

**Defined:** 2026-03-31
**Core Value:** Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time.

## v1.13 Requirements

### Format String Keys

- [x] **FMT-01**: All 9 Localizable.strings files contain `game.number`, `headtohead.matchesVs`, `player.deleteMessage`, `chart.last10`, `chart.last20`, `chart.last50` with correct native translations

### MatchDetailView

- [x] **FMT-02**: MatchDetailView decoded scorecard "Game N" rows use `String(format: localization.localized("game.number"), index + 1)` — switching to Japanese shows "第1ゲーム", "第2ゲーム" etc.
- [x] **FMT-03**: MatchDetailView fallback scorecard rows ("Game 1", "Game 2", "Game 3") use the same `game.number` format key

### HeadToHeadView

- [x] **FMT-04**: HeadToHeadView "Matches vs [opponent]" section header uses `String(format: localization.localized("headtohead.matchesVs"), selectedOpponent!)` — switching to Danish shows "Kampe mod [name]"

### PlayerProfileView

- [x] **FMT-05**: PlayerProfileView delete alert message uses `String(format: localization.localized("player.deleteMessage"), name)` instead of hardcoded English

### WinRateTrendChart

- [x] **FMT-06**: WinRateTrendChart range picker labels use localized display names via `TrendRange.localizationKey` — switching to Chinese shows "最近10场", "最近20场", "最近50场"

## Out of Scope

| Feature | Reason |
|---------|--------|
| "%.0f%% win rate" format string in HeadToHeadView/StatsView | Percentage format with no meaningful translation; stays as-is |
| "Buffer: %.1fs / 10.0s" in ChallengeVideoView | Technical debug string; not user-facing |
| "Distance from line: %.1fcm" in TrajectoryReplayView | Technical measurement; stays as-is |
| "Custom (%d pts, best of %d)" in format badge | Not yet surfaced in MatchDetailView; deferred |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| FMT-01 | Phase 33 | Done |
| FMT-02 | Phase 33 | Done |
| FMT-03 | Phase 33 | Done |
| FMT-04 | Phase 33 | Done |
| FMT-05 | Phase 34 | Done |
| FMT-06 | Phase 34 | Done |

**Coverage:**
- v1.13 requirements: 6 total
- Mapped to phases: 6
- Unmapped: 0

---
*Requirements defined: 2026-03-31*
