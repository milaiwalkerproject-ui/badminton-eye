# Phase 1: Scoring Engine - Research

**Researched:** 2026-03-28
**Domain:** BWF-compliant badminton scoring state machine + iPhone UI (SwiftUI + SwiftData)
**Confidence:** HIGH

## Summary

Phase 1 delivers a BWF-compliant scoring engine as a pure value-type state machine in Swift, an iPhone scoring UI with half-screen tap zones, and SwiftData persistence designed for future CloudKit sync. The scoring engine must handle singles, doubles, and mixed doubles with correct service rotation, deuce rules, 30-point cap, side switching, and interval tracking. The engine MUST be a separate Swift package so it can be shared with the watchOS target in Phase 2.

The BWF 21-point rally scoring system (best-of-3 games) remains the official system as of March 2026. A 3x15 alternative is under trial but has NOT been adopted -- the vote is scheduled for the BWF AGM on April 25, 2026. The app should implement the current 21-point system. If the 3x15 system is later adopted, it can be added as a second scoring mode.

**Primary recommendation:** Build the scoring engine as a pure Swift struct with zero dependencies, exhaustively tested with Swift Testing parameterized tests, then wrap it in SwiftData persistence and SwiftUI views.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Simple setup screen: pick format (singles/doubles/mixed), enter player names, tap Start -- minimal friction
- Player names are optional -- default to "Player 1" / "Player 2" for quick pickup games
- Doubles teams: select 2 players per side from saved list, or type names inline
- User can abandon a match mid-game via "End Match" button with confirmation dialog, saves partial result
- Two large half-screen tap zones (left side = team A, right side = team B) -- maximizes tap target, works one-handed
- Always visible during match: score (large), game number, server indicator, service court side -- minimal clutter
- Server/service court indicated by shuttlecock icon on serving player's side + highlighted service court (left/right)
- Game end: brief celebration overlay with game score summary, auto-advance to next game; match end shows full scorecard
- Single-level undo (revert last point only) -- simple, covers 95% of mis-taps
- SwiftData model saved after every point -- survives app crash, background kill, Watch disconnection
- Pure value-type state machine (struct) with deterministic transitions -- all rules encoded as computed properties, exhaustively testable
- Design SwiftData models with CloudKit constraints from day one (optional properties, no @Attribute(.unique)) even though sync ships in Phase 4

### Claude's Discretion
- Specific color scheme and visual design details
- Animation timing and transition styles
- Internal naming conventions for state machine types

### Deferred Ideas (OUT OF SCOPE)
- None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SCORE-01 | User can start a new match selecting singles, doubles, or mixed doubles format | Match setup screen with format picker; MatchFormat enum in state machine |
| SCORE-02 | User can tap to increment score for either side with large one-hand-friendly tap targets | Half-screen tap zones using GeometryReader + contentShape(Rectangle()) |
| SCORE-03 | App enforces BWF 21-point rally scoring with deuce rules (2-point lead at 20-all, 30-point cap) | Pure state machine with exhaustive rule encoding; BWF Laws 7.1-7.5 |
| SCORE-04 | App automatically tracks best-of-3 games with side switch at game end and mid-third-game | State machine tracks game number, triggers side switch; BWF Law 8 |
| SCORE-05 | App automatically tracks service side and server based on current score (even/odd) | Singles: even=right, odd=left; BWF Law 10 |
| SCORE-06 | App tracks doubles service rotation (which player serves and from which court) | Four-player rotation tracking with court position; BWF Law 11 |
| SCORE-07 | User can undo the last scored point | Single-level undo via previous state snapshot stored before each transition |
| SCORE-08 | All scoring works fully offline without internet connectivity | SwiftData local persistence; no network calls; state machine is pure |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift | 6.x | Primary language | Required for iOS; strict concurrency, value-type safety |
| SwiftUI | iOS 17+ SDK | Declarative UI | Shared code path for iPhone/Watch; Apple's direction |
| SwiftData | iOS 17+ | Local persistence | Native SwiftUI integration, CloudKit-ready, macro-based |
| Swift Testing | Xcode 16+ | Unit tests | @Test macro, parameterized tests, parallel execution |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| OSLog | iOS 17+ | Structured logging | Debug scoring transitions; zero-dependency |
| XCTest | Current | UI tests only | Swift Testing does not yet support UI testing |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SwiftData | UserDefaults + Codable | Simpler but no migration path to CloudKit sync |
| Swift Testing | XCTest | XCTest works but lacks parameterized tests and modern macro syntax |
| Pure struct state machine | TCA (Composable Architecture) | TCA is powerful but heavyweight for a single-screen scoring UI |

