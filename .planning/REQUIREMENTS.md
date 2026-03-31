# Requirements: Badminton Eye v1.8 — Doubles & Mixed Deuce/Cap Coverage

**Defined:** 2026-03-30
**Core Value:** Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time.

## v1.8 Requirements

### Doubles Deuce & Cap

- [x] **DUB-DCE-01**: Doubles deuce activates at 20-20 (isDeuce is true, same threshold as singles)
- [x] **DUB-DCE-02**: Doubles 21-20 does NOT win the game in deuce (2-point lead required)
- [x] **DUB-DCE-03**: Doubles cap at 30-29 ends the game (cap overrides the 2-point-lead requirement)

### Doubles Mid-Game Switch & Undo

- [x] **DUB-MID-01**: Doubles game-3 mid-switch triggers shouldSwitchSidesFlag at 11 points
- [x] **DUB-UND-01**: Undo in doubles during deuce (at 21-20) reverts to 20-20 with correct server restored

### Mixed Doubles Cross-Game Service

- [x] **MXD-G3-01**: Mixed doubles: loser of game 2 serves first in game 3 (same resetServiceForNewGame path as doubles)

## Out of Scope

| Feature | Reason |
|---------|--------|
| 3×15 doubles deuce/cap | Same isGameWon code path; already covered via singles 3×15 tests |
| Custom scoring deuce in doubles | Same isGameWon code path; covered in CustomScoringTests |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DUB-DCE-01 | Phase 23 | Complete |
| DUB-DCE-02 | Phase 23 | Complete |
| DUB-DCE-03 | Phase 23 | Complete |
| DUB-MID-01 | Phase 23 | Complete |
| DUB-UND-01 | Phase 23 | Complete |
| MXD-G3-01 | Phase 24 | Complete |

**Coverage:**
- v1.8 requirements: 6 total
- Mapped to phases: 6
- Unmapped: 0

---
*Requirements defined: 2026-03-30*
