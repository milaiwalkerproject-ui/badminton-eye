# Requirements: Badminton Eye v1.6 — Undo Edge Cases & Cross-Game Service Tests

**Defined:** 2026-03-30
**Core Value:** Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time.

## v1.6 Requirements

### Undo Edge Cases

- [ ] **UND-01**: Undo the match-winning point reverts matchPhase to `.inProgress` with correct game state
- [ ] **UND-02**: Undo at 21-20 (during deuce) reverts to 20-20 and `isDeuce` remains true
- [ ] **UND-03**: Undo the 11th point in the third game (mid-game switch) clears `hasSwitchedInThirdGame` and `shouldSwitchSidesFlag`

### Cross-Game Service Continuity

- [ ] **SVC-01**: After sideA wins game 1, sideB (the loser) serves first in game 2
- [ ] **SVC-02**: After sideB wins game 2 (with sideA having won game 1), sideA (the loser of game 2) serves first in game 3

## Out of Scope

| Feature | Reason |
|---------|--------|
| Changing the winner/loser service rule | Requires BWF rule verification before behavioral change |
| Doubles cross-game service tests | Covered by existing DoublesScoring tests |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| UND-01 | Phase 19 | Pending |
| UND-02 | Phase 19 | Pending |
| UND-03 | Phase 19 | Pending |
| SVC-01 | Phase 20 | Pending |
| SVC-02 | Phase 20 | Pending |

**Coverage:**
- v1.6 requirements: 5 total
- Mapped to phases: 5
- Unmapped: 0

---
*Requirements defined: 2026-03-30*
