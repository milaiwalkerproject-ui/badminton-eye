# Phase 3: Match Data and Player Profiles - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase delivers match history browsing, player profile management, head-to-head win/loss records, match result sharing as images, and CSV/PDF data export. All data operations build on the existing SwiftData PersistedMatch model from Phase 1, adding a new Player model and query-based views.

</domain>

<decisions>
## Implementation Decisions

### Match History UI
- Chronological list with date headers (Today, Yesterday, This Week, Older), each row shows opponent names + final score + match format badge
- Match detail view: game-by-game score cards stacked vertically with per-game server indicators and side switch markers
- Empty state: friendly illustration + "Start your first match" CTA button linking to match setup
- Swipe-to-delete with confirmation alert — standard iOS pattern

### Player Profiles
- Player photo: camera or photo library picker, optional, default to initials avatar (first letter of name, colored background)
- Alphabetical scrollable list with search bar, initials/photo avatar on left, W/L record on right
- Quick-select in match setup: tappable chips showing recent opponents at top, full player list below with search — select 1 for singles, 2 per side for doubles
- Head-to-head: dedicated screen from player profile with big W-L number, match list against that opponent, win rate percentage

### Sharing & Export
- Scorecard image: court-themed card with player names, final scores per game, date, and "Badminton Eye" watermark — rendered as UIImage for share sheet
- CSV: one row per match (date, format, player names, game scores, winner) — importable by any spreadsheet app
- PDF: styled scorecard matching share image but formatted for A4/Letter printing with all games and match metadata
- Share/export trigger: buttons in match detail view toolbar — share icon for image, export icon for CSV/PDF with format picker

### Claude's Discretion
- Specific color palette for initials avatars
- Animation timing for list transitions
- Court-themed scorecard visual design details
- PDF layout engine choice (UIGraphicsPDFRenderer vs third-party)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PersistedMatch` SwiftData @Model (Phase 1) — stores match state with CloudKit-safe conventions
- `CodableMatchState` — Codable mirror of MatchState for serialization
- `MatchEndView` (Phase 1) — already shows final scorecard, can be adapted for match detail
- `MatchSetupView` (Phase 1) — player name input, needs player profile integration

### Established Patterns
- SwiftData with autosave and optional properties for CloudKit compatibility
- @Observable view models wrapping domain logic
- NavigationSplitView for iPad (Phase 2) — match list already in sidebar

### Integration Points
- New Player @Model needs relationship to PersistedMatch (optional, CloudKit-safe)
- MatchSetupView needs player quick-select integration
- iPad NavigationSplitView sidebar needs match history list
- Match detail needs share/export toolbar buttons

</code_context>

<specifics>
## Specific Ideas

- Date-grouped sections (Today, Yesterday, This Week, Older) for match list
- Tappable player chips for quick opponent selection
- Court-themed scorecard image with watermark for social sharing
- Head-to-head screen accessible from player profile tap

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope

</deferred>