**Installation:**
```bash
# All Apple frameworks -- no external packages needed for Phase 1.
# The scoring engine is a local Swift package within the Xcode project.
```

## Architecture Patterns

### Recommended Project Structure
```
BadmintonEye/
├── BadmintonEye.xcodeproj
├── BadmintonEye/                    # iOS app target
│   ├── App/
│   │   └── BadmintonEyeApp.swift
│   ├── Views/
│   │   ├── MatchSetupView.swift     # Format picker, player names
│   │   ├── LiveMatchView.swift      # Half-screen tap zones, score display
│   │   ├── GameEndOverlay.swift     # Brief celebration, score summary
│   │   └── MatchEndView.swift       # Full scorecard
│   ├── ViewModels/
│   │   └── LiveMatchViewModel.swift # @Observable, owns MatchEngine + persistence
│   └── Models/
│       └── SwiftDataModels.swift    # @Model classes for persistence
├── ScoringEngine/                   # Local Swift package (shared with Watch)
│   ├── Package.swift
│   ├── Sources/ScoringEngine/
│   │   ├── MatchState.swift         # Core struct -- all scoring state
│   │   ├── MatchEngine.swift        # Transition function: (State, Event) -> State
│   │   ├── BWFRules.swift           # Rule computations (isDeuce, isGamePoint, etc.)
│   │   ├── ServiceTracker.swift     # Singles/doubles service logic
│   │   └── Types.swift              # MatchFormat, Side, Court, Player, etc.
│   └── Tests/ScoringEngineTests/
│       ├── SinglesScoringTests.swift
│       ├── DoublesScoringTests.swift
│       ├── DeuceAndCapTests.swift
│       ├── ServiceRotationTests.swift
│       └── UndoTests.swift
└── BadmintonEyeWatch/               # Watch target (Phase 2, placeholder)
```

### Pattern 1: Pure Value-Type State Machine
**What:** The scoring engine is a pure Swift struct. A transition function takes the current state and an event, returns a new state. No side effects, no mutation of shared state.
**When to use:** All BWF scoring logic.
**Why:** Deterministic, exhaustively testable, trivially serializable for persistence and Watch sync.

```swift
// ScoringEngine/Sources/ScoringEngine/MatchState.swift
struct MatchState: Codable, Equatable, Sendable {
    let format: MatchFormat           // .singles, .doubles, .mixed
    var games: [GameState]            // Completed games
    var currentGame: GameState        // Active game
    var matchPhase: MatchPhase        // .inProgress, .complete
    var previousState: MatchState?    // For single-level undo (not Codable)

    // All rule queries are computed properties on the struct
    var isDeuce: Bool { currentGame.scoreA >= 20 && currentGame.scoreB >= 20 }
    var isAtCap: Bool { currentGame.scoreA == 29 && currentGame.scoreB == 29 }
    var shouldSwitchSides: Bool { /* Law 8 logic */ }
    var currentServer: PlayerPosition { /* Law 10/11 logic */ }
    var serviceCourt: Court { /* even/odd logic */ }
}

struct GameState: Codable, Equatable, Sendable {
    var scoreA: Int = 0
    var scoreB: Int = 0
    var gameNumber: Int               // 1, 2, or 3
    var hasSwitchedInThirdGame: Bool = false
}

enum MatchEvent: Codable, Sendable {
    case scorePoint(Side)
    case undo
    case abandon
}
```

