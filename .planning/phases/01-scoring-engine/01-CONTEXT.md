# Phase 1: Scoring Engine - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase delivers a complete BWF-compliant badminton scoring engine with an iPhone UI. Users can start singles, doubles, or mixed doubles matches, score points by tapping, see correct service tracking, undo mistakes, and play fully offline. No Watch, no cloud, no AI — just a rock-solid scoring foundation.

</domain>

<decisions>
## Implementation Decisions

### Match Setup & Format
- Simple setup screen: pick format (singles/doubles/mixed), enter player names, tap Start — minimal friction
- Player names are optional — default to "Player 1" / "Player 2" for quick pickup games
- Doubles teams: select 2 players per side from saved list, or type names inline
- User can abandon a match mid-game via "End Match" button with confirmation dialog, saves partial result

### Scoring UI Layout
- Two large half-screen tap zones (left side = team A, right side = team B) — maximizes tap target, works one-handed
- Always visible during match: score (large), game number, server indicator, service court side — minimal clutter
- Server/service court indicated by shuttlecock icon on serving player's side + highlighted service court (left/right)
- Game end: brief celebration overlay with game score summary, auto-advance to next game; match end shows full scorecard

### State Machine & Persistence
- Single-level undo (revert last point only) — simple, covers 95% of mis-taps
- SwiftData model saved after every point — survives app crash, background kill, Watch disconnection
- Pure value-type state machine (struct) with deterministic transitions — all rules encoded as computed properties, exhaustively testable
- Design SwiftData models with CloudKit constraints from day one (optional properties, no @Attribute(.unique)) even though sync ships in Phase 4

### Claude's Discretion
- Specific color scheme and visual design details
- Animation timing and transition styles
- Internal naming conventions for state machine types

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- None — greenfield project, Phase 1 is the first code written

### Established Patterns
- None yet — this phase establishes the patterns all subsequent phases follow
- Research recommends: Swift 6, SwiftUI, SwiftData, pure value-type state machine

### Integration Points
- SwiftData models designed here will be used by Watch (Phase 2), Match Data (Phase 3), CloudKit (Phase 4)
- Scoring state machine will be shared between iPhone and Watch targets
- Must be a separate Swift package or shared framework for multi-target use

</code_context>

<specifics>
## Specific Ideas

- BWF 21-point rally scoring: best-of-3 games, 2-point deuce lead at 20-all, 30-point cap
- Doubles service rotation must track which specific player serves and from which court (left/right based on even/odd score)
- Side switch at end of each game + at 11 points in third game
- Half-screen tap zones for scoring — court-side usability is critical
- Shuttlecock icon for server indicator

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope

</deferred>
