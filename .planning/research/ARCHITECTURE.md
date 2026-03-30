# Architecture Patterns: v1.2 Haptic Feedback, BWF 3x15 Scoring, Multi-Camera Hawk Eye

**Domain:** iOS badminton scoring app with AI line calling
**Researched:** 2026-03-29
**Confidence:** HIGH (based on direct codebase analysis and Apple framework knowledge)

## Integration Map

```
Feature 1: HAPTIC FEEDBACK
  LiveMatchViewModel.scorePoint()  -->  [NEW] HapticFeedbackService
  WatchMatchViewModel.scorePoint() -->  WKInterfaceDevice.current().play(.success)
  SettingsView                     -->  [MODIFIED] haptic toggle in UserDefaults/AppStorage

Feature 2: BWF 3x15 SCORING
  MatchState (ScoringEngine)       -->  [MODIFIED] add ScoringSystem enum
  BWFRules.swift                   -->  [MODIFIED] parameterized thresholds
  MatchEngine.swift                -->  [MODIFIED] best-of-5 game transitions
  MatchSetupView                   -->  [MODIFIED] scoring format picker
  CodableMatchState                -->  [MODIFIED] encode ScoringSystem
  SyncPayload                      -->  cascades from CodableMatchState
  PersistedMatch                   -->  [MODIFIED] game4/game5 score fields
  LiveActivity                     -->  [MODIFIED] display up to 5 games won

Feature 3: MULTI-CAMERA HAWK EYE
  [NEW] MultiCamSessionManager     -->  AVCaptureMultiCamSession
  [NEW] CameraAngle enum           -->  identifies primary/secondary angles
  [NEW] MultiAngleBuffer           -->  synchronized CircularFrameBuffers per camera
  HawkEyePipeline                  -->  [MODIFIED] accept multiple video sources
  TrajectoryCalculator             -->  [MODIFIED] multi-view triangulation
  CalibrationProfile               -->  [MODIFIED] per-camera calibration data
  ChallengeVideoView               -->  [MODIFIED] angle switcher UI
```

## New Components

### 1. HapticFeedbackService (Services/)

**Responsibility:** Centralized haptic playback for score events on iOS. Uses UIImpactFeedbackGenerator for standard taps and Core Haptics (CHHapticEngine) for richer patterns on score, game win, and match win.

**Why a separate service:** Haptic patterns differ by event type (point scored vs game won vs match won). Encapsulating this avoids scattering UIKit haptic calls across ViewModels. Also enables future customization of haptic intensity.

**Interface:**
```swift
import CoreHaptics
import UIKit

final class HapticFeedbackService {
    static let shared = HapticFeedbackService()

    private var engine: CHHapticEngine?
    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)

    /// Whether haptics are enabled (reads from UserDefaults).
    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "hapticFeedbackEnabled")
    }

    func playScorePoint() { ... }
    func playGameWon() { ... }
    func playMatchWon() { ... }

    private func prepareEngineIfNeeded() { ... }
}
```

**Key decisions:**
- Use `UIImpactFeedbackGenerator` for basic point-scored feedback (simple, low latency, no engine setup).
- Use `CHHapticEngine` only for game-won and match-won patterns (sustained vibration patterns that UIFeedbackGenerator cannot produce).
- Prepare the engine lazily on first use -- CHHapticEngine is expensive to create.
- Check `CHHapticEngine.capabilitiesForHardware().supportsHaptics` before attempting Core Haptics; fall back to UINotificationFeedbackGenerator on devices without Taptic Engine.
- Single `@AppStorage("hapticFeedbackEnabled")` toggle, defaulting to `true`.

**watchOS counterpart:** No new service needed. `WKInterfaceDevice.current().play(.success)` for point scored, `.notification` for game/match end. Two lines added to `WatchMatchViewModel.scorePoint()`.

### 2. ScoringSystem Enum (ScoringEngine/Types.swift)

**Responsibility:** Distinguishes between BWF 3x21 (current default) and BWF 3x15 (proposed new format) at the type level.

```swift
public enum ScoringSystem: String, Codable, Sendable, Equatable {
    case threeByTwentyOne  // Best of 3, play to 21, deuce at 20, cap at 30
    case threeByFifteen    // Best of 3, play to 15, deuce at 14, cap at 21 (BWF proposal)
}
```

**Why an enum, not a config struct:** The two formats differ in exactly 3 numeric thresholds (game point, deuce threshold, cap). An enum with computed properties is cleaner than a freeform config object and prevents invalid combinations. If BWF adopts further variations, new cases can be added without breaking existing match persistence.

