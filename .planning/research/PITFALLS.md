# Domain Pitfalls: v1.2 Haptic Feedback, BWF 3x15 Scoring, Multi-Camera Hawk Eye

**Domain:** Adding haptic feedback, alternate scoring format, and multi-camera support to existing iOS badminton scoring app
**Researched:** 2026-03-29
**Overall confidence:** MEDIUM (no web search available; based on codebase analysis + training data knowledge of Apple APIs)

---

## Area 1: ScoringEngine -- Adding BWF 3x15 Format

### Critical Pitfall 1.1: Hardcoded Magic Numbers in BWFRules.swift

**Risk Level:** CRITICAL
**What goes wrong:** `BWFRules.swift` has hardcoded `20`, `21`, `29`, `30`, and `11` throughout its computed properties (`isDeuce`, `isAtCap`, `isGameWon`, `shouldSwitchSides`). Adding 3x15 means every one of these constants changes: deuce at 14, cap at 17 (if BWF keeps a cap), game won at 15, side switch at 8 in third game. Naively adding `if format == .threeByFifteen` branches to each property creates a parallel rule system that diverges and rots.
**Why it happens in this codebase:** The current `MatchState.format` is `MatchFormat` (singles/doubles/mixed) -- it describes team composition, NOT scoring rules. There is no concept of "scoring system" separate from "match format." The temptation is to overload `MatchFormat` with `.singles3x15`, `.doubles3x15`, `.mixed3x15` -- tripling the enum surface.
**Consequences:** 6+ enum cases where 3 existed. Every `switch` on `MatchFormat` throughout the entire codebase (MatchSetupView, LiveMatchViewModel, CodableMatchState, WatchMatchViewModel, SyncPayload, PersistedMatch) must handle the new cases. Missed switches cause silent bugs.
**Prevention:**
- Introduce a separate `ScoringSystem` enum (`.standard21` / `.bwf3x15`) on `MatchState`, orthogonal to `MatchFormat`
- Extract rule constants into a `ScoringRules` struct: `struct ScoringRules { let pointsToWin: Int; let deuceThreshold: Int; let capScore: Int; let maxGames: Int; let sidesSwitchPoint: Int }`
- `BWFRules.swift` computed properties read from `self.scoringRules` instead of hardcoded numbers
- `MatchFormat` stays as-is (singles/doubles/mixed)
**When to address:** Phase 1 (before any scoring logic changes). This is the foundation.

### Critical Pitfall 1.2: Breaking 44 Existing Tests Without Realizing It

**Risk Level:** CRITICAL
**What goes wrong:** All 44 tests assume 21-point scoring. Adding `ScoringSystem` to `MatchState` changes the struct layout. If the default is `.standard21`, existing tests pass silently -- but `CodableMatchState` deserialization of old JSON (from v1.0 crash recovery or CloudKit) fails because the new field is missing.
**Why it happens in this codebase:** `CodableMatchState` is a manual mirror of `MatchState` (not auto-synthesized). It has an explicit `init(from state:)` and `toMatchState()`. Adding a `scoringSystem` field to `MatchState` but forgetting to add it to `CodableMatchState` means crash recovery silently drops the scoring system and defaults to... whatever the factory method uses.
**Consequences:** A match started as 3x15 crashes/recovers and comes back as 21-point. Scores make no sense. Watch shows wrong game state.
**Prevention:**
- Add `scoringSystem` to `CodableMatchState` with `var scoringSystem: ScoringSystem = .standard21` (default handles backward compat)
- Write a dedicated test: decode a v1.0 JSON blob (no `scoringSystem` field) and verify it round-trips as `.standard21`
- Write 3x15-specific tests BEFORE changing any engine logic (TDD)
- Run all 44 existing tests after every change to `MatchState` or `BWFRules`
**When to address:** Phase 1, alongside the scoring rules refactor.

### Moderate Pitfall 1.3: isMatchComplete Changes for Best-of-3 at 15