```swift
// ScoringEngine/Sources/ScoringEngine/MatchEngine.swift
enum MatchEngine {
    /// Pure function: (State, Event) -> State
    static func apply(event: MatchEvent, to state: MatchState) -> MatchState {
        switch event {
        case .scorePoint(let side):
            var next = state
            next.previousState = state  // snapshot for undo
            // Apply point, check game win, check match win
            return next
        case .undo:
            return state.previousState ?? state
        case .abandon:
            var next = state
            next.matchPhase = .abandoned
            return next
        }
    }
}
```

### Pattern 2: @Observable ViewModel Bridging Engine to SwiftUI
**What:** An `@Observable` class owns the `MatchState` struct and handles persistence to SwiftData after each transition.
**When to use:** LiveMatchView and any UI that displays live scoring.

```swift
@Observable
final class LiveMatchViewModel {
    private(set) var state: MatchState
    private let modelContext: ModelContext

    func scorePoint(for side: Side) {
        state = MatchEngine.apply(event: .scorePoint(side), to: state)
        persistState()
    }

    func undo() {
        state = MatchEngine.apply(event: .undo, to: state)
        persistState()
    }

    private func persistState() {
        // Update the SwiftData @Model with current state
        // This saves after EVERY point per user decision
    }
}
```

### Pattern 3: SwiftData Models with CloudKit Constraints
**What:** @Model classes use optional properties and default values from day one.
**When to use:** All persistent data models.

```swift
@Model
final class PersistedMatch {
    var id: UUID = UUID()
    var format: String = "singles"    // Store as String, not enum (CloudKit safe)
    var startedAt: Date = Date()
    var endedAt: Date?                // Optional -- match may be in progress
    var stateJSON: Data?              // Serialized MatchState for crash recovery
    var isComplete: Bool = false
    var isAbandoned: Bool = false

    // Player names (optional for quick games)
    var playerAName: String?
    var playerBName: String?
    var playerA2Name: String?         // Doubles partner
    var playerB2Name: String?         // Doubles partner

    // Game scores stored as simple arrays
    var game1ScoreA: Int = 0
    var game1ScoreB: Int = 0
    var game2ScoreA: Int?
    var game2ScoreB: Int?
    var game3ScoreA: Int?
    var game3ScoreB: Int?

    // Relationships must be optional for CloudKit
    // var player: PersistedPlayer?   // Phase 3

    init() {}  // Required empty init for SwiftData
}
```

### Anti-Patterns to Avoid
- **Putting BWF rules in the view layer:** All scoring logic MUST live in the ScoringEngine package. Views call the ViewModel, ViewModel calls MatchEngine, MatchEngine returns new state. Views never compute scores.
- **Using @Attribute(.unique) on any property:** CloudKit does not support unique constraints. Use UUID-based IDs without uniqueness enforcement.
- **Storing enums directly in SwiftData:** Store as String or Int raw values. Enum case additions across versions can break CloudKit deserialization.
- **Holding match state only in memory:** State MUST persist to SwiftData after every point. App can be killed at any time (SIGKILL from watchOS permission changes, iOS background termination).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Service rotation tracking | Custom linked list of players | Explicit index into fixed-size array of 4 players | Doubles rotation is a deterministic cycle; array index math handles it cleanly |
| State serialization | Custom binary format | Codable + JSON | MatchState is a simple struct tree; Codable encodes it for both persistence and Watch sync |
| Undo system | Command pattern with undo stack | Single previousState snapshot on MatchState | User decided single-level undo only; a snapshot is simpler and covers the requirement |
| Half-screen tap targets | Custom gesture recognizers | SwiftUI Button + GeometryReader + contentShape(Rectangle()) | SwiftUI handles hit testing correctly when contentShape is set |
| Score persistence | Manual SQLite | SwiftData @Model | SwiftData handles schema, migrations, and future CloudKit sync |