### 3. MultiCamSessionManager (Services/)

**Responsibility:** Manages `AVCaptureMultiCamSession` for simultaneous capture from two cameras. Provides synchronized frame streams from each angle.

**Key architecture decisions:**

- `AVCaptureMultiCamSession` is available on iPhone XS and later (A12+ chip). It allows simultaneous capture from multiple cameras (e.g., wide + ultra-wide, or wide + front). On devices that do not support multi-cam, gracefully fall back to single-camera mode via the existing `VideoCaptureManager`.
- Each camera gets its own `AVCaptureVideoDataOutput` and `CircularFrameBuffer`.
- Frame synchronization uses presentation timestamps (PTS) -- frames from different cameras are correlated by nearest PTS within a tolerance window (e.g., 8ms at 120fps).
- Multi-cam limits FPS per stream. On iPhone 15 Pro, two cameras can each run at 120fps but not 240fps simultaneously. The architecture must negotiate the best available FPS per camera.

**Interface:**
```swift
enum CameraAngle: String, Codable, Sendable {
    case primary    // Main court-side camera (wide angle)
    case secondary  // Second angle (ultra-wide or opposite side)
}

@Observable
final class MultiCamSessionManager: NSObject, @unchecked Sendable {
    var isMultiCamSupported: Bool { AVCaptureMultiCamSession.isMultiCamSupported }
    var activeCameras: [CameraAngle] = []
    var currentFPS: [CameraAngle: Double] = [:]

    func startCapture(cameras: [CameraAngle]) { ... }
    func stopCapture() { ... }
    func saveBuffersToDisk() async throws -> [CameraAngle: URL] { ... }

    // Delegate pattern: frame delivery per angle
    var onFrame: ((CameraAngle, CMSampleBuffer) -> Void)?
}
```

### 4. MultiAngleAnalysisResult (within HawkEyePipeline)

**Responsibility:** Wraps per-angle HawkEyeResults and the fused multi-angle result with overall confidence.

```swift
struct MultiAngleAnalysisResult {
    let perAngle: [CameraAngle: HawkEyeResult]
    let fusedResult: HawkEyeResult       // Triangulated from multiple views
    let confidenceBoost: Double           // How much multi-angle improved confidence
    let agreementScore: Double            // 0-1, do angles agree on IN/OUT?
}
```

## Modified Components

### 1. MatchState (ScoringEngine) -- MODERATE changes

**What changes:**
- Add `scoringSystem: ScoringSystem` stored property (default: `.threeByTwentyOne`).
- Factory methods gain `scoringSystem:` parameter.
- `Equatable` conformance includes `scoringSystem`.

**What does NOT change:** `GameState`, `MatchPhase`, `Side`, `Court`, `PlayerPosition`, `MatchEvent` -- all unchanged.

### 2. BWFRules.swift -- MODERATE changes

**What changes:** Every threshold becomes parameterized by `scoringSystem`.

| Property | 3x21 | 3x15 |
|----------|-------|------|
| `isDeuce` | both >= 20 | both >= 14 |
| `isAtCap` | both == 29 | both == 20 |
| `isGameWon` | >= 21 with 2-pt lead, or 30 | >= 15 with 2-pt lead, or 21 |
| `isMatchComplete` | 2 games won | 2 games won (same) |
| `shouldSwitchSides` | at 11 in 3rd game | at 8 in 3rd game (proportional) |

**Implementation approach:** Add private computed thresholds:
```swift
private var gamePoint: Int {
    scoringSystem == .threeByFifteen ? 15 : 21
}
private var deuceThreshold: Int {
    scoringSystem == .threeByFifteen ? 14 : 20
}
private var capScore: Int {
    scoringSystem == .threeByFifteen ? 21 : 30
}
private var midGameSwitch: Int {
    scoringSystem == .threeByFifteen ? 8 : 11
}
```

Then rewrite `isDeuce`, `isAtCap`, `isGameWon`, and `shouldSwitchSides` to use these thresholds. The best-of-3 structure (2 games to win) stays the same for both formats.

**Note on BWF 3x15 mid-game interval:** The proposed BWF 3x15 format may include a 60-second interval when the leading score reaches 8 (similar to the interval at 11 in 3x21). This does not affect scoring logic -- it is a UI concern (show interval overlay). The `shouldSwitchSides` logic at midpoint can double as the interval trigger.

### 3. MatchEngine.swift -- SMALL changes