**Risk Level:** MODERATE
**What goes wrong:** `isMatchComplete` currently checks `gamesWon.sideA >= 2 || gamesWon.sideB >= 2`. This is correct for best-of-3 in both formats. BUT the BWF 3x15 proposal has discussed best-of-5 sets of 11 as an alternative. If the format changes before or after the April 2026 BWF vote, the `>= 2` threshold is wrong.
**Why it happens:** BWF has not finalized the rules as of the project start date. Building against a moving spec.
**Consequences:** Implementing the wrong format, then having to change it post-ship.
**Prevention:**
- Put `gamesRequiredToWin` in the `ScoringRules` struct (2 for best-of-3, 3 for best-of-5)
- Make `isMatchComplete` read from `scoringRules.gamesRequiredToWin`
- Monitor BWF announcements and flag this as a "rules may change" item
**When to address:** Phase 1 design, but monitor through Phase 2.

### Moderate Pitfall 1.4: PersistedMatch game3Score Fields Assume Max 3 Games

**Risk Level:** MODERATE
**What goes wrong:** `PersistedMatch` has `game1ScoreA/B`, `game2ScoreA/B`, `game3ScoreA/B` -- exactly 3 games. If BWF goes best-of-5, there is no `game4` or `game5`. The `updateGameScores()` method in `LiveMatchViewModel` indexes `allGames[0]`, `allGames[1]`, `allGames[2]` with no bounds beyond that.
**Why it happens in this codebase:** The denormalized score fields on `PersistedMatch` were designed for fast list rendering of best-of-3. Reasonable for v1.0 but brittle for format changes.
**Consequences:** If best-of-5 ever ships, games 4 and 5 are silently lost from the persisted record.
**Prevention:**
- For now (best-of-3 at 15 points), the existing fields work fine -- no migration needed
- Add a `scoringSystem: String = "standard21"` field to `PersistedMatch` (additive migration, CloudKit safe)
- If best-of-5 becomes real, migrate to a JSON array for game scores instead of fixed fields
- Do NOT add `game4ScoreA/B` and `game5ScoreA/B` preemptively -- that is speculative complexity
**When to address:** Phase 1 (add `scoringSystem` field). Best-of-5 migration only if BWF confirms it.

### Minor Pitfall 1.5: SyncPayload Does Not Carry Scoring System

**Risk Level:** MINOR but EASY TO MISS
**What goes wrong:** `SyncPayload` serializes `CodableMatchState` to a dictionary for WatchConnectivity. If `CodableMatchState` gains `scoringSystem` but `SyncPayload.toDictionary()` does not include it, the Watch receives a match but does not know it is 3x15. The Watch applies 21-point rules to a 15-point match.
**Why it happens:** `SyncPayload` likely passes through `CodableMatchState` JSON, so this may be automatic. But if it uses manual dictionary keys, it is easy to forget.
**Prevention:**
- Verify that `SyncPayload` round-trips the full `CodableMatchState` including the new field
- Write a sync round-trip test: encode on iPhone, decode on Watch, verify `scoringSystem` preserved
**When to address:** Phase 1, during sync testing.

---

## Area 2: Haptic Feedback -- iPhone (UIFeedbackGenerator / CoreHaptics) vs Watch (WKInterfaceDevice)

### Critical Pitfall 2.1: Playing Haptics on Wrong Thread / Actor

