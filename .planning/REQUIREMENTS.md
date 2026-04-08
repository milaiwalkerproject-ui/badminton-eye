# Requirements: Badminton Eye v1.18 — Custom Scoring Mid-Switch & Validation Edge Cases

**Defined:** 2026-04-08
**Core Value:** Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time.

## v1.18 Requirements

### Custom Scoring Mid-Game Switch Tests

- [x] **CST-MID-01**: In a custom-rules match, the mid-game switch fires at `midGameSwitchPoint` in the final game. `shouldSwitchSidesFlag == true` and `hasSwitchedInThirdGame == true` exactly at that threshold.
- [x] **CST-MID-02**: In a custom-rules match, the mid-game switch fires only once in the final game. Scoring beyond `midGameSwitchPoint` does NOT set `shouldSwitchSidesFlag` again.
- [x] **CST-MID-03**: In a custom-rules match, the mid-game switch does NOT fire in a non-final game (game 1 or 2). Scoring through `midGameSwitchPoint` in game 1 leaves `hasSwitchedInThirdGame == false`.

### ScoringRules.isValid Boundary Tests

- [x] **CST-VAL-04**: `isValid` returns `false` when `capScore <= pointsToWin` (cap must exceed the winning threshold).
- [x] **CST-VAL-05**: `isValid` returns `false` when `midGameSwitchPoint == 0`.
- [x] **CST-VAL-06**: A minimal best-of-1 custom format (gamesToWin=1, maxGames=1) passes `isValid`.

## Out of Scope

| Feature | Reason |
|---------|--------|
| UI changes | No UI changes needed — pure engine logic |
| Doubles custom mid-switch | Same code path as singles; covered by existing doubles tests |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CST-MID-01 | Phase 41 | Done |
| CST-MID-02 | Phase 41 | Done |
| CST-MID-03 | Phase 41 | Done |
| CST-VAL-04 | Phase 41 | Done |
| CST-VAL-05 | Phase 41 | Done |
| CST-VAL-06 | Phase 41 | Done |

**Coverage:**
- v1.18 requirements: 6 total
- Mapped to phases: 6
- Unmapped: 0

---
*Requirements defined: 2026-04-08*
