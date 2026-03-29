# Phase 2: Apple Watch Companion - Research

**Researched:** 2026-03-28
**Domain:** watchOS companion app with WatchConnectivity sync, HealthKit workout integration, and iPad adaptive layout
**Confidence:** HIGH

## Summary

Phase 2 adds an Apple Watch companion app that displays live scores, accepts tap-to-score input, syncs bidirectionally with iPhone via WatchConnectivity, runs HealthKit workout sessions during matches, and adapts the existing iPhone UI for iPad via NavigationSplitView. The Watch app consumes the existing ScoringEngine Swift package (already configured with `.watchOS(.v10)` platform support).

The primary technical challenge is WatchConnectivity reliability. The framework has three distinct transport mechanisms with different guarantees, and the decision to use `updateApplicationContext` as primary (latest-wins, guaranteed delivery) with `sendMessage` as a real-time boost is correct and well-supported by Apple documentation and developer experience. The second major area is HealthKit workout integration, which uses `HKWorkoutSession` + `HKLiveWorkoutBuilder` -- a well-documented pattern with `HKWorkoutActivityType.badminton` available since iOS 10/watchOS 3.

The iPad layout work uses `NavigationSplitView`, which automatically provides sidebar-detail on iPad and collapses to `NavigationStack` on iPhone -- a straightforward adaptation of the existing views.

**Primary recommendation:** Build the WatchConnectivity manager as a singleton `@unchecked Sendable` class shared between iOS and watchOS targets, with `updateApplicationContext` as the always-on transport and `sendMessage` as an opportunistic fast path. The Watch UI should be a single-screen vertical split with two large tap zones (top = Side A, bottom = Side B) and minimal chrome.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Two large tap zones (top/bottom split) matching iPhone's left/right paradigm -- maximizes 45mm screen
- Watch displays: score (large, centered), game indicator (dots), shuttlecock icon for server -- absolute minimum for glanceability
- Watch can only JOIN an iPhone-started match, not create new ones -- keeps Watch interaction minimal
- Haptic patterns: single tap on score, double tap on game won, long buzz on match complete -- distinct and unmistakable during play
- `updateApplicationContext` as primary transport + `sendMessage` for real-time boost when reachable
- iPhone is authoritative -- Watch sends scoring intents, iPhone validates and confirms. Timestamp ordering for disconnection reconciliation
- Watch continues scoring independently using local ScoringEngine copy when disconnected. On reconnect, sync full state snapshot (iPhone state wins if conflict)
- iPhone creates match -> Watch auto-receives via applicationContext. Match end on either device propagates to the other
- HealthKit workout starts automatically when a match starts on Watch -- no extra step
- Workout type: `HKWorkoutActivityType.badminton` with active energy, heart rate, and duration
- iPad layout: NavigationSplitView -- match list in sidebar, active match in detail pane
- iPad scoring: same half-screen tap zones as iPhone but with wider panels

### Claude's Discretion
- WatchConnectivity error handling and retry strategies
- Specific animation timing for Watch UI transitions
- Internal naming conventions for sync message types

### Deferred Ideas (OUT OF SCOPE)
- None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| WATCH-01 | Apple Watch displays current score, game number, and server indicator in a glanceable layout | watchOS SwiftUI layout patterns, 44pt+ tap targets, flat navigation (no nested TabView) |
| WATCH-02 | User can tap to score from Apple Watch with large tap targets and haptic confirmation | Top/bottom VStack split, WKInterfaceDevice haptic API, WKHapticType patterns |
| WATCH-03 | Score updates sync in real-time between iPhone/iPad and Apple Watch (bidirectional) | WatchConnectivity triple-transport strategy, CodableMatchState serialization, conflict resolution |
| WATCH-04 | Watch app functions independently if iPhone is temporarily unreachable | Local ScoringEngine copy, UserDefaults persistence per point, reconnection reconciliation |
| WATCH-05 | Match automatically starts a HealthKit workout session tracking calories, heart rate, and duration | HKWorkoutSession + HKLiveWorkoutBuilder + HKLiveWorkoutDataSource, auto-start on match begin |
| WATCH-06 | Completed match workout data is written to HealthKit and counts toward Activity Rings | HKLiveWorkoutBuilder.endCollection + finishWorkout, Activity Rings integration automatic |
| UX-02 | App supports both iPhone and iPad with adaptive layouts | NavigationSplitView with sidebar/detail, horizontalSizeClass environment value |
</phase_requirements>