**Risk Level:** CRITICAL
**What goes wrong:** `UIImpactFeedbackGenerator` and `UINotificationFeedbackGenerator` must be prepared and triggered from the main thread. `WKInterfaceDevice.current().play(_:)` also requires the main thread on watchOS. The scoring path in `LiveMatchViewModel.scorePoint()` runs on `@MainActor` (it is an `@Observable` class), but `WatchMatchViewModel.scorePoint()` is NOT explicitly `@MainActor` -- it relies on being called from SwiftUI but the haptic call itself could be dispatched elsewhere.
**Why it happens in this codebase:** `WatchMatchViewModel` is `@Observable` but not `@MainActor`-annotated. `scorePoint()` calls `WatchSessionManager.shared.sendScoringIntent()` which is not actor-isolated. If haptics are added inside `scorePoint()` without ensuring main thread, the haptic fires on whatever thread the WCSession callback arrived on.
**Consequences:** Silent failure (haptics just do not play). No crash, no error -- the feature simply does not work, and debugging is frustrating because it works in previews (always main thread) but not from Watch session callbacks.
**Prevention:**
- Ensure haptic calls are always dispatched to `@MainActor` or wrapped in `DispatchQueue.main.async`
- On iPhone: call `generator.prepare()` when the match starts, then `generator.impactOccurred()` on each score
- On Watch: call `WKInterfaceDevice.current().play(.click)` inside a `@MainActor` closure
- Write a test that verifies haptics are called from the correct context (mock the generator)
**When to address:** Phase 2 (haptic implementation).

### Moderate Pitfall 2.2: Different Haptic APIs With No Shared Abstraction

**Risk Level:** MODERATE
**What goes wrong:** iPhone has three tiers of haptic APIs: `UIImpactFeedbackGenerator` (simple), `UINotificationFeedbackGenerator` (success/warning/error), and `CoreHaptics` (custom patterns via `CHHapticEngine`). Apple Watch has only `WKInterfaceDevice.play(_:)` with a fixed set of `WKHapticType` values (`.click`, `.directionUp`, `.success`, `.failure`, etc). There is no shared protocol. Developers build haptic logic twice with no code sharing.
**Why it happens:** The ScoringEngine package is pure (no UIKit/WatchKit). Haptic logic cannot live there. It must live in the app targets. Without an abstraction, you get copy-pasted haptic patterns in `LiveMatchViewModel` (iPhone) and `WatchMatchViewModel` (Watch) that drift.
**Consequences:** iPhone plays a success haptic on game win; Watch plays a click. Users notice the inconsistency. Or worse, one platform gets haptics and the other silently does not.
**Prevention:**
- Define a `HapticEvent` enum in the ScoringEngine package (pure, no UIKit): `.scorePoint`, `.gameWon`, `.matchWon`, `.undo`, `.sideSwitch`
- In each app target, implement a `HapticPlayer` protocol that maps `HapticEvent` to platform-specific calls
- iPhone `HapticPlayer`: `.scorePoint` -> `UIImpactFeedbackGenerator(.light)`, `.gameWon` -> `UINotificationFeedbackGenerator(.success)`, `.matchWon` -> CoreHaptics custom pattern
- Watch `HapticPlayer`: `.scorePoint` -> `.click`, `.gameWon` -> `.success`, `.matchWon` -> `.success` (limited vocabulary)
- Inject `HapticPlayer` into the view models
**When to address:** Phase 2 design, before writing any haptic code.

### Moderate Pitfall 2.3: CoreHaptics CHHapticEngine Lifecycle Mismanagement

**Risk Level:** MODERATE
**What goes wrong:** `CHHapticEngine` must be started before playing patterns and can stop itself when the app backgrounds. If you create the engine once on match start, it silently becomes invalid after the user locks their phone (common during a match). Next score tap -- no haptic, no error.
**Why it happens:** `CHHapticEngine` has a `stoppedHandler` and `resetHandler` that developers forget to implement. The engine auto-stops on backgrounding unless you set `isAutoShutdownEnabled = false` (but Apple recommends against this for battery).
**Consequences:** Haptics work for the first few points, then stop after the phone locks and unlocks. Intermittent bug that is hard to reproduce in testing.
**Prevention:**
- Set the `resetHandler` to restart the engine: `engine.resetHandler = { [weak self] in try? self?.engine.start() }`
- Set the `stoppedHandler` to log the reason and prepare for restart
- Before each haptic play, check `CHHapticEngine.capabilitiesForHardware().supportsHaptics`
- Consider using `UIImpactFeedbackGenerator` for simple score haptics and reserve CoreHaptics only for the match-win celebration pattern -- simpler lifecycle
**When to address:** Phase 2, if CoreHaptics is chosen for custom patterns.

