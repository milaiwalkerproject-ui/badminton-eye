# Requirements: Badminton Eye v1.7 — 3×15 Service Continuity & Doubles Game-3 Tests

**Defined:** 2026-03-30
**Core Value:** Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time.

## v1.7 Requirements

### 3×15 Cross-Game Service

- [ ] **SVC3X-01**: After sideA wins game 1 in 3×15 format, sideB (loser) serves first in game 2 from the right court
- [ ] **SVC3X-02**: After sideB wins game 2 in 3×15 (with sideA having won game 1), sideA (loser of game 2) serves first in game 3

### Doubles Game-3 Service

- [ ] **DBLS3-01**: After sideB wins game 2 in doubles (with sideA winning game 1), sideA (loser of game 2) serves first in game 3 with correctly reset doublesRotation
- [ ] **UNDO-G-01**: Undoing the first point of game 2 in doubles restores the cross-game-boundary state (correct server, rotation, and game 1 still in games array)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Doubles 3×15 cross-game service | Same resetServiceForNewGame code path as singles 3×15 |
| Mixed doubles game 3 service | Same rotation reset code path as doubles |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SVC3X-01 | Phase 21 | Pending |
| SVC3X-02 | Phase 21 | Pending |
| DBLS3-01 | Phase 22 | Pending |
| UNDO-G-01 | Phase 22 | Pending |

**Coverage:**
- v1.7 requirements: 4 total
- Mapped to phases: 4
- Unmapped: 0

---
*Requirements defined: 2026-03-30*
