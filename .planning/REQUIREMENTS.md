# Requirements: Badminton Eye v1.10 — Localize Remaining Views

**Defined:** 2026-03-31
**Core Value:** Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time.

## v1.10 Requirements

### Wire Existing Keys to Views

- [x] **LOC-01**: MatchHistoryView uses `history.title` and `history.noMatches` localization keys instead of hardcoded English strings
- [x] **LOC-02**: StatsView uses `stats.title`, `stats.wins`, and `stats.losses` localization keys instead of hardcoded English strings
- [x] **LOC-03**: LiveMatchView uses `match.game` localization key for the game number label

### New Localization Keys

- [x] **LOC-04**: New keys `game.over`, `game.continue`, `match.new`, and `match.games` added to all 9 Localizable.strings files (en, ja, zh-Hans, ko, id, ms, hi, th, da) with correct translations
- [x] **LOC-05**: GameEndOverlay uses `game.over`, `match.undo`, and `game.continue` localization keys
- [x] **LOC-06**: MatchEndView uses `match.new` for the New Match button and `match.games` for the games tally row; game score rows use `match.game` for the "Game N" label

## Out of Scope

| Feature | Reason |
|---------|--------|
| MatchSetupView localization | Picker labels use Tag-associated Text which SwiftUI can handle natively; format strings like "Custom (X pts, best of X)" require localization format strings |
| Win rate / streak format strings | Require `%@` format pattern localization; separate milestone |
| Date grouping labels (Today, Yesterday) | Handled natively by iOS Calendar/DateFormatter system locale |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| LOC-01 | Phase 27 | Complete |
| LOC-02 | Phase 27 | Complete |
| LOC-03 | Phase 27 | Complete |
| LOC-04 | Phase 28 | Complete |
| LOC-05 | Phase 28 | Complete |
| LOC-06 | Phase 28 | Complete |

**Coverage:**
- v1.10 requirements: 6 total
- Mapped to phases: 6
- Unmapped: 0

---
*Requirements defined: 2026-03-31*
