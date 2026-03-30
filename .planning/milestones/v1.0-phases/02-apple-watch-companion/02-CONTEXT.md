# Phase 2: Apple Watch Companion - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase delivers the Apple Watch companion app with glanceable score display, tap-to-score input, real-time bidirectional sync with iPhone via WatchConnectivity, independent offline operation, HealthKit workout integration, and adaptive iPad layout. The Watch app consumes the ScoringEngine package built in Phase 1.

</domain>

<decisions>
## Implementation Decisions

### Watch Scoring UI
- Two large tap zones (top/bottom split) matching iPhone's left/right paradigm — maximizes 45mm screen
- Watch displays: score (large, centered), game indicator (dots), shuttlecock icon for server — absolute minimum for glanceability
- Watch can only JOIN an iPhone-started match, not create new ones — keeps Watch interaction minimal
- Haptic patterns: single tap on score, double tap on game won, long buzz on match complete — distinct and unmistakable during play

### Sync Protocol
- `updateApplicationContext` as primary transport (latest-wins, guaranteed delivery) + `sendMessage` for real-time boost when reachable
- iPhone is authoritative — Watch sends scoring intents, iPhone validates and confirms. Timestamp ordering for disconnection reconciliation
- Watch continues scoring independently using local ScoringEngine copy when disconnected. On reconnect, sync full state snapshot (iPhone state wins if conflict)
- iPhone creates match → Watch auto-receives via applicationContext. Match end on either device propagates to the other

### HealthKit & iPad Layout
- HealthKit workout starts automatically when a match starts on Watch — no extra step
- Workout type: `HKWorkoutActivityType.badminton` with active energy, heart rate, and duration
- iPad layout: NavigationSplitView — match list in sidebar, active match in detail pane
- iPad scoring: same half-screen tap zones as iPhone but with wider panels

### Claude's Discretion
- WatchConnectivity error handling and retry strategies
- Specific animation timing for Watch UI transitions
- Internal naming conventions for sync message types

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ScoringEngine` Swift package — pure value-type state machine, shared between iOS and watchOS targets
- `LiveMatchViewModel` — @Observable bridge to MatchEngine (Phase 1)
- `SwiftDataModels.swift` — PersistedMatch @Model with CloudKit-safe conventions
- `CodableMatchState.swift` — Codable mirror for encoding MatchState

### Established Patterns
- Pure struct state machine with `MatchEngine.apply(event:to:)` transitions
- @Observable view model wrapping MatchEngine for SwiftUI
- SwiftData with autosave for per-point persistence
- Half-screen tap zones for scoring input

### Integration Points
- Watch target imports ScoringEngine package (add watchOS target to Xcode project)
- WatchConnectivity manager bridges iPhone and Watch scoring ViewModels
- HealthKit session starts when LiveMatchViewModel begins a match
- iPad layout adapts existing iPhone views via NavigationSplitView

</code_context>

<specifics>
## Specific Ideas

- Top/bottom tap zone split on Watch (not left/right — wrist ergonomics)
- Game indicator as dots (●●○ for game 3 of best-of-3)
- Shuttlecock icon rotates to indicate serving side
- Watch should feel like a "remote control" for the scoring, not a standalone app

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope

</deferred>
