# Requirements: Badminton Eye v1.12 — Localize HeadToHeadView, PlayerProfileView, MatchDetailView & Analytics Charts

**Defined:** 2026-03-31
**Core Value:** Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time.

## v1.12 Requirements

### HeadToHeadView Localization

- [ ] **H2H-01**: HeadToHeadView navigation title, "Opponents" section header, "All Matches" section header, "No matches yet" empty state all use localized keys; existing `stats.wins` and `stats.losses` keys reused for W/L labels

### PlayerProfileView Localization

- [ ] **PPV-01**: PlayerProfileView section headers ("Name", "Photo") use localized keys; form fields ("Player Name" placeholder) use localized key; toolbar buttons ("Cancel", "Save") use localized keys; navigation title ("New Player" / "Edit Player") uses localized keys
- [ ] **PPV-02**: PlayerProfileView destructive actions ("Choose Photo", "Remove Photo", "Delete Player") use localized keys; delete confirmation alert title ("Delete Player?") uses localized key

### Analytics Chart Localization

- [ ] **ANA-01**: WinRateTrendChart card title ("Performance Trend") and empty state ("Not enough data") use localized keys; chart x-axis label ("Match") uses localized key
- [ ] **ANA-02**: ScoringPatternsChart card title ("Scoring Patterns") and empty state ("Not enough data") use the same localized key as ANA-01 (`chart.notEnoughData`)

### MatchDetailView Localization

- [ ] **MDV-01**: MatchDetailView navigation title ("Match Details") and toolbar menu actions ("Share Scorecard", "Export...") use localized keys; existing `match.games` key reused for the "Games" summary row

### Localization Strings

- [ ] **STR-01**: 21 new keys added to all 9 Localizable.strings files (en, ja, zh-Hans, ko, id, ms, hi, th, da) with correct native translations

## Out of Scope

| Feature | Reason |
|---------|--------|
| Alert message "This will permanently remove \(name)…" | Contains `%@` format string; requires NSLocalizedString with format args |
| "Game \(index+1)" format strings in MatchDetailView | Requires `%d` format string interpolation |
| "Matches vs \(opponent)" format string in HeadToHeadView | Requires `%@` format string interpolation |
| WinRateTrendChart range picker "Last 10/20/50" | Enum rawValues with number interpolation |
| "Custom (%d pts, best of %d)" | Requires format string arguments |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| H2H-01 | Phase 31 | Pending |
| PPV-01 | Phase 31 | Pending |
| PPV-02 | Phase 31 | Pending |
| ANA-01 | Phase 32 | Pending |
| ANA-02 | Phase 32 | Pending |
| MDV-01 | Phase 32 | Pending |
| STR-01 | Phase 31 | Pending |

**Coverage:**
- v1.12 requirements: 7 total
- Mapped to phases: 7
- Unmapped: 0

---
*Requirements defined: 2026-03-31*