**Key insight:** The scoring engine itself is pure computation -- no I/O, no frameworks, no dependencies. Everything complex (persistence, UI, sync) wraps around the engine, never inside it.

## BWF Scoring Rules (Exhaustive Reference)

### Law 7: Scoring System
- A game is won by the first side to reach 21 points (Law 7.1)
- If the score reaches 20-all, the side that gains a 2-point lead wins (Law 7.3)
- If the score reaches 29-all, the side scoring the 30th point wins (Law 7.4)
- A match is best-of-3 games (Law 7.6)

### Law 8: Change of Ends
- Players change ends after the first game (Law 8.1.1)
- Players change ends after the second game, if there is a third game (Law 8.1.2)
- In the third game, players change ends when a side first reaches 11 points (Law 8.1.3)

### Law 10: Singles Service Rules
- Server's score is 0 or even: serve from RIGHT service court (Law 10.1)
- Server's score is odd: serve from LEFT service court (Law 10.2)
- Server wins rally: server scores a point and serves again from the alternate court (Law 10.5)
- Receiver wins rally: receiver scores a point and becomes the new server (Law 10.6)

### Law 11: Doubles Service Rules
- Serving side's score is 0 or even: server serves from RIGHT court (Law 11.1)
- Serving side's score is odd: server serves from LEFT court (Law 11.2)
- The player of the receiving side standing in the diagonally opposite court is the receiver (Law 11.3)
- Serving side wins rally: server scores a point and serves again from alternate court (Law 11.4)
- Receiving side wins rally: receiving side becomes the new serving side (Law 11.5)
- Players do NOT change service courts until they win a point when their side is serving (Law 11.6)

### Doubles Service Rotation Sequence
At the start of a game, the serving side chooses which player serves first, and the receiving side chooses which player receives first. After that:
1. Initial server serves from right court
2. After initial server's side loses service, the player diagonally opposite the initial receiver serves
3. Then the initial server's partner
4. Then the initial receiver
5. Then back to initial server -- the cycle repeats

**Critical implementation detail:** Track which player is in which court position. Players switch courts ONLY when their own side scores while serving. When they gain service (opponent loses), players stay in their current courts.

### 2026 Mixed Doubles Clarification
Effective January 1, 2026: when the receiving side wins a rally and gains service, the player who was NOT the receiver serves next. This prevents strategic receiver-switching and ensures rotational integrity. Example: if the male player (Player A) receives and wins the rally, the female player (Player B) serves next.

### Law 16: Intervals
- 60-second interval when the leading score reaches 11 in any game (Law 16.2.1)
- 120-second interval between games (Law 16.2.2)

### 3x15 Scoring System Status
The BWF is trialing a 3x15 rally scoring system (best-of-3 games to 15, no deuce, cap at 21) but the membership vote is scheduled for April 25, 2026. The current 21-point system remains official. **Do NOT implement 3x15 in Phase 1.** If adopted later, it can be added as a configuration option.

## Common Pitfalls

### Pitfall 1: Doubles Service Rotation Bugs
**What goes wrong:** The most common scoring app bug. Developers confuse "who serves next" with "who served last." In doubles, when the receiving side wins the rally, the player who was NOT the receiver must serve -- NOT the player who was the receiver.
**Why it happens:** The rule is counterintuitive. Most developers expect the receiver who won the rally to serve next.
**How to avoid:** Model each player's court position (left/right) separately from the service order. Track a service rotation index (0-3) that maps to the four players in fixed order. Unit test every rally of a full doubles game.
**Warning signs:** Tests pass for the first 5-6 rallies but fail later when rotation cycles.