### Minor Pitfall 2.4: Haptic Toggle State Not Synced to Watch

**Risk Level:** MINOR
**What goes wrong:** User toggles haptics off in iPhone Settings. Watch keeps playing haptics because the toggle is stored in iPhone `UserDefaults` and never sent via WatchConnectivity.
**Prevention:**
- Include haptic preference in the `applicationContext` payload sent to Watch
- Or store in a shared App Group `UserDefaults` (if using an app group)
- Simpler: make haptic toggle independent per device (user may want haptics on Watch but not iPhone during a match where they are watching from the side)
**When to address:** Phase 2, during settings implementation.

### Minor Pitfall 2.5: Haptic Fatigue in Fast-Scoring Scenarios

**Risk Level:** MINOR
**What goes wrong:** In rapid scoring (undo then re-score, or catching up after offline scoring on Watch), haptics fire for every event replay. 10 rapid haptic pulses feel like a vibrating phone, not intentional feedback.
**Prevention:**
- Debounce haptics: if two score events happen within 200ms, skip the haptic on the second
- On Watch reconnection (replaying iPhone state), do NOT play haptics for the catch-up delta
- Only play haptics for user-initiated score taps, not for state sync from the other device
**When to address:** Phase 2, during haptic implementation.

---

## Area 3: Multi-Camera Hawk Eye (AVCaptureMultiCamSession)

### Critical Pitfall 3.1: AVCaptureMultiCamSession Not Available on Most Devices

**Risk Level:** CRITICAL
**What goes wrong:** `AVCaptureMultiCamSession` requires `AVCaptureMultiCamSession.isMultiCamSupported == true`. This is only available on iPhone XS and later with A12+ chip AND specific camera hardware configurations. Even on supported devices, you cannot combine arbitrary camera pairs -- for example, dual wide-angle cameras (front + back) work, but using the telephoto and ultra-wide simultaneously may not.
**Why it happens in this codebase:** The current `VideoCaptureManager` uses `AVCaptureSession` (single camera). Swapping to `AVCaptureMultiCamSession` is not a drop-in replacement. Different initialization, different input/output configuration, and different device requirements.
**Consequences:** Feature crashes or is silently unavailable on 30-40% of the user base. If feature availability is not communicated, users subscribe to Premium expecting multi-camera and cannot use it.
**Prevention:**
- Check `AVCaptureMultiCamSession.isMultiCamSupported` at runtime before offering the feature
- Keep the existing single-camera `VideoCaptureManager` as the default. Multi-camera is an enhancement, not a replacement
- Show clear UI: "Multi-camera available on your device" vs "Your device supports single camera only"
- Do NOT require multi-camera for Hawk Eye -- it should boost confidence, not be a gate
**When to address:** Phase 3 (multi-camera), but design the feature toggle in Phase 1 settings.

### Critical Pitfall 3.2: Memory and Thermal Explosion From Dual 240fps Streams

**Risk Level:** CRITICAL
**What goes wrong:** Two cameras at 240fps means 480 frames/second flowing through the circular buffer. The existing `CircularFrameBuffer` holds 10 seconds of frames. At 240fps single camera, that is 2,400 `CMSampleBuffer` references. At dual 240fps, that is 4,800 -- and each buffer for 720p is ~1.8MB. That is 8.6GB of pixel data in the buffer window. The OS will kill the app.
**Why it happens in this codebase:** `CircularFrameBuffer` uses `var buffers: [CMSampleBuffer] = []` -- it retains every buffer in memory. This works at single-camera 240fps because eviction keeps it bounded, but the 10-second window is already aggressive. Doubling throughput doubles memory.
**Consequences:** App termination by Jetsam (out-of-memory kill). Loss of challenge footage. Bad user experience on the most premium feature.
**Prevention:**
- Do NOT run both cameras at 240fps. Run primary camera at 240fps, secondary at 120fps or 60fps (sufficient for angle validation)
- Use separate `CircularFrameBuffer` instances per camera with reduced capacity (e.g., 5 seconds each instead of 10)
- Monitor `os_proc_available_memory()` and reduce buffer capacity dynamically if memory is tight
- Consider writing secondary camera frames directly to disk via `AVAssetWriter` instead of buffering in memory
- Profile on the lowest-spec multi-cam-capable device (iPhone XS, 4GB RAM) not just iPhone 15 Pro (8GB RAM)
**When to address:** Phase 3 architecture design, before writing any multi-camera capture code.

