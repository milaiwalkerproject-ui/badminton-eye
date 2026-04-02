# Requirements: Badminton Eye v1.15 — Chart Labels & Custom Format Badge Localization

**Defined:** 2026-04-02
**Core Value:** Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time.

## v1.15 Requirements

### ScoringPatternsChart Localization

- [ ] **CHART-01**: ScoringPatternsChart "Game X" x-axis labels use `String(format: localization.localized("game.number"), avg.game)` — switching to Japanese shows "第1ゲーム" etc.
- [ ] **CHART-02**: ScoringPatternsChart bar series use `chart.scored` / `chart.conceded` localization keys for the type label; `chartForegroundStyleScale` keys match the localized strings so colors remain correct in all languages
- [ ] **CHART-03**: `chart.scored` and `chart.conceded` keys are present in all 9 Localizable.strings files with correct native translations

### Custom Format Badge

- [ ] **BADGE-01**: MatchDetailView `formatBadge` for `scoringSystemRaw == "custom"` decodes `customRulesJSON` and returns `"\(base) · " + String(format: localization.localized("setup.customDetail"), rules.pointsToWin, rules.gamesToWin)` — e.g. "Singles · Custom (17 pts, best of 3)"
- [ ] **BADGE-02**: `setup.customDetail` format key is present in all 9 Localizable.strings files with correct native translations

## Out of Scope

| Feature | Reason |
|---------|--------|
| chartAccessibilityLabel using localized "scored"/"conceded" in the summary sentence | Low priority; screen reader users understand the numbers in context |
| Custom format badge when `customRulesJSON` is nil (fallback to "· Custom") | Nil only if data was created before v1.3; safe fallback retained |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CHART-01 | Phase 37 | Pending |
| CHART-02 | Phase 37 | Pending |
| CHART-03 | Phase 37 | Pending |
| BADGE-01 | Phase 38 | Pending |
| BADGE-02 | Phase 38 | Pending |

**Coverage:**
- v1.15 requirements: 5 total
- Mapped to phases: 5
- Unmapped: 0

---
*Requirements defined: 2026-04-02*