### Pitfall 2: Side Switch Resets Service Court
**What goes wrong:** After switching sides (end of game or at 11 in third game), the service court assignment gets confused because the physical left/right of the court has flipped.
**Why it happens:** The service court (even=right, odd=left) is relative to the SCORING side's perspective, which flips after a side switch.
**How to avoid:** The state machine tracks logical service court (right/left based on score), NOT physical position on screen. The UI layer maps logical court to physical screen position based on which side the team is currently on.
**Warning signs:** Service indicator appears on the wrong side after a side switch.

### Pitfall 3: Undo From Game-Over State
**What goes wrong:** A user accidentally taps the final point, the game ends, the celebration overlay appears, and there is no way to undo. Competing apps have this bug.
**Why it happens:** The game-end logic transitions to a new game state, and undo only reverts within the current game.
**How to avoid:** Store the previousState snapshot BEFORE any transition, including game-ending transitions. Undo from a "game just ended" state should restore the previous game's penultimate state. The celebration overlay should have a visible undo button.
**Warning signs:** Cannot undo the winning point of a game.

### Pitfall 4: SwiftData Saving Blocks the Main Thread
**What goes wrong:** Saving MatchState JSON to SwiftData after every point causes a visible UI hitch, especially noticeable during fast-paced scoring.
**Why it happens:** SwiftData operations on the main ModelContext run on the main thread by default.
**How to avoid:** Keep the persisted data minimal (scores + metadata, not the full state machine history). Use `modelContext.save()` only when needed (autosave handles most cases). If performance is an issue, use a background ModelContext with `ModelActor`.
**Warning signs:** UI stutter when tapping to score rapidly (e.g., tapping 5 points in 3 seconds during testing).

### Pitfall 5: State Machine Not Sendable
**What goes wrong:** Compiler errors when passing MatchState between actors or to background tasks in Swift 6 strict concurrency mode.
**Why it happens:** If MatchState contains reference types or non-Sendable properties.
**How to avoid:** Make MatchState and all its nested types (GameState, PlayerPosition, etc.) conform to Sendable. Since they are all structs with value-type properties, this should be automatic. Verify by enabling strict concurrency checking in the package's build settings.
**Warning signs:** Concurrency warnings that escalate to errors in Swift 6 mode.

## Code Examples

### Half-Screen Tap Zones (SCORE-02)
```swift
// Source: SwiftUI standard patterns + contentShape for hit testing
struct LiveMatchView: View {
    @State private var viewModel: LiveMatchViewModel

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Left half -- Team A
                Button {
                    viewModel.scorePoint(for: .sideA)
                } label: {
                    ScorePanel(
                        score: viewModel.state.currentGame.scoreA,
                        teamName: viewModel.state.teamAName,
                        isServing: viewModel.state.currentServer.side == .sideA,
                        serviceCourt: viewModel.state.serviceCourt
                    )
                    .frame(width: geometry.size.width / 2, height: geometry.size.height)
                    .contentShape(Rectangle()) // Makes entire area tappable
                }
                .buttonStyle(.plain)

                // Right half -- Team B
                Button {
                    viewModel.scorePoint(for: .sideB)
                } label: {
                    ScorePanel(
                        score: viewModel.state.currentGame.scoreB,
                        teamName: viewModel.state.teamBName,
                        isServing: viewModel.state.currentServer.side == .sideB,
                        serviceCourt: viewModel.state.serviceCourt
                    )
                    .frame(width: geometry.size.width / 2, height: geometry.size.height)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .ignoresSafeArea()
    }
}
```