## Standard Stack

### Core (Phase 2 additions)

| Library/Framework | Version | Purpose | Why Standard |
|-------------------|---------|---------|--------------|
| WatchConnectivity | watchOS 10+ | Bidirectional iPhone-Watch sync | Only framework for direct device-to-device communication; no alternatives exist |
| HealthKit | watchOS 10+ | Workout session tracking | Required for Activity Rings integration and workout data |
| HKWorkoutSession | watchOS 10+ | Manages workout lifecycle | Apple's dedicated API for live workout tracking on Watch |
| HKLiveWorkoutBuilder | watchOS 10+ | Collects workout samples in real-time | Automatic sensor management (heart rate, energy) via HKLiveWorkoutDataSource |
| SwiftUI (watchOS) | watchOS 10+ | Watch app UI | Required for watchOS apps; shares code patterns with iOS target |
| NavigationSplitView | iOS 16+ | iPad sidebar-detail layout | Native adaptive layout; collapses to NavigationStack on iPhone automatically |

### Already in Project (from Phase 1)

| Library | Purpose | Phase 2 Usage |
|---------|---------|---------------|
| ScoringEngine (local package) | BWF scoring state machine | Imported by watchOS target -- already has `.watchOS(.v10)` platform |
| SwiftData | Match persistence | iPad uses same PersistedMatch model; Watch does NOT need SwiftData |
| @Observable | Reactive view models | Watch ViewModel wraps WatchConnectivity state for SwiftUI |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `updateApplicationContext` primary | `sendMessage` primary | sendMessage fails silently when not reachable; applicationContext guarantees eventual delivery |
| `transferUserInfo` for scoring | `updateApplicationContext` | transferUserInfo is FIFO queued with higher latency; scoring only needs latest state, not history |
| SwiftData on Watch | UserDefaults on Watch | SwiftData adds unnecessary overhead on Watch; UserDefaults is sufficient for single-match state persistence |
| Custom workout tracking | HKLiveWorkoutBuilder | HKLiveWorkoutBuilder handles sensor management automatically; custom approach requires manual HKQuantitySample creation |

**Installation:**
```bash
# No additional package dependencies -- all Apple frameworks
# watchOS target added to existing Xcode project, importing ScoringEngine package
```

## Architecture Patterns

### Recommended Project Structure
```
BadmintonEye/
├── BadmintonEye/                  # iOS app target (existing)
│   ├── App/
│   ├── Models/
│   ├── ViewModels/
│   │   ├── LiveMatchViewModel.swift      # Updated: notify WatchSyncManager on state changes
│   │   └── ...
│   ├── Views/
│   │   ├── LiveMatchView.swift           # Updated: iPad-adaptive with NavigationSplitView
│   │   └── ...
│   └── Services/
│       └── WatchSyncManager.swift        # NEW: iOS-side WCSessionDelegate singleton
│
├── BadmintonEyeWatch/             # watchOS app target (NEW)
│   ├── App/
│   │   └── BadmintonEyeWatchApp.swift
│   ├── Views/
│   │   ├── WatchScoringView.swift        # Top/bottom tap zones
│   │   ├── WatchScoreDisplay.swift       # Glanceable score + game dots + server icon
│   │   └── WatchWaitingView.swift        # "Open iPhone to start match" state
│   ├── ViewModels/
│   │   └── WatchMatchViewModel.swift     # @Observable, drives Watch UI from sync state
│   └── Services/
│       ├── WatchSessionManager.swift     # watchOS-side WCSessionDelegate singleton
│       └── WorkoutManager.swift          # HKWorkoutSession + HKLiveWorkoutBuilder
│
├── Shared/                        # Shared code (or use ScoringEngine package)
│   └── SyncPayload.swift                 # Codable struct for WatchConnectivity messages
│
└── ScoringEngine/                 # Existing Swift package (already supports watchOS)
    └── ...
```

### Pattern 1: WatchConnectivity Triple-Transport Strategy