### Critical Pitfall 3.3: Frame Synchronization Between Two Camera Streams

**Risk Level:** CRITICAL
**What goes wrong:** Two `AVCaptureVideoDataOutput` delegates fire independently on separate queues. Their `CMSampleBuffer` presentation timestamps are from the same clock but are NOT frame-aligned. The HawkEyePipeline must correlate "what did camera 1 see at time T?" with "what did camera 2 see at time T?" Naive matching by closest timestamp can pair frames that are 2-4ms apart -- enough for a shuttle moving at 400km/h to travel 20+ cm between frames.
**Why it happens:** Each camera sensor has its own exposure and readout timing. Multi-cam does not guarantee synchronized shutters unless you explicitly configure it.
**Consequences:** Trajectory reconstruction from two angles uses spatially inconsistent data. The "higher confidence" from multi-camera becomes LOWER confidence because the positions disagree.
**Prevention:**
- Use `AVCaptureDataOutputSynchronizer` to receive synchronized multi-camera frames in a single callback
- Set the primary camera's output as the master; synchronizer aligns secondary frames to primary timestamps
- Accept that synchronized frames may have slightly different exposure -- this is fine for position detection
- In `HawkEyePipeline`, process synchronized frame pairs, not independent frame streams
**When to address:** Phase 3, core implementation.

### Moderate Pitfall 3.4: HawkEyePipeline Assumes Single Video Input

**Risk Level:** MODERATE
**What goes wrong:** `HawkEyePipeline.analyze(videoURL:calibration:)` takes a single `URL` and a single `CalibrationProfile`. Multi-camera means two video files and two calibration profiles (each camera has its own perspective transform / homography). The entire pipeline signature must change.
**Why it happens in this codebase:** The pipeline was correctly designed for v1.0's single-camera use case. But the `analyze` method, `TrajectoryCalculator`, and `HawkEyeResult` all assume one perspective.
**Consequences:** Refactoring the pipeline interface after it is already integrated into `ChallengeVideoView` and the rest of the UI chain causes cascading changes.
**Prevention:**
- Design the multi-camera pipeline as a wrapper: `MultiCameraHawkEyePipeline` that runs two `HawkEyePipeline` instances (one per camera) and merges results
- Do NOT modify the existing `HawkEyePipeline.analyze()` signature -- it stays single-camera
- The merger compares two independent trajectory analyses and produces a combined confidence score
- If the two cameras disagree on in/out, use the higher-confidence result but flag the disagreement
**When to address:** Phase 3 design.

### Moderate Pitfall 3.5: Dual Calibration UX Complexity

**Risk Level:** MODERATE
**What goes wrong:** Users already find single-camera court calibration tedious (tap 4 corners). With two cameras, they must calibrate EACH camera separately. If one camera moves between calibration and challenge, its homography is wrong and the multi-camera merge produces garbage.
**Why it happens:** Physical setup complexity. Two tripods, two phone mounts, two calibration steps. Users will skip re-calibration.
**Consequences:** Multi-camera is theoretically better but practically worse because one camera's calibration drifts.
**Prevention:**
- Phase 3 should support "primary + secondary" camera roles, not require both to be calibrated independently
- Secondary camera validates the primary camera's call (agrees/disagrees) without needing its own full calibration
- Or: use a checkerboard/ArUco marker on the court for automatic calibration of the secondary camera
- Show calibration validity indicator ("last calibrated 5 min ago" vs "calibration may be stale")
**When to address:** Phase 3, UX design.

