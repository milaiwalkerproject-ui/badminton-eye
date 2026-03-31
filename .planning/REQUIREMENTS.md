# Requirements: Badminton Eye v1.11 — Wire SettingsView, MatchSetupView & PlayerListView Localization

**Defined:** 2026-03-31
**Core Value:** Players can effortlessly record badminton match scores from either their iPhone/iPad or Apple Watch, with both devices synced in real-time.

## v1.11 Requirements

### SettingsView Localization

- [x] **SET-01**: SettingsView premium section uses `premium.active`, `premium.allUnlocked`, `premium.manage`, `premium.upgrade`, `premium.unlockHawkEye` instead of hardcoded English strings; section header uses `settings.premium`
- [x] **SET-02**: SettingsView auth/iCloud sections use `icloud.title`, `icloud.signInPrompt`, `icloud.syncActive`, `icloud.account`, `settings.signOut` instead of hardcoded English strings
- [x] **SET-03**: SettingsView haptic section uses `settings.scoring` (header), `settings.haptic`, `settings.haptic.subtitle` instead of hardcoded English strings
- [x] **SET-04**: SettingsView about section uses `settings.about`, `settings.version`, `settings.build`, `settings.restorePurchases` instead of hardcoded English strings

### MatchSetupView Localization

- [x] **SUP-01**: MatchSetupView uses `setup.matchFormat`, `setup.singles`, `setup.doubles`, `setup.mixed` for the Match Format section
- [x] **SUP-02**: MatchSetupView uses `setup.scoring`, `setup.scoringStandard`, `setup.scoring3x15`, `setup.customFormat` for the Scoring section
- [x] **SUP-03**: MatchSetupView uses `setup.teamA`, `setup.teamB`, `setup.startMatch`; navigation title uses `setup.title`

### PlayerListView Localization

- [x] **PLA-01**: New keys `players.search`, `players.edit`, `players.noPlayers`, `players.addFirst` added to all 9 Localizable.strings files with correct translations; PlayerListView uses `players.title`, `players.search`, `players.edit`, `players.noPlayers`, `players.addFirst`

## Out of Scope

| Feature | Reason |
|---------|--------|
| Custom format display string "Custom (X pts, best of X)" | Requires `%@` format pattern localization; separate milestone |
| Win rate / streak format strings in HeadToHeadView | Require `%@` format pattern localization; separate milestone |
| Picker label "Format" / "Scoring System" | Internal to SwiftUI Picker; not user-visible as standalone text |
| Player placeholder names ("Player 1A" etc.) | Only shown when fields empty; low visibility |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| SET-01 | Phase 29 | Done |
| SET-02 | Phase 29 | Done |
| SET-03 | Phase 29 | Done |
| SET-04 | Phase 29 | Done |
| SUP-01 | Phase 30 | Done |
| SUP-02 | Phase 30 | Done |
| SUP-03 | Phase 30 | Done |
| PLA-01 | Phase 30 | Done |

**Coverage:**
- v1.11 requirements: 8 total
- Mapped to phases: 8
- Unmapped: 0

---
*Requirements defined: 2026-03-31*