**What changes:** No structural changes. The `applyScorePoint` function already delegates game-won checks to `isGameWon` and match-complete checks to `isMatchComplete`. Since those are parameterized in BWFRules.swift, MatchEngine automatically works with 3x15.

**One edge case:** The `resetServiceForNewGame` function is called when `!isMatchComplete` after a game win. Since both formats are best-of-3, this logic is unchanged.

### 4. CodableMatchState -- SMALL changes

**What changes:** Add `scoringSystem` field. Must handle backward compatibility -- matches serialized before v1.2 lack this field, so decode with a default of `.threeByTwentyOne`.

```swift
var scoringSystem: ScoringSystem

init(from state: MatchState) {
    // ... existing fields ...
    self.scoringSystem = state.scoringSystem
}

// Custom Decodable for backward compat:
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.scoringSystem = try container.decodeIfPresent(ScoringSystem.self,
        forKey: .scoringSystem) ?? .threeByTwentyOne
    // ... rest of fields ...
}
```

### 5. MatchSetupView -- MODERATE changes

**What changes:** Add a scoring system picker in the "Match Format" section:
```swift
Section("Scoring") {
    Picker("System", selection: $selectedScoringSystem) {
        Text("21-point (standard)").tag(ScoringSystem.threeByTwentyOne)
        Text("15-point (BWF new)").tag(ScoringSystem.threeByFifteen)
    }
}
```

Pass `scoringSystem` through to `MatchState` factory methods.

### 6. PersistedMatch -- SMALL changes

**What changes:**
- Add `scoringSystem: String = "threeByTwentyOne"` field.
- Game 4 and Game 5 score fields are NOT needed because both 3x21 and 3x15 are best-of-3. Maximum 3 games. The existing `game1ScoreA/B`, `game2ScoreA/B`, `game3ScoreA/B` fields suffice.

### 7. LiveMatchViewModel -- SMALL changes

**What changes:**
- After `scorePoint()`, call `HapticFeedbackService.shared.playScorePoint()`.
- After game end detection, call `.playGameWon()`.
- After match complete, call `.playMatchWon()`.
- Three lines of code total.

### 8. SettingsView -- SMALL changes

**What changes:** Add a "Haptic Feedback" toggle in a new section:
```swift
Section("Match Experience") {
    Toggle("Haptic Feedback", isOn: $hapticEnabled)
}
```
Using `@AppStorage("hapticFeedbackEnabled") private var hapticEnabled = true`.

### 9. HawkEyePipeline -- MODERATE changes

**What changes:**
- Add a new `analyze(videos: [CameraAngle: URL], calibrations: [CameraAngle: CalibrationProfile])` method that runs the existing single-camera analysis per angle, then fuses results.
- The existing `analyze(videoURL:calibration:)` method stays as-is for single-camera fallback.
- Fusion logic: if both angles agree (both IN or both OUT), confidence = max(angle1, angle2) + agreementBonus. If they disagree, confidence = min(angle1, angle2) * 0.5, result = `.uncertain`.

### 10. CalibrationProfile -- MODERATE changes

**What changes:**
- Add `cameraAngle: String = "primary"` field to identify which camera this calibration belongs to.
- A venue may have multiple CalibrationProfiles -- one per camera angle.
- Query becomes: `#Predicate<CalibrationProfile> { $0.venueName == venueName && $0.cameraAngle == angle }`.

### 11. TrajectoryCalculator -- SMALL changes for multi-view

**What changes:**
- Add `fuseTrajectories(_ results: [HawkEyeResult]) -> HawkEyeResult` method.
- Simple fusion: weight landing points by confidence, compute weighted average. If landing results disagree, mark as `.uncertain`.
- More sophisticated triangulation (epipolar geometry) is a v2 concern. For v1.2, independent per-angle analysis with confidence-weighted fusion is sufficient and testable.

### 12. LiveActivity -- SMALL changes

**What changes:** The `MatchActivityAttributes.ContentState` already uses `gamesWonA`/`gamesWonB` integers. No changes needed for 3x15 -- the numbers just represent different game point totals. The display logic ("Game 2 of 3") stays identical.

### 13. WatchMatchViewModel -- SMALL changes

**What changes:**
- Add haptic feedback calls: `WKInterfaceDevice.current().play(.success)` after local scoring.
- `CodableMatchState` changes cascade automatically -- Watch decodes the new `scoringSystem` field and passes it through.
- No Watch UI changes needed -- the Watch shows scores and game numbers, which work identically for both formats.

### 14. SyncPayload -- NO changes

The `SyncPayload` wraps `CodableMatchState` generically. Adding `scoringSystem` to `CodableMatchState` flows through automatically.