### Minor Pitfall 3.6: Multi-Cam Session Interruptions

**Risk Level:** MINOR
**What goes wrong:** `AVCaptureMultiCamSession` can be interrupted by phone calls, FaceTime, other apps acquiring the camera. The interruption handler from `AVCaptureSession` works differently -- multi-cam sessions may drop one camera input while keeping the other, leaving the pipeline in a half-working state.
**Prevention:**
- Register for `.AVCaptureSessionWasInterrupted` and `.AVCaptureSessionInterruptionEnded` notifications
- On interruption: gracefully degrade to single-camera mode if one input drops
- On interruption end: attempt to re-add the dropped input
- Never assume both cameras are active -- always check `session.connections` state
**When to address:** Phase 3, robustness pass.

---

## Area 4: SwiftData + CloudKit Migration

### Critical Pitfall 4.1: Non-Optional New Field on PersistedMatch Breaks CloudKit

**Risk Level:** CRITICAL
**What goes wrong:** Adding `var scoringSystem: String` (non-optional, no default) to `PersistedMatch` requires a migration. CloudKit lightweight migration only supports additive changes with defaults. A required field without a default value causes `NSPersistentCloudKitContainer` to fail silently -- records from v1.0 users sync down without the field, SwiftData cannot instantiate them, and the fetch returns zero results. The user's match history vanishes.
**Why it happens in this codebase:** `PersistedMatch` already uses this pattern correctly -- `var format: String = "singles"` has a default. But a developer adding `var scoringSystem: String` (forgetting the default) causes the break. SwiftData does not crash -- it just returns empty query results.
**Consequences:** Users who upgrade from v1.0 to v1.2 lose ALL match history visibility. Data is still in CloudKit but cannot be materialized. This is a silent data loss bug that only manifests on upgrade.
**Prevention:**
- ALL new fields on `PersistedMatch` MUST have default values: `var scoringSystem: String = "standard21"`
- NEVER add non-optional fields without defaults to any `@Model` that syncs with CloudKit
- NEVER rename or delete existing fields
- NEVER add relationships (CloudKit has strict relationship constraints with SwiftData)
- Test the upgrade path: install v1.0, create matches, install v1.2, verify all matches appear
**When to address:** Phase 1, when adding the `scoringSystem` field.

### Critical Pitfall 4.2: Schema Version Not Tracked -- No Migration Path

**Risk Level:** CRITICAL
**What goes wrong:** SwiftData with CloudKit does not support custom migration plans (`SchemaMigrationPlan`) when using CloudKit sync. You can only do lightweight (additive) migrations. If you need a non-lightweight migration later (e.g., splitting `PersistedMatch` into separate models for different scoring systems), there is no clean path.
**Why it happens:** This is a known SwiftData + CloudKit limitation. The CloudKit schema is append-only. You cannot remove or rename columns in the CloudKit schema.
**Consequences:** Technical debt accumulates on `PersistedMatch`. Every new feature adds more optional fields. The model becomes a grab-bag.
**Prevention:**
- Accept the append-only constraint. Add `scoringSystem` as a new field. Do not try to restructure.
- Document the schema version in a comment: `// Schema v2: added scoringSystem (v1.2)`
- If complex structure is needed later, add it as a JSON blob in a `Data` field (like `stateJSON` already does) rather than new columns
- Keep `PersistedMatch` flat and denormalized -- this is the right pattern for CloudKit
**When to address:** Phase 1, architecture decision.

### Moderate Pitfall 4.3: game3Score Fields Semantics Change for 3x15