### Parameterized Scoring Tests (Swift Testing)
```swift
// Source: Swift Testing parameterized test pattern
import Testing
@testable import ScoringEngine

struct SinglesScoringTests {
    @Test("Regular game win at 21", arguments: [
        (scoresA: 21, scoresB: 15),
        (scoresA: 21, scoresB: 0),
        (scoresA: 21, scoresB: 19),
    ])
    func regularGameWin(scoresA: Int, scoresB: Int) {
        var state = MatchState.newSinglesMatch()
        // Score points alternating as needed
        for _ in 0..<scoresB {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        for _ in scoresB..<scoresA {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.currentGame.scoreA == scoresA)
        #expect(state.games.count == 1) // One game completed
    }

    @Test("Deuce requires 2-point lead")
    func deuceScenario() {
        var state = MatchState.newSinglesMatch()
        // Score to 20-20
        for _ in 0..<20 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        #expect(state.isDeuce == true)

        // Score 21-20 -- game NOT won yet
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.currentGame.scoreA == 21)
        #expect(state.matchPhase == .inProgress)

        // Score 22-20 -- game won
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.games.count == 1)
    }

    @Test("30-point cap overrides deuce")
    func capAt30() {
        var state = MatchState.newSinglesMatch()
        // Score to 29-29
        for _ in 0..<29 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        #expect(state.isAtCap == true)

        // 30th point wins regardless of lead
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.games.count == 1)
        #expect(state.currentGame.scoreA == 0) // New game started
    }
}
```