**What:** Use three WatchConnectivity methods in concert for reliable scoring sync.
**When:** Every score update from either device.

```swift
// iPhone side: after scoring a point
func sendStateUpdate(_ state: MatchState) {
    let payload = SyncPayload(from: state)
    let dict = try! JSONEncoder().encode(payload)
    let message: [String: Any] = ["state": dict, "timestamp": Date().timeIntervalSince1970]

    // 1. ALWAYS update applicationContext (guaranteed latest-state delivery)
    try? WCSession.default.updateApplicationContext(message)

    // 2. ALSO sendMessage for real-time if reachable
    if WCSession.default.isReachable {
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            // Non-fatal: applicationContext is the fallback
            print("sendMessage failed (non-fatal): \(error.localizedDescription)")
        }
    }
}

// Watch side: scoring intent (Watch -> iPhone)
func sendScoringIntent(side: Side) {
    let intent: [String: Any] = ["action": "scorePoint", "side": side.rawValue,
                                  "timestamp": Date().timeIntervalSince1970]
    if WCSession.default.isReachable {
        WCSession.default.sendMessage(intent, replyHandler: nil, errorHandler: nil)
    }
    // Also apply locally for immediate UI feedback
    applyLocalScore(side: side)
    // Persist locally for crash recovery
    persistLocalState()
}
```

**Key insight:** `updateApplicationContext` overwrites previous unsent context. For scoring, this is correct behavior -- the Watch only ever needs the latest score state, not a history of changes.

### Pattern 2: Watch Offline Scoring with Reconciliation

**What:** Watch maintains a local ScoringEngine when iPhone is unreachable, reconciles on reconnect.
**When:** `WCSession.default.isReachable == false` during active scoring.

```swift
// WatchMatchViewModel
@Observable
final class WatchMatchViewModel {
    private(set) var state: MatchState?
    private(set) var isOffline: Bool = false
    private var localEngine: Bool = false // true when scoring without iPhone

    func scorePoint(for side: Side) {
        guard var currentState = state else { return }

        if WCSession.default.isReachable && !localEngine {
            // Send intent to iPhone (authoritative)
            WatchSessionManager.shared.sendScoringIntent(side: side)
        } else {
            // Offline: apply locally
            isOffline = true
            localEngine = true
            state = MatchEngine.apply(event: .scorePoint(side), to: currentState)
            persistToUserDefaults()
        }
    }

    func receiveStateFromiPhone(_ newState: MatchState) {
        // iPhone state wins on reconnection
        state = newState
        localEngine = false
        isOffline = false
        clearLocalPersistence()
    }
}
```

### Pattern 3: HealthKit Workout Lifecycle

**What:** Auto-start workout when match begins on Watch, end when match completes.
**When:** Match state transitions to active / complete.

```swift
final class WorkoutManager: NSObject, HKWorkoutSessionDelegate,
                            HKLiveWorkoutBuilderDelegate {
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private let healthStore = HKHealthStore()

    func startWorkout() async throws {
        let config = HKWorkoutConfiguration()
        config.activityType = .badminton
        config.locationType = .indoor  // Most badminton is indoor

        session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
        builder = session?.associatedWorkoutBuilder()

        session?.delegate = self
        builder?.delegate = self
        builder?.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: config
        )

        let startDate = Date()
        session?.startActivity(with: startDate)
        try await builder?.beginCollection(at: startDate)
    }

    func endWorkout() async throws {
        session?.end()
        let endDate = Date()
        try await builder?.endCollection(at: endDate)
        try await builder?.finishWorkout()
        // Workout automatically contributes to Activity Rings
    }
}
```

### Pattern 4: iPad Adaptive Layout with NavigationSplitView

**What:** Wrap existing iPhone views in NavigationSplitView for iPad sidebar-detail layout.
**When:** iPad horizontal size class detected.

```swift
struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            // iPad: sidebar + detail
            NavigationSplitView {
                MatchListSidebar()
            } detail: {
                // Active match or setup
                ActiveMatchDetail()
            }
        } else {
            // iPhone: existing NavigationStack
            NavigationStack {
                // existing flow
            }
        }
    }
}
```

### Pattern 5: WCSession Singleton with Swift 6 Concurrency