**Risk Level:** MODERATE
**What goes wrong:** `game1ScoreA`/`game1ScoreB` etc. are used for fast list rendering. With 3x15 format, game 1 max is 17 (at cap) not 30. The UI must know which scoring system to interpret the scores correctly. If `MatchHistoryView` shows "15-12" it is ambiguous -- was that a completed game (3x15) or an in-progress game (standard 21)?
**Prevention:**
- With the `scoringSystem` field on `PersistedMatch`, the UI can determine context
- Show the scoring format badge on match history entries: "21-pt" or "15-pt"
- `isComplete` flag already disambiguates in-progress vs finished
**When to address:** Phase 2, UI updates for match history.

---

## Area 5: Cross-Cutting Integration Pitfalls

### Critical Pitfall 5.1: WatchConnectivity Payload Size With Multi-Camera State

**Risk Level:** HIGH
**What goes wrong:** `WatchConnectivity.sendMessage()` and `updateApplicationContext()` have payload size limits. `applicationContext` replaces the entire context each time (max ~256KB). If multi-camera state, calibration profiles for two cameras, and match state are all shoved into the sync payload, it may exceed limits or become slow to serialize.
**Why it happens in this codebase:** Currently `SyncPayload.toDictionary()` sends match state, which is small. But if camera status, calibration validity, or multi-camera metadata is added, the payload grows.
**Prevention:**
- Do NOT send camera/Hawk Eye state via WatchConnectivity -- the Watch does not need it
- Keep the sync payload exclusively about scoring state
- If haptic preferences need syncing, send as a separate `applicationContext` key (small)
**When to address:** Phase 2/3, when integrating new features with sync.

### Moderate Pitfall 5.2: Live Activity ContentState Does Not Reflect Scoring System

**Risk Level:** MODERATE
**What goes wrong:** `MatchActivityAttributes.ContentState` shows `scoreA`, `scoreB`, `gameNumber`. On the lock screen, a score of "15-12" with no format indicator is confusing -- is the game almost over (3x15) or barely started (standard 21)?
**Prevention:**
- Add `scoringSystem` or `pointsToWin` to `MatchActivityAttributes` so the Live Activity can show context
- Or add a simple label: "Game 2 of 3 (to 15)"
**When to address:** Phase 2, when updating Live Activity for 3x15.

### Moderate Pitfall 5.3: Feature Flag Explosion

**Risk Level:** MODERATE
**What goes wrong:** Three new features (haptics, 3x15, multi-camera) each need toggles/settings. If they are all jammed into `SettingsView` without organization, the UI becomes cluttered. If they are feature-flagged with booleans scattered across `UserDefaults`, the settings state becomes unmanageable.
**Prevention:**
- Group settings: "Match Settings" (scoring format choice), "Feedback" (haptic toggle), "Hawk Eye" (multi-camera toggle)
- Use a single `AppSettings` observable object that wraps `UserDefaults`/`@AppStorage`
- Haptic toggle: per-device (no sync needed)
- Scoring format: per-match (set in `MatchSetupView`, not global)
- Multi-camera: gated behind device capability check
**When to address:** Phase 1 settings architecture.

### Minor Pitfall 5.4: MatchSetupView Must Add Scoring Format Picker Without Breaking Flow

**Risk Level:** MINOR
**What goes wrong:** `MatchSetupView` currently has Format (singles/doubles/mixed) -> Player Names -> Start Match. Adding a scoring system picker adds another decision point. If placed poorly, it interrupts the fast "tap-tap-start" flow that casual users need.
**Prevention:**
- Add scoring system as a segmented control directly below format picker: `21-point | 15-point`
- Default to 21-point (most users will not change this until BWF officially adopts 3x15)
- Do NOT put it in a separate screen or expandable section
**When to address:** Phase 2, UI implementation.

---

## Phase-Specific Warnings

