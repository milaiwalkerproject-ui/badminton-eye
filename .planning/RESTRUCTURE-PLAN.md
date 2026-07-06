# UI Restructure Tier (a) — Plan (approved 2026-07-06)

Owner decision: **GO** on design-review tier (a): **one match = score + video +
highlights on ONE screen, hero "Start Match"**. (Tier (b) confidence-posture
redesign and (c) shipping the Live Activity were NOT approved — do not touch.)

The Overseer's `DESIGN-REVIEW.md` (23 screenshots) lives on the Mac Studio, NOT
in this repo. This plan comes from a code inventory (workflow wf_51852ea5-766).

## Current state (why the restructure is view-layer only)

- Shell: 4 tabs (Matches / Players / Footage / Settings) inline in `ContentView`
  (`App/BadmintonEyeApp.swift:114-356`); iPad = NavigationSplitView sidebar.
- **No hero Start Match**: landing surface is `MatchHistoryView` (history list);
  starting a match = toolbar "+" → `MatchSetupView` form → floating CTA → 2+ taps.
- One match's data is split across three sibling paths that never cross-link:
  score/analytics (`MatchDetailView`, never reads `match.gameVideos`), video
  (`FootageView` → `FootageDetailView`), highlights (`HighlightClipEditorView`,
  reachable only from FootageDetailView).
- **The data model is already unified**: `PersistedMatch.gameVideos` (cascade)
  → `GameVideoRecord` → `clipRef: ClipRef` ({fileName, startTime, endTime} —
  a highlight is a time range into the game video, not a separate file).
  No schema migration needed.
- Design tokens: `Views/DesignSystem.swift` (BE.TeamA/TeamB gradients,
  serveAccent, scoreNumeral/displayTitle/eyebrow, card(), Space, pop/ease,
  GlassPill/GlassIconButton). `MatchDetailView` currently does NOT use them.

## PR sequence (each keeps CI green and the app fully usable)

1. **Extract reusable game-video components** (no visible change): move
   FootageDetailView's per-game section (player/placeholder, metadata, highlight
   create/edit + share, HighlightExporter wiring) into `Views/GameVideoSection.swift`
   + a `VideoThumbnailView` (AVAssetImageGenerator thumbnail, tap-to-activate
   AVPlayer — do NOT instantiate N live AVPlayers on one scroll view).
2. **Unified MatchDetailView**: add a Video section (gameVideos sorted by
   gameNumber, reusing GameVideoSection) + a horizontal highlights strip
   (records with clipRef != nil; chip seeks AVPlayer to startTime, pauses at
   endTime via boundary observer — no export needed for playback). Restyle with
   BE.* tokens.
3. **Hero home screen**: rebuild Matches tab root as `MatchesHomeView` — hero
   Start Match button (reuse MatchSetupView.startMatchCTA styling) above the
   date-grouped history list; secondary "Import Video" action wired to the
   existing showVideoImport sheet. Keep the "+" toolbar item initially.
4. **Post-match handoff**: expose the persisted match id from
   `LiveMatchViewModel` (currently private), pass to `MatchEndView`, add a
   "View Match" button → unified MatchDetailView.
5. **Retire the Footage tab** (last, so nothing breaks earlier): remove the
   tabItem + iPad sidebar section, relocate Import Video to home. Keep
   FootageView compiling one release or delete + update project.pbxproj.

## Hard guardrails (from the inventory)

- `ContentView` deliberately has NO top-level `@Query` (perf comment at
  BadmintonEyeApp.swift:118-123). Keep every @Query in leaf views with the
  filter pushed into the SQL predicate (FootageView.swift:30-38 pattern) —
  root TabView builds tabs eagerly; Swift-side filtering caused a measured
  cold-launch hang.
- Do not disturb: the Resume-Match pass/prompt (`pendingResumeID`,
  MatchResumeService, BadmintonEyeApp.swift:248-330), the crash-recovery
  `restoredViewModel` branch, LiveMatchView's capture lifecycle
  (`.task` settle-delay, LiveMatchView.swift:137-148), LiveMatchViewModel's
  game-boundary footage writes, or any `AppMode.freeAppleIDMode` gate
  (the gated CloudKit/Watch/LiveActivity/StoreKit paths must stay compilable).
- Query mismatch to resolve: history shows `isComplete` only; Footage shows
  complete OR abandoned. Before PR 5, widen the home list (or add an
  "Abandoned" group) so abandoned-match footage stays reachable.
- All new strings → 9 `.lproj` files (several current Footage strings are
  hardcoded English — localize them during the merge).
- Cleanup opportunity: `sideAScoreButton`/`sideBScoreButton` +
  `ScorePanel` are dead code (unreferenced by current layouts) — reuse
  ScorePanel for the unified score summary or delete it in whichever PR
  touches LiveMatchView last.

## Sequencing vs. wave 1

Wave 1 Phase 1 (in-app labeler) ships first — it's the trip-critical
deliverable. Restructure PRs 1–2 can interleave after that (they touch
different files); PR 3–5 after. The wave-1 progress UI (analysis status) lands
on whatever match-detail surface exists at that time.