**What:** Thread-safe WCSessionDelegate singleton compatible with Swift 6 strict concurrency.
**When:** Both iOS and watchOS targets need a session manager.

```swift
final class WatchSyncManager: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSyncManager()

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // Delegate methods dispatch to @MainActor for UI updates
    func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            // Decode and update view model
        }
    }
}
```

**Why `@unchecked Sendable`:** WCSession requires an NSObject delegate. The singleton holds no mutable state that crosses isolation boundaries -- all state mutations happen on MainActor via Task dispatch. This is the standard pattern for WCSession in Swift 6 codebases.

### Anti-Patterns to Avoid

- **Nested TabView on watchOS:** Causes cumulative memory leaks. Use a flat structure with a single TabView at most, or a simple VStack-based layout. Source: fatbobman.com production experience.
- **sendMessage without applicationContext fallback:** Messages are silently lost when Watch is not reachable. Always pair with `updateApplicationContext`.
- **SwiftData on watchOS:** Unnecessary overhead. Watch only needs current match state (UserDefaults) plus the ScoringEngine for offline scoring. Full persistence belongs on iPhone.
- **Confirmation dialogs on Watch scoring:** One tap = one point. No "Are you sure?" dialogs during active play. Undo via Digital Crown rotation or a small button instead.
- **Holding match state only in memory on Watch:** watchOS sends SIGKILL when privacy settings change on iPhone. Persist state to UserDefaults after every point scored.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Device-to-device sync | Custom Bluetooth/networking | WatchConnectivity framework | Only supported mechanism; handles all Bluetooth/Wi-Fi transport automatically |
| Workout sensor data collection | Manual HKQuantitySample queries | HKLiveWorkoutDataSource | Automatically manages heart rate sensor, energy calculations, workout state |
| Activity Rings contribution | Manual HKActivitySummary writes | HKLiveWorkoutBuilder.finishWorkout() | Finishing a workout automatically credits Activity Rings -- no manual step needed |
| iPad sidebar layout | Custom split view with GeometryReader | NavigationSplitView | Handles all platform adaptations, sidebar visibility states, and collapse behavior natively |
| Haptic feedback engine | Custom AudioServicesPlaySystemSound | WKInterfaceDevice.current().play(_:) | watchOS provides predefined haptic types (.success, .failure, .notification, etc.) that feel native |
| Match state serialization for sync | Custom binary protocol | CodableMatchState (existing) + JSONEncoder | Already built in Phase 1; Codable struct mirrors MatchState without recursive previousState |

**Key insight:** CodableMatchState from Phase 1 is the perfect sync payload. It already strips the recursive `previousState` field and round-trips through `MatchState`. Use it directly as the WatchConnectivity payload format.

## Common Pitfalls

### Pitfall 1: WatchConnectivity Silent Message Loss
**What goes wrong:** `sendMessage` fails silently when Watch screen is off, app is backgrounded, or Bluetooth drops. Score updates appear lost.
**Why it happens:** `sendMessage` requires both apps to be active and reachable. During a fast badminton game, the Watch screen frequently turns off.
**How to avoid:** Always call `updateApplicationContext` alongside `sendMessage`. The context persists and is delivered when the Watch app next becomes active.
**Warning signs:** Stale scores on Watch after wrist-down/wrist-up gesture.

### Pitfall 2: watchOS SIGKILL on iPhone Privacy Setting Change
**What goes wrong:** User changes any privacy setting on iPhone mid-match, watchOS kills the Watch app instantly. Unsaved state is lost.
**Why it happens:** Apple watchOS security policy sends SIGKILL (not SIGTERM -- no chance to save) to the Watch app when privacy entitlements change.
**How to avoid:** Persist match state to UserDefaults after EVERY scored point, not just at match end. On launch, check for and recover interrupted state.
**Warning signs:** Users report "Watch app crashed and lost my score."

### Pitfall 3: Nested TabView Memory Leak on watchOS
**What goes wrong:** Using TabView inside TabView on watchOS causes cumulative memory growth. After several matches, watchOS watchdog kills the app.
**Why it happens:** watchOS has ~80-120MB memory budget for foreground apps. Nested TabViews leak view hierarchies.
**How to avoid:** Flat navigation: single-screen scoring view with optional sheet/fullScreenCover for settings. No TabView nesting.
**Warning signs:** App becomes slower after 3-4 matches without force-quit.

