# Phase 4: Cloud Sync and Authentication - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase delivers Apple Sign-In authentication, CloudKit-based cross-device data sync for match history and player profiles, local-only mode for unsigned users, and Live Activity on iPhone lock screen and Dynamic Island showing live match scores.

</domain>

<decisions>
## Implementation Decisions

### Authentication & Cloud Sync
- Sign-in UI in Settings tab — sign-in card at top with Apple button, signed-in state shows iCloud status and account info
- Auto-merge on sign-in: local data uploads to iCloud, cloud data from other devices downloads. No data loss.
- SwiftData with CloudKit automatic sync (NSPersistentCloudKitContainer under the hood) — zero custom server code
- Seamless offline-to-online: app works identically offline, syncs delta when connectivity returns. SwiftData handles merge automatically.

### Live Activity & Dynamic Island
- Live Activity shows: current score (large), game number, server indicator, player/team names — mirrors Watch glanceable display
- Dynamic Island compact: score only "12-9" in minimal leading/trailing layout
- Auto-starts when match begins, auto-ends when match completes or abandoned — no user action needed
- Lock screen expanded: full score with player names, game indicator dots, server — tap opens app to match

### Claude's Discretion
- CloudKit container identifier naming
- Sign-in button styling details
- Live Activity color scheme and layout specifics
- Error handling for CloudKit sync failures

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PersistedMatch` and `Player` SwiftData @Models — already CloudKit-safe (optional props, no @Attribute(.unique))
- `CodableMatchState` — serialization for match state
- `LiveMatchViewModel` — needs Live Activity start/stop integration
- Settings tab placeholder in TabView (Phase 3)

### Established Patterns
- SwiftData with autosave and CloudKit constraints from Phase 1
- @Observable view models
- TabView navigation (iPhone) / NavigationSplitView (iPad)

### Integration Points
- SwiftData modelContainer needs CloudKit configuration toggle based on auth state
- LiveMatchViewModel triggers Live Activity on match start/end
- ActivityKit widget extension for Live Activity rendering
- Settings tab for sign-in UI

</code_context>

<specifics>
## Specific Ideas

- Apple Sign-In button using ASAuthorizationAppleIDButton (system-provided)
- Live Activity mirrors Watch layout concept — glanceable score
- Dynamic Island compact view: just the score "12-9"

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope

</deferred>
