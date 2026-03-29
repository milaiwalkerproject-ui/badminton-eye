# Phase 6: Match Analytics - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase delivers a statistics dashboard accessible from a new "Stats" tab showing win/loss summary, win streak, performance trend chart over configurable time ranges, and per-game scoring pattern visualization. All analytics computed from existing PersistedMatch data with no new SwiftData models or migrations.

</domain>

<decisions>
## Implementation Decisions

### Statistics Dashboard
- Scrollable cards layout: summary card (W/L/streak) at top, trend chart below, then game patterns — single column, no tabs-within-tabs
- Win rate trend: segmented control with Last 10 / Last 20 / All matches — user toggles inline
- Per-game scoring patterns: grouped bar chart showing average points scored and conceded per game (1/2/3) — compact, glanceable
- Empty state when <3 matches: "Play more matches to unlock analytics" with match count indicator

### Data & Integration
- Compute from existing PersistedMatch + decoded game scores — no new SwiftData model, pure computed aggregation
- Stats tab position: third tab (Matches / Players / Stats / Settings)
- Tap any player in Stats to see head-to-head trend (reuses HeadToHeadView pattern)
- Stats recompute on tab appearance (onAppear) — data is local and fast

### Claude's Discretion
- Chart color scheme and styling
- Card spacing and padding
- Animation timing for chart transitions
- Specific Swift Charts mark types and modifiers

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PersistedMatch` SwiftData @Model — stores format, player names, game scores, stateJSON, winnerSide
- `HeadToHeadView` — opponent-specific stats pattern from Phase 3
- `MatchHistoryView` — date-grouped match list pattern
- TabView in `BadmintonEyeApp.swift` — currently has Matches / Players / Settings tabs

### Established Patterns
- SwiftData queries with @Query property wrapper
- @Observable view models for computed state
- NavigationLink for drill-down

### Integration Points
- Add "Stats" tab to existing TabView in BadmintonEyeApp.swift
- Swift Charts framework import (new for this phase)
- Reuse HeadToHeadView for per-opponent drill-down from stats

</code_context>

<specifics>
## Specific Ideas

- Summary card with large W-L number and streak badge
- Line chart for win rate trend with segmented control toggle
- Grouped bar chart for per-game patterns
- Minimum 3 matches threshold for analytics

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope

</deferred>