## Component Dependency Graph

```
                    ScoringSystem (new enum)
                         |
            +------------+------------+
            |            |            |
       MatchState   BWFRules    MatchEngine
       (modified)  (modified)  (unchanged logic,
            |                   uses BWFRules)
            |
     CodableMatchState (modified)
            |
    +-------+-------+
    |               |
SyncPayload    PersistedMatch
(no change)    (add scoringSystem field)
    |
WatchMatchViewModel
(haptics added)

HapticFeedbackService (new) <-- LiveMatchViewModel (modified)
                             <-- WatchMatchViewModel (modified)

MultiCamSessionManager (new) --> CircularFrameBuffer (per camera)
         |
         v
  HawkEyePipeline (modified) --> TrajectoryCalculator (modified)
         |
CalibrationProfile (modified, per-camera)
```

## Build Order

The three features have specific dependency relationships that determine build order.

### Phase 1: BWF 3x15 Scoring (build first)

**Rationale:** This touches the ScoringEngine pure Swift package, which is the foundation of the app. Changes here cascade to CodableMatchState, SyncPayload (implicitly), PersistedMatch, and UI. Building this first ensures the state machine is stable before adding side-effect features.

**Build sequence within phase:**
1. Add `ScoringSystem` enum to `Types.swift`
2. Add `scoringSystem` property to `MatchState`, update factory methods
3. Parameterize thresholds in `BWFRules.swift`
4. Update `CodableMatchState` with backward-compatible decoding
5. Add `scoringSystem` field to `PersistedMatch`
6. Update `MatchSetupView` with scoring system picker
7. Write exhaustive unit tests (duplicate existing test suites with 3x15 thresholds)

**Dependencies:** None. Self-contained in ScoringEngine + UI layer.

**Risk:** LOW. Pure value-type transformations. Exhaustively testable. No async, no hardware, no side effects.

### Phase 2: Haptic Feedback (build second)

**Rationale:** Haptic feedback is a thin layer on top of the scoring flow. It requires the scoring system to be finalized (Phase 1) because haptic patterns fire on score events, game ends, and match ends -- events whose thresholds differ between 3x21 and 3x15.

**Build sequence within phase:**
1. Create `HapticFeedbackService` with `UIImpactFeedbackGenerator` for points
2. Add Core Haptics patterns for game-won and match-won
3. Wire into `LiveMatchViewModel.scorePoint()` / game-end / match-end
4. Add `@AppStorage` toggle in `SettingsView`
5. Add `WKInterfaceDevice.play()` calls in `WatchMatchViewModel`
6. Test on device (haptics cannot be tested in simulator)

**Dependencies:** Phase 1 (scoring events must be stable).

**Risk:** LOW. UIKit/Core Haptics APIs are stable and well-documented. Main risk is haptic pattern tuning (subjective, requires real-device testing).

### Phase 3: Multi-Camera Hawk Eye (build last)

**Rationale:** This is the most complex feature and touches the camera/ML pipeline. It has zero dependencies on Phase 1 (scoring) or Phase 2 (haptics) -- it is architecturally independent. However, it should be built last because:
- Highest complexity and risk (hardware-dependent, async, multi-stream synchronization).
- Requires real multi-camera device testing (cannot validate in simulator).
- The scoring and haptic features deliver user value quickly while this is in development.
- If v1.2 needs to ship early, Phase 1 + Phase 2 can ship without Phase 3.

**Build sequence within phase:**
1. Add `CameraAngle` enum and `cameraAngle` field to `CalibrationProfile`
2. Build `MultiCamSessionManager` with `AVCaptureMultiCamSession`
3. Add per-camera `CircularFrameBuffer` management
4. Add `fuseTrajectories()` to `TrajectoryCalculator`
5. Add multi-angle `analyze()` method to `HawkEyePipeline`
6. Update `CourtCalibrationView` for per-camera calibration
7. Update `ChallengeVideoView` with angle switcher
8. Add fallback path: if device does not support multi-cam, use existing single-camera flow unchanged

**Dependencies:** None on Phase 1 or 2. Internal dependency: CalibrationProfile changes before Pipeline changes.

**Risk:** MEDIUM.
- `AVCaptureMultiCamSession` has device-specific limitations on simultaneous resolution and FPS.
- Frame synchronization across cameras requires careful PTS correlation.
- CalibrationProfile schema change needs SwiftData lightweight migration.
- Fusion algorithm quality is hard to validate without real multi-angle footage.

## Anti-Patterns to Avoid

### Anti-Pattern 1: Scoring System as Global Setting