| Phase | Feature | Likely Pitfall | Severity | Mitigation |
|-------|---------|---------------|----------|------------|
| 1 | ScoringEngine refactor | Hardcoded magic numbers (1.1) | CRITICAL | Extract ScoringRules struct first |
| 1 | ScoringEngine refactor | CodableMatchState missing new field (1.2) | CRITICAL | Add with default, test v1.0 JSON compat |
| 1 | SwiftData migration | Non-optional field breaks CloudKit (4.1) | CRITICAL | Default value on ALL new fields |
| 1 | SwiftData migration | No migration path for future (4.2) | CRITICAL | Accept append-only, document schema version |
| 2 | Haptic feedback | Wrong thread haptic calls (2.1) | CRITICAL | @MainActor all haptic calls |
| 2 | Haptic feedback | No shared abstraction (2.2) | MODERATE | HapticEvent enum in ScoringEngine package |
| 2 | Haptic feedback | CHHapticEngine lifecycle (2.3) | MODERATE | Use UIFeedbackGenerator for simple cases |
| 2 | Haptic feedback | Haptic fatigue on rapid events (2.5) | MINOR | Debounce, skip sync-originated events |
| 3 | Multi-camera | Device compatibility (3.1) | CRITICAL | Runtime check, graceful fallback |
| 3 | Multi-camera | Memory from dual streams (3.2) | CRITICAL | Asymmetric FPS, separate buffers, profile on XS |
| 3 | Multi-camera | Frame sync (3.3) | CRITICAL | AVCaptureDataOutputSynchronizer |
| 3 | Multi-camera | Pipeline assumes single input (3.4) | MODERATE | Wrapper pattern, do not modify existing pipeline |
| 3 | Multi-camera | Dual calibration UX (3.5) | MODERATE | Primary + validator pattern |

## Warning Signs Checklist

Use these during development to detect pitfalls early:

- [ ] Any hardcoded `21`, `20`, `29`, `30`, or `11` in scoring logic -> Pitfall 1.1
- [ ] `CodableMatchState` has fewer fields than `MatchState` -> Pitfall 1.2
- [ ] New `@Model` field without `= defaultValue` -> Pitfall 4.1
- [ ] Haptic call not wrapped in `@MainActor` or `DispatchQueue.main` -> Pitfall 2.1
- [ ] `CHHapticEngine` created without `resetHandler` -> Pitfall 2.3
- [ ] `CircularFrameBuffer` total memory > 500MB in Instruments -> Pitfall 3.2
- [ ] Two `captureOutput` delegates firing independently (no synchronizer) -> Pitfall 3.3
- [ ] WatchConnectivity payload > 100KB -> Pitfall 5.1
- [ ] Match history shows score without format context -> Pitfall 4.3 / 5.2

## Sources

- Codebase analysis: `ScoringEngine/Sources/ScoringEngine/BWFRules.swift` (hardcoded rule constants)
- Codebase analysis: `ScoringEngine/Sources/ScoringEngine/MatchState.swift` (struct layout, factory methods)
- Codebase analysis: `BadmintonEye/Models/CodableMatchState.swift` (manual Codable mirror)
- Codebase analysis: `BadmintonEye/Models/SwiftDataModels.swift` (PersistedMatch schema)
- Codebase analysis: `BadmintonEye/Services/VideoCaptureManager.swift` (AVCaptureSession usage)
- Codebase analysis: `BadmintonEye/Services/CircularFrameBuffer.swift` (CMSampleBuffer retention)
- Codebase analysis: `BadmintonEye/Services/HawkEyePipeline.swift` (single video URL signature)
- Codebase analysis: `BadmintonEye/Services/WatchSyncManager.swift` (sync payload pattern)
- Codebase analysis: `BadmintonEyeWatch/ViewModels/WatchMatchViewModel.swift` (no @MainActor, offline scoring)
- Apple AVCaptureMultiCamSession documentation (training data, MEDIUM confidence)
- Apple CoreHaptics CHHapticEngine lifecycle (training data, MEDIUM confidence)
- Apple WKInterfaceDevice haptic types (training data, HIGH confidence -- stable API)
- SwiftData + CloudKit migration constraints (training data, HIGH confidence -- well-documented limitation)
