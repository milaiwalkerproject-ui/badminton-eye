---
phase: 03-match-data-and-player-profiles
plan: 02
subsystem: ui
tags: [swiftui, swiftdata, player-profiles, photospicker, tabview, head-to-head]

requires:
  - phase: 03-match-data-and-player-profiles/01
    provides: Player model, PersistedMatch model, MatchHistoryView
provides:
  - PlayerListView with search, avatars, and W/L records
  - PlayerProfileView with CRUD and photo support
  - HeadToHeadView with per-opponent breakdown
  - PlayerPickerView with recent opponent chips
  - TabView navigation (iPhone) and sidebar navigation (iPad)
  - Auto-creation of Player records from match setup
affects: [03-match-data-and-player-profiles/03, 04-iphone-watch-sync]

tech-stack:
  added: [PhotosUI/PhotosPicker]
  patterns: [avatar-from-name-hash, recent-opponents-chips, auto-create-on-use]

key-files:
  created:
    - BadmintonEye/BadmintonEye/Views/PlayerListView.swift
    - BadmintonEye/BadmintonEye/Views/PlayerProfileView.swift
    - BadmintonEye/BadmintonEye/Views/HeadToHeadView.swift
    - BadmintonEye/BadmintonEye/Views/PlayerPickerView.swift
  modified:
    - BadmintonEye/BadmintonEye/App/BadmintonEyeApp.swift
    - BadmintonEye/BadmintonEye/Views/MatchSetupView.swift
    - BadmintonEye/BadmintonEye.xcodeproj/project.pbxproj

key-decisions:
  - "Initials avatar color derived from name.hashValue mod 8-color palette for consistent per-player colors"
  - "TabView for iPhone (Matches + Players tabs) vs NavigationSplitView sidebar for iPad"
  - "PlayerPickerView instantiates PlayerListView avatar helper for reuse rather than duplicating"
  - "Auto-create Player records on match start for organic player list growth"

patterns-established:
  - "Avatar pattern: Circle with first-initial + deterministic color from name hash, photo override when available"
  - "Picker-as-sheet pattern: person.circle button next to TextField opens sheet with searchable picker"

requirements-completed: [DATA-03, DATA-04, DATA-05]

duration: 4min
completed: 2026-03-29
---

# Phase 3 Plan 2: Player Profiles and Quick-Select Summary

**Player CRUD with photo support, alphabetical list with search and W/L stats, head-to-head opponent breakdown, and quick-select chips in match setup**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-29T06:20:44Z
- **Completed:** 2026-03-29T06:25:43Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- Player list with @Query sorting, .searchable, initials avatars (8-color palette from name hash), and W/L record per player
- Player profile create/edit/delete with PhotosPicker, image resize to 200x200 JPEG thumbnail
- Head-to-head view with large W-L display, win rate percentage, per-opponent breakdown, and filterable match history
- TabView navigation for iPhone (Matches + Players tabs) and sidebar sections for iPad
- Player quick-select via recent opponent chips and searchable list in match setup
- Auto-creation of Player records when starting matches with new names

## Task Commits

Each task was committed atomically:

1. **Task 1: Player list, profile create/edit, and head-to-head views** - `f07d6df` (feat)
2. **Task 2: Player quick-select integration in match setup** - `cae9b44` (feat)

## Files Created/Modified
- `BadmintonEye/BadmintonEye/Views/PlayerListView.swift` - Alphabetical player list with search, initials avatars, W/L records, NavigationLink to head-to-head
- `BadmintonEye/BadmintonEye/Views/PlayerProfileView.swift` - Create/edit player form with name TextField, PhotosPicker, image resize, delete with confirmation
- `BadmintonEye/BadmintonEye/Views/HeadToHeadView.swift` - Big W-L display, win rate, per-opponent breakdown, filterable match history
- `BadmintonEye/BadmintonEye/Views/PlayerPickerView.swift` - Recent opponent chips (horizontal ScrollView), searchable player list, excludeNames support
- `BadmintonEye/BadmintonEye/App/BadmintonEyeApp.swift` - Added TabView with Matches/Players tabs (iPhone), sidebar sections (iPad)
- `BadmintonEye/BadmintonEye/Views/MatchSetupView.swift` - Added person.circle picker buttons, sheet-based PlayerPickerView, auto-create Player records
- `BadmintonEye/BadmintonEye.xcodeproj/project.pbxproj` - Added 4 new Swift files to build

## Decisions Made
- Initials avatar color derived from `name.hashValue % 8` for deterministic per-player colors across all views
- TabView for iPhone (compact size class) with sportscourt and person.2 tab icons; NavigationSplitView sidebar for iPad (regular size class)
- PlayerPickerView reuses PlayerListView.avatarView helper to avoid duplicating avatar rendering logic
- Auto-create Player records on match start so the player database grows organically from usage
- HeadToHeadView shows overall stats by default with tappable per-opponent rows to filter match list

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
- Pre-existing build failure in MatchDetailView.swift (references ScorecardRenderer, ExportFormatPicker, ActivityViewController not yet implemented) -- out of scope, from a future plan. Does not affect this plan's files.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Player profiles and match setup integration complete
- Ready for Plan 03 (export/sharing features) which can build on the player and match data infrastructure
- Pre-existing MatchDetailView build issue needs resolution in the plan that introduced those references

---
*Phase: 03-match-data-and-player-profiles*
*Completed: 2026-03-29*