### Pitfall 4: HealthKit Permission Request During Active Play
**What goes wrong:** HealthKit authorization prompt appears mid-match when workout tries to start, interrupting scoring flow.
**Why it happens:** `HKHealthStore.requestAuthorization` is called lazily on first workout start.
**How to avoid:** Request HealthKit permissions during app onboarding/first launch, before any match starts. Check authorization status before starting workout and skip gracefully if denied.
**Warning signs:** System permission sheet appearing over the scoring interface.

### Pitfall 5: WatchConnectivity Session Not Activated Early Enough
**What goes wrong:** First message sent before `WCSession.default.activate()` has completed. Messages silently dropped.
**Why it happens:** `activate()` is async. Sending messages before `activationDidComplete` delegate callback fires results in no-ops.
**How to avoid:** Call `WatchSyncManager.shared.activate()` in the App's init or `onAppear` of the root view. Gate all message-sending on `session.activationState == .activated`.
**Warning signs:** First match after app launch fails to sync; subsequent matches work fine.

### Pitfall 6: iPad Layout Breaking in Slide Over / Split View
**What goes wrong:** NavigationSplitView collapses to single column in iPad Split View (1/3 width) and the scoring tap zones become too small.
**Why it happens:** iPad multitasking can shrink the app window to compact size class.
**How to avoid:** Use `horizontalSizeClass` environment value to detect compact mode and fall back to iPhone-style full-screen layout. Do not force NavigationSplitView in compact contexts.
**Warning signs:** Scoring panels are too narrow to tap reliably in iPad Split View mode.

## Code Examples

### SyncPayload -- Reusing CodableMatchState

```swift
// SyncPayload.swift (Shared between iOS and watchOS targets)
import Foundation
import ScoringEngine

struct SyncPayload: Codable {
    let matchState: CodableMatchState
    let timestamp: TimeInterval
    let isMatchActive: Bool

    init(from state: MatchState, isActive: Bool) {
        self.matchState = CodableMatchState(from: state)
        self.timestamp = Date().timeIntervalSince1970
        self.isMatchActive = isActive
    }

    func toDictionary() -> [String: Any] {
        let data = try! JSONEncoder().encode(self)
        return ["syncPayload": data]
    }

    static func from(dictionary: [String: Any]) -> SyncPayload? {
        guard let data = dictionary["syncPayload"] as? Data else { return nil }
        return try? JSONDecoder().decode(SyncPayload.self, from: data)
    }
}
```

### Watch Scoring View -- Top/Bottom Split

```swift
// WatchScoringView.swift
import SwiftUI
import ScoringEngine

struct WatchScoringView: View {
    @State var viewModel: WatchMatchViewModel

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Side A tap zone (top half)
                Button {
                    viewModel.scorePoint(for: .sideA)
                    WKInterfaceDevice.current().play(.click) // haptic
                } label: {
                    WatchScorePanel(
                        score: viewModel.scoreA,
                        name: viewModel.teamAName,
                        isServing: viewModel.servingSide == .sideA,
                        color: .blue
                    )
                }
                .buttonStyle(.plain)
                .frame(height: geo.size.height / 2)

                // Side B tap zone (bottom half)
                Button {
                    viewModel.scorePoint(for: .sideB)
                    WKInterfaceDevice.current().play(.click)
                } label: {
                    WatchScorePanel(
                        score: viewModel.scoreB,
                        name: viewModel.teamBName,
                        isServing: viewModel.servingSide == .sideB,
                        color: .red
                    )
                }
                .buttonStyle(.plain)
                .frame(height: geo.size.height / 2)
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .center) {
            // Game indicator dots centered between zones
            GameDotsIndicator(
                currentGame: viewModel.currentGameNumber,
                totalGames: 3
            )
        }
    }
}
```

### HealthKit Permission Request at Onboarding

```swift
// WorkoutManager.swift -- permission handling
func requestAuthorization() async -> Bool {
    let typesToShare: Set<HKSampleType> = [
        HKObjectType.workoutType()
    ]
    let typesToRead: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
    ]

    do {
        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        return true
    } catch {
        return false
    }
}
```

