# Requirements: Badminton Eye v1.9 — 3×15 Undo & Mixed Doubles Boundary Tests

**Defined:** 2026-03-30
**Core Value:** Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time.

## v1.9 Requirements

### 3×15 Undo Edge Cases

- [ ] **THX-UND-01**: Undo at 15-14 (deuce state) in 3×15 reverts to 14-14 with isDeuce true
- [ ] **THX-UND-02**: Undo the 8th-point mid-game-switch in 3×15 5th game clears hasSwitchedInThirdGame flag and shouldSwitchSidesFlag
- [ ] **THX-UND-03**: Undo the first point of 3×15 game 3 restores cross-game-boundary state (server, score, completed-game list)

### Mixed Doubles Undo & Mid-Switch

- [ ] **MXD-UND-01**: Mixed doubles undo of the first point of game 2 restores pre-game-end state (server, rotation, scores, game 1 in games array)
- [ ] **MXD-MID-01**: Mixed doubles game-3 mid-switch triggers shouldSwitchSidesFlag when total points reach 11 (same threshold as doubles)

## Out of Scope

| Feature | Reason |
|---------|--------|
| 3×15 doubles undo tests | 3×15 doubles format uses same undo code path as standard doubles; standard doubles undo already covered |
| Custom scoring undo in doubles | Same undo code path; standard doubles and custom singles undo already covered |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| THX-UND-01 | Phase 25 | Pending |
| THX-UND-02 | Phase 25 | Pending |
| THX-UND-03 | Phase 25 | Pending |
| MXD-UND-01 | Phase 26 | Pending |
| MXD-MID-01 | Phase 26 | Pending |

**Coverage:**
- v1.9 requirements: 5 total
- Mapped to phases: 5
- Unmapped: 0

---
*Requirements defined: 2026-03-30*