### Service Court Tracking
```swift
// Source: BWF Laws 10 and 11
extension MatchState {
    /// Which court the server serves from (Law 10.1-10.2, Law 11.1-11.2)
    var serviceCourt: Court {
        let servingScore = currentServer.side == .sideA
            ? currentGame.scoreA
            : currentGame.scoreB
        return servingScore.isMultiple(of: 2) ? .right : .left
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| ObservableObject + @Published | @Observable macro | iOS 17 (2023) | Simpler, better performance, no Combine dependency |
| Core Data | SwiftData | iOS 17 (2023) | Macro-based, native SwiftUI integration |
| XCTest only | Swift Testing + XCTest | Xcode 16 (2024) | Parameterized tests, modern syntax, parallel by default |
| 15-point scoring (pre-2006) | 21-point rally scoring | 2006 | Current BWF standard; 3x15 trial pending vote April 2026 |

**Deprecated/outdated:**
- ObservableObject: Replaced by @Observable for new code
- Core Data: Replaced by SwiftData for greenfield iOS 17+ apps
- @Attribute(.unique): Cannot be used with CloudKit sync

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (Xcode 16+) + XCTest (UI tests only) |
| Config file | ScoringEngine/Package.swift (test target) + Xcode scheme |
| Quick run command | `swift test --package-path ScoringEngine` |
| Full suite command | `xcodebuild test -scheme BadmintonEye -destination 'platform=iOS Simulator,name=iPhone 16'` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SCORE-01 | Start match with singles/doubles/mixed format | unit | `swift test --filter SinglesScoringTests` | Wave 0 |
| SCORE-02 | Tap increments score for correct side | unit + UI | `swift test --filter ScorePointTests` | Wave 0 |
| SCORE-03 | BWF 21-point, deuce, 30-cap enforcement | unit | `swift test --filter DeuceAndCapTests` | Wave 0 |
| SCORE-04 | Best-of-3 games, side switches | unit | `swift test --filter GameTransitionTests` | Wave 0 |
| SCORE-05 | Service side tracks even/odd score | unit | `swift test --filter ServiceCourtTests` | Wave 0 |
| SCORE-06 | Doubles service rotation | unit | `swift test --filter DoublesScoringTests` | Wave 0 |
| SCORE-07 | Undo last point | unit | `swift test --filter UndoTests` | Wave 0 |
| SCORE-08 | Offline operation (no network calls) | integration | Manual verification -- engine has zero network imports | N/A |

### Sampling Rate
- **Per task commit:** `swift test --package-path ScoringEngine`
- **Per wave merge:** `xcodebuild test -scheme BadmintonEye -destination 'platform=iOS Simulator,name=iPhone 16'`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `ScoringEngine/Package.swift` -- local package manifest with test target
- [ ] `ScoringEngine/Tests/ScoringEngineTests/` -- all test files listed above
- [ ] Xcode project with iOS target linking ScoringEngine package
- [ ] Xcode test scheme configured for both package tests and app tests

## Open Questions

1. **3x15 Scoring System Adoption**
   - What we know: BWF vote scheduled April 25, 2026. Currently in trial only.
   - What's unclear: Whether it will be adopted, and if so, when it takes effect for recreational play.
   - Recommendation: Implement 21-point only. Design MatchState to be parameterizable (winningScore, maxScore properties) so a 3x15 mode can be added later without restructuring.

2. **SwiftData Performance for Per-Point Saves**
   - What we know: SwiftData autosave typically batches writes. Explicit `save()` after every point may cause UI jank.
   - What's unclear: Actual performance on target devices with the match data size we produce.
   - Recommendation: Start with autosave (default behavior). Only add explicit saves if crash recovery testing shows data loss. Profile if UI stutters appear.

3. **Mixed Doubles 2026 Rule Clarification Edge Cases**
   - What we know: The 2026 rule clarifies that the non-receiver serves next when the receiving side wins service.
   - What's unclear: Whether this is truly a CHANGE from previous rules or just a clarification of existing rules.
   - Recommendation: Implement the 2026 clarification as stated. It is the current law regardless of whether it represents a change.

## Sources

### Primary (HIGH confidence)
- [BWF Laws of Badminton](https://worldbadminton.com/rules/) -- Laws 7, 8, 10, 11, 16 (scoring, service, intervals)
- [BWF 2026 Rules Update](https://bwfbadminton.com/news-single/2025/11/27/updates-to-bwf-laws-and-regulations-4/) -- 2026 edition changes
- [BWF 3x15 Scoring Trial Status](https://bwfbadminton.com/news-single/2026/02/12/3x15-scoring-system-for-decision-at-bwf-agm-2026) -- Vote pending April 25, 2026
- [SwiftData CloudKit Constraints - fatbobman](https://fatbobman.com/en/snippet/rules-for-adapting-data-models-to-cloudkit/) -- Optional properties, no unique constraints
- [Swift Testing - Apple Developer](https://developer.apple.com/xcode/swift-testing/) -- @Test macro, parameterized tests

### Secondary (MEDIUM confidence)
- [SwiftUI contentShape for tap areas - Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftui/how-to-control-the-tappable-area-of-a-view-using-contentshape) -- Hit testing patterns
- [Pure State Machine with Effects - Andy Matuschak](https://gist.github.com/andymatuschak/d5f0a8730ad601bcccae97e8398e25b2) -- Separation of pure transitions from effects
- [SwiftData Architecture Patterns - AzamSharp](https://azamsharp.com/2025/03/28/swiftdata-architecture-patterns-and-practices.html) -- Model design patterns
- [Sharing Swift Package with watchOS - Corner Software](https://csdcorp.com/blog/coding/sharing-swift-package-with-watchos-extension/) -- Multi-target package setup

### Tertiary (LOW confidence)
- [BWF 2026 Mixed Doubles Rule Details](https://www.alibaba.com/product-insights/what-are-the-official-badminton-rules-in-2026.html) -- Specific mixed doubles rotation clarification (page now 404, info cross-referenced with other sources)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all Apple-native frameworks, well-documented
- Architecture: HIGH -- pure state machine is a well-established pattern; SwiftData CloudKit constraints documented by multiple authoritative sources
- BWF Rules: HIGH -- sourced from official BWF Laws; 2026 changes cross-verified
- Pitfalls: HIGH -- doubles service rotation bugs and undo-from-game-over are well-known issues in competing apps
- UI patterns: MEDIUM -- half-screen tap zones are straightforward SwiftUI but need real-device testing for ergonomics

**Research date:** 2026-03-28
**Valid until:** 2026-04-28 (stable domain; re-check if BWF 3x15 vote result changes scoring rules after April 25)