### Haptic Patterns for Match Events

```swift
// WatchMatchViewModel -- haptic feedback
func playHaptic(for event: MatchHapticEvent) {
    switch event {
    case .pointScored:
        WKInterfaceDevice.current().play(.click)        // single tap
    case .gameWon:
        WKInterfaceDevice.current().play(.success)       // double tap feel
    case .matchComplete:
        WKInterfaceDevice.current().play(.notification)  // long buzz
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| WKInterfaceController (storyboard) | SwiftUI lifecycle for watchOS | watchOS 7 (2020) | Pure SwiftUI Watch apps, no storyboards |
| Manual HKQuantitySample writes | HKLiveWorkoutBuilder + HKLiveWorkoutDataSource | watchOS 5 (2018) | Automatic sensor management, simplified workout tracking |
| WKExtensionDelegate | @main App struct | watchOS 7 (2020) | Standard SwiftUI app lifecycle |
| ObservableObject + @Published | @Observable macro | watchOS 10 (2023) | Simpler reactivity, no Combine dependency |
| NavigationView | NavigationSplitView / NavigationStack | iOS 16 (2022) | Proper multi-column iPad support |
| HealthKit workout on Watch only | HKWorkoutSession on iPhone too (iOS 26) | 2025 | Future opportunity, but watchOS remains primary for Phase 2 |

**Deprecated/outdated:**
- `WKInterfaceController`: Replaced by SwiftUI views; not relevant for new watchOS 10+ apps
- `NavigationView`: Replaced by NavigationSplitView/NavigationStack; NavigationView still works but has layout bugs on iPad
- `ObservableObject`: Still functional but `@Observable` is recommended for new code in iOS 17+ / watchOS 10+

## Open Questions

1. **Watch screen sizes and layout testing**
   - What we know: Apple Watch comes in 41mm, 45mm, 49mm (Ultra) sizes. Tap targets must be 44pt minimum.
   - What's unclear: Exact point dimensions for each size to validate the top/bottom split has sufficient area.
   - Recommendation: Design for 45mm as the baseline. Use `@Environment(\.isLuminanceReduced)` for always-on display state. Test on all sizes in Simulator.

2. **HKWorkoutSession background runtime**
   - What we know: An active HKWorkoutSession grants the Watch app extended background runtime.
   - What's unclear: Whether this keeps WatchConnectivity active for receiving score updates while wrist is down.
   - Recommendation: Test on real device. The workout session should keep the app alive, but WCSession message delivery when wrist is down needs empirical validation.

3. **CodableMatchState serialization size**
   - What we know: WatchConnectivity applicationContext has an undocumented but practical size limit.
   - What's unclear: Whether a full doubles match state (with rotation arrays, all game scores) exceeds typical limits.
   - Recommendation: CodableMatchState is lightweight (JSON, likely <2KB). Should be well within limits, but log payload sizes during development.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (Xcode 16+) + XCTest for UI tests |
| Config file | ScoringEngine/Package.swift (test target exists) |
| Quick run command | `cd ScoringEngine && swift test` |
| Full suite command | `cd ScoringEngine && swift test && xcodebuild test -project ../BadmintonEye/BadmintonEye.xcodeproj -scheme BadmintonEye -destination 'platform=iOS Simulator,name=iPhone 16'` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| WATCH-01 | Watch displays score, game, server | UI (manual) | Manual: verify on Watch Simulator | No -- Wave 0 |
| WATCH-02 | Watch tap-to-score with haptic | UI (manual) | Manual: tap test on Watch Simulator | No -- Wave 0 |
| WATCH-03 | Bidirectional sync iPhone <-> Watch | Integration | `swift test --filter WatchSyncTests` | No -- Wave 0 |
| WATCH-04 | Watch functions independently offline | Unit | `swift test --filter OfflineScoringTests` | No -- Wave 0 |
| WATCH-05 | Auto-start HealthKit workout | Integration | Manual: requires device with HealthKit | No -- Wave 0 |
| WATCH-06 | Workout data written to HealthKit | Integration | Manual: verify in Health app | No -- Wave 0 |
| UX-02 | iPad adaptive layout | UI (manual) | Manual: verify on iPad Simulator | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `cd ScoringEngine && swift test` (existing engine tests must stay green)
- **Per wave merge:** Full suite including any new WatchConnectivity unit tests
- **Phase gate:** All existing tests green + manual verification on Watch and iPad Simulators

### Wave 0 Gaps
- [ ] `Tests/WatchSyncTests/` -- WatchConnectivity message encoding/decoding, SyncPayload round-trip
- [ ] `Tests/WatchSyncTests/OfflineScoringTests.swift` -- Watch offline scoring with local ScoringEngine, state persistence to UserDefaults, reconciliation when iPhone state arrives
- [ ] `Tests/WatchSyncTests/SyncPayloadTests.swift` -- CodableMatchState serialization to/from [String: Any] dictionary
- [ ] HealthKit and Watch UI tests are manual-only (require device capabilities)
- [ ] iPad layout tests are manual-only (Simulator visual inspection)

## Sources

### Primary (HIGH confidence)
- [WatchConnectivity - Apple Developer Documentation](https://developer.apple.com/documentation/watchconnectivity) -- transport methods, session lifecycle
- [HKWorkoutSession - Apple Developer Documentation](https://developer.apple.com/documentation/healthkit/hkworkoutsession) -- workout session API
- [HKWorkoutActivityType.badminton - Apple Developer Documentation](https://developer.apple.com/documentation/healthkit/hkworkoutactivitytype/badminton) -- confirmed badminton workout type exists
- [HKLiveWorkoutBuilder - Apple Developer Documentation](https://developer.apple.com/documentation/healthkit/hkliveworkoutbuilder) -- live workout data collection
- [NavigationSplitView - Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/navigationsplitview) -- iPad sidebar-detail pattern
- [Transferring data with Watch Connectivity - Apple Developer](https://developer.apple.com/documentation/WatchConnectivity/transferring-data-with-watch-connectivity) -- official transfer patterns
- ScoringEngine Package.swift -- confirmed `.watchOS(.v10)` platform already configured

### Secondary (MEDIUM confidence)
- [HKLiveWorkoutBuilder Tutorial - BrightDigit](https://brightdigit.com/tutorials/hkliveworkoutbuilder-healthkit-workout-session/) -- workout session code patterns
- [WatchConnectivity Data Synchronization - Medium](https://medium.com/@sheik25bareeth/data-synchronization-between-ios-and-watchos-using-watchconnectivity-009a3064e12a) -- transport method comparison
- [Three Ways to Communicate via WatchConnectivity - Teabyte](https://alexanderweiss.dev/blog/2023-01-18-three-ways-to-communicate-via-watchconnectivity) -- applicationContext vs sendMessage vs transferUserInfo
- [watchOS Development Pitfalls - fatbobman.com](https://fatbobman.com/en/posts/watchos-development-pitfalls-and-practical-tips) -- SIGKILL pitfall, nested TabView leak, memory limits
- [Using Singletons in Swift 6 - Donny Wals](https://www.donnywals.com/using-singletons-in-swift-6/) -- @unchecked Sendable pattern for WCSession
- [SwiftUI iPad Adaptive Layout - Wesley Matlock](https://medium.com/@wesleymatlock/swiftui-ipad-adaptive-layout-five-layers-for-apps-that-dont-break-in-split-view-8433b726f293) -- NavigationSplitView iPad patterns

### Tertiary (LOW confidence)
- watchOS memory limits (512MB-2GB RAM, ~80-120MB per app budget) -- general developer reports, not official Apple documentation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all Apple first-party frameworks with well-documented APIs
- Architecture: HIGH -- WatchConnectivity patterns are mature (since watchOS 2), HealthKit workout APIs stable since watchOS 5
- Pitfalls: HIGH -- documented by multiple production developers (fatbobman.com, community forums)
- Watch UI patterns: MEDIUM -- specific tap zone sizing needs empirical validation on real devices
- Conflict resolution: MEDIUM -- iPhone-authoritative + timestamp ordering is a well-understood pattern but edge cases need testing

**Research date:** 2026-03-28
**Valid until:** 2026-04-28 (stable domain -- WatchConnectivity and HealthKit APIs have not changed significantly in years)
