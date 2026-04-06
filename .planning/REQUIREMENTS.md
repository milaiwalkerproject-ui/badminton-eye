# Requirements: Badminton Eye v1.17 — 3×15 Games 3–4–5 Service Continuity Tests

**Defined:** 2026-04-05
**Core Value:** Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time.

## v1.17 Requirements

### 3×15 Cross-Game Service Continuity (Games 3→4 and 4→5)

- [x] **THX-G4-01**: In a 3×15 match, the loser of game 3 serves first in game 4. `currentServer.side` equals the losing side of game 3 immediately after game 4 starts.
- [x] **THX-G5-01**: In a 3×15 match, the loser of game 4 serves first in game 5. `currentServer.side` equals the losing side of game 4 immediately after game 5 starts.
- [x] **THX-G4-02**: Game 4 in a 3×15 match does NOT trigger a mid-game switch at 8 points (the switch only fires in the final game 5, not game 4).
- [x] **THX-UND-04**: Undo of the first point of game 4 fully restores the cross-game-boundary state: `gameNumber == 4`, `scoreA == 0`, `scoreB == 0`, correct server, and 3 completed games in `games`.
- [x] **THX-UND-05**: Undo of the first point of game 5 fully restores the cross-game-boundary state: `gameNumber == 5`, `scoreA == 0`, `scoreB == 0`, correct server, and 4 completed games in `games`.

## Out of Scope

| Feature | Reason |
|---------|--------|
| UI changes to ScoringPatternsChart | Already handles any number of games dynamically |
| Doubles/mixed 3×15 cross-game tests beyond game 3 | Same code path as singles; lower priority |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| THX-G4-01 | Phase 40 | Done |
| THX-G5-01 | Phase 40 | Done |
| THX-G4-02 | Phase 40 | Done |
| THX-UND-04 | Phase 40 | Done |
| THX-UND-05 | Phase 40 | Done |

**Coverage:**
- v1.17 requirements: 5 total
- Mapped to phases: 5
- Unmapped: 0

---
*Requirements defined: 2026-04-05*