**What:** Storing 3x15 vs 3x21 as a global app preference instead of per-match.
**Why bad:** A user may play a 3x21 match in the morning and a 3x15 match in the evening. Historical matches must retain their original scoring system for correct score display and stat calculation.
**Instead:** Store `scoringSystem` on `MatchState` (and thus `PersistedMatch`). The setup screen picks the system; it travels with the match forever.

### Anti-Pattern 2: Haptics in the ScoringEngine Package

**What:** Adding haptic feedback triggers inside the pure Swift ScoringEngine.
**Why bad:** ScoringEngine is a pure, platform-independent package shared between iOS and watchOS. UIKit (UIImpactFeedbackGenerator) and WatchKit (WKInterfaceDevice) are platform-specific. Importing them would break the clean package boundary.
**Instead:** Haptics are a side effect triggered by the ViewModel layer after applying state transitions.

### Anti-Pattern 3: Shared AVCaptureSession for Multi-Camera

**What:** Trying to add two camera inputs to a regular `AVCaptureSession`.
**Why bad:** `AVCaptureSession` supports only one camera input at a time. Adding a second silently fails or crashes.
**Instead:** Use `AVCaptureMultiCamSession` (requires A12+ chip) which explicitly supports multiple simultaneous camera inputs. Check `AVCaptureMultiCamSession.isMultiCamSupported` and fall back to single-camera.

### Anti-Pattern 4: Breaking CodableMatchState Backward Compatibility

**What:** Adding required fields to `CodableMatchState` without defaults.
**Why bad:** Existing persisted matches (stateJSON in SwiftData) were encoded without `scoringSystem`. Decoding them with a required field throws and crashes the app on update.
**Instead:** Use `decodeIfPresent` with a default of `.threeByTwentyOne` for all new fields.

## Patterns to Follow

### Pattern 1: Parameterized Rules via Stored Enum

**What:** Store a `ScoringSystem` enum on `MatchState` and derive all scoring thresholds from it via computed properties.
**When:** Any time game rules vary by configuration but the state machine structure is identical.
**Why:** Keeps the state machine unified (one `MatchEngine.apply()`) while supporting multiple rule sets. No branching in the engine -- only the threshold values change.

### Pattern 2: Side-Effect Layer in ViewModel

**What:** All side effects (haptics, persistence, sync, Live Activity) live in the ViewModel layer, triggered after pure state transitions from the engine.
**When:** Always. This is the existing pattern and must be maintained.
**Why:** The ScoringEngine remains pure and testable. Side effects are explicit and ordered.

### Pattern 3: Multi-Camera Graceful Degradation

**What:** Design multi-camera as an enhancement layer that falls back to single-camera transparently.
**When:** Any feature that depends on hardware capabilities varying across devices.
**Why:** Users on older devices (pre-A12) or with only one calibrated camera should get the same Hawk Eye experience they had in v1.0/v1.1. Multi-camera is additive confidence, not a requirement.

### Pattern 4: Confidence-Weighted Fusion

**What:** When multiple data sources provide independent estimates (two camera angles), combine them by weighting each estimate by its confidence score rather than simple averaging.
**When:** Multi-camera Hawk Eye result fusion.
**Why:** A clear shot from one angle (high confidence) should dominate over an occluded shot from another angle (low confidence). Equal weighting would degrade the good estimate.

## Scalability Considerations

| Concern | v1.0-1.1 | v1.2 | Future |
|---------|----------|------|--------|
| Scoring formats | Single (3x21) | Two (3x21, 3x15) | Enum extensible for any future BWF format |
| Camera streams | Single | Dual simultaneous | Could extend to external cameras via NDI/RTSP |
| Haptic patterns | None | 3 patterns (point, game, match) | Custom patterns per user preference |
| CalibrationProfiles | One per venue | One per venue per camera | Auto-calibration via court line detection |
| Frame buffers | 1 CircularFrameBuffer | 2 (one per camera) | Memory pressure: 2x buffer at 120fps = ~3.6GB/10s at 720p |

## Sources

- Direct codebase analysis: all 55 Swift source files read
- Apple AVCaptureMultiCamSession documentation (training data, MEDIUM confidence -- API available since iOS 13, well-established)
- Apple Core Haptics / UIFeedbackGenerator documentation (training data, HIGH confidence -- stable APIs since iOS 13/10 respectively)
- BWF 3x15 scoring proposal (training data, MEDIUM confidence -- details of deuce/cap thresholds may differ from final BWF ratification; flag for verification when BWF publishes final rules)
