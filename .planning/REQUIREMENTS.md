# Requirements: Badminton Eye v1.16 — Games 4 & 5 in Scoring Analytics

**Defined:** 2026-04-05
**Core Value:** Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time.

## v1.16 Requirements

### Games 4 & 5 in perGameAverages()

- [x] **ANAL-01**: `perGameAverages()` collects game 4 scored/conceded data from `game4ScoreA` / `game4ScoreB` fields and includes a game 4 entry in the returned array when at least one completed match has game 4 data.
- [x] **ANAL-02**: `perGameAverages()` collects game 5 scored/conceded data from `game5ScoreA` / `game5ScoreB` fields and includes a game 5 entry in the returned array when at least one completed match has game 5 data.
- [x] **ANAL-03**: For matches with fewer than 4 or 5 games, the missing game entries are simply absent (no zero-padding). Existing game 1–3 behaviour is unchanged.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Updating detectPlayer to include playerBName | Detection is best-effort; selectedPlayerName override handles edge cases |
| UI changes to ScoringPatternsChart | Already handles any number of games dynamically |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| ANAL-01 | Phase 39 | Done |
| ANAL-02 | Phase 39 | Done |
| ANAL-03 | Phase 39 | Done |

**Coverage:**
- v1.16 requirements: 3 total
- Mapped to phases: 3
- Unmapped: 0

---
*Requirements defined: 2026-04-05*
