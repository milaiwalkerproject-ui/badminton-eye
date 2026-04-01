# Requirements: Badminton Eye v1.14 — Analytics Localization & Accessibility

**Defined:** 2026-03-31
**Core Value:** Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time.

## v1.14 Requirements

### Stats Localization

- [ ] **STAT-01**: StatsView win rate label uses `String(format: localization.localized("stats.winRateFormat"), viewModel.winRate)` — switching to Japanese shows "勝率 X%"
- [ ] **STAT-02**: StatsView streak badge uses `String(format: localization.localized("stats.streakFormat"), viewModel.currentWinStreak)` — switching to Chinese shows "连胜 N 场"
- [ ] **STAT-03**: StatsView empty state is fully localized: `chart.notEnoughData` key for label, new `stats.playMore` key for description, new `stats.matchesOf` format key for progress line; all 9 language files contain `stats.winRateFormat`, `stats.streakFormat`, `stats.playMore`, `stats.matchesOf`

### Analytics Accessibility

- [ ] **ACC-01**: StatsView summary card has `accessibilityElement(children: .combine)` with a single composed `accessibilityLabel` covering wins, losses, win rate, and streak — VoiceOver reads it as one element
- [ ] **ACC-02**: WinRateTrendChart `Chart { }` block has `.accessibilityLabel(…)` summarising the selected range and current win rate
- [ ] **ACC-03**: ScoringPatternsChart `Chart { }` block has `.accessibilityLabel(…)` describing that it shows average points scored and conceded per game

## Out of Scope

| Feature | Reason |
|---------|--------|
| "Scored" / "Conceded" chart category label localization | Tied to `chartForegroundStyleScale` key matching; refactor deferred |
| "Game X" labels inside ScoringPatternsChart | Same issue as above; both labels deferred to v1.15 |
| "Custom (%d pts, best of %d)" in format badge | Not yet surfaced in MatchDetailView; deferred |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| STAT-01 | Phase 35 | Pending |
| STAT-02 | Phase 35 | Pending |
| STAT-03 | Phase 35 | Pending |
| ACC-01 | Phase 36 | Pending |
| ACC-02 | Phase 36 | Pending |
| ACC-03 | Phase 36 | Pending |

**Coverage:**
- v1.14 requirements: 6 total
- Mapped to phases: 6
- Unmapped: 0

---
*Requirements defined: 2026-03-31*
