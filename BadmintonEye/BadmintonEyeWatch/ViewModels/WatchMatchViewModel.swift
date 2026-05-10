import Foundation
import WatchConnectivity
#if os(watchOS)
import WatchKit
#endif
import ScoringEngine

/// ViewModel driving the Watch match UI.
/// Supports offline scoring via local MatchEngine when iPhone is unreachable.
/// Persists state to UserDefaults after every point for SIGKILL protection.
/// iPhone-authoritative: adopts iPhone state on reconnection.
///
/// Offline reconciliation (task 8a82ba0f):
/// When the Watch scores locally while offline, intents are queued in
/// `pendingIntents`. On the next iPhone state update, the queue is replayed
/// via sendScoringIntent so iPhone can apply the delta authoritatively.
/// iPhone echoes back the merged state, which the Watch then adopts.
///
/// Dependency injection (task 8b2b9d3f):
/// `isReachable` and `sendIntent` are injectable so the full scoring + reconciliation
/// logic can be tested without a real WCSession or WKInterfaceDevice.
@Observable
@MainActor
final class WatchMatchViewModel {

    // MARK: - Types

    /// A scoring intent queued while the Watch was offline.
    struct PendingIntent: Codable {
        let side: Side
        let timestamp: Date
    }

    // MARK: - Injected Dependencies

    /// Returns current WCSession reachability. Defaults to `WCSession.default.isReachable`.
    private let isReachable: () -> Bool

    /// Sends a scoring intent to the iPhone. Defaults to `WatchSessionManager.shared`.
    private let sendIntent: (Side) -> Void

    /// UserDefaults suite used for offline state persistence. Swappable in tests.
    private let userDefaults: UserDefaults

    // MARK: - State

    private(set) var state: MatchState?
    private(set) var isOffline: Bool = false
    private var localEngine: Bool = false
    /// Scoring intents accumulated while the Watch was offline.
    private(set) var pendingIntents: [PendingIntent] = []

    #if os(watchOS)
    private let workoutManager = WorkoutManager.shared
    #endif

    // MARK: - Computed Properties

    var scoreA: Int { state?.currentGame.scoreA ?? 0 }
    var scoreB: Int { state?.currentGame.scoreB ?? 0 }
    var teamAName: String { state?.teamANames.first ?? "Side A" }
    var teamBName: String { state?.teamBNames.first ?? "Side B" }
    var servingSide: Side? { state?.currentServer.side }
    var currentGameNumber: Int { state?.currentGame.gameNumber ?? 0 }
    var isMatchActive: Bool { state != nil && state?.matchPhase == .inProgress }
    var completedGames: [GameState] { state?.games ?? [] }

    /// True when local-only scoring events are queued and awaiting iPhone sync.
    var needsOfflineSync: Bool { !pendingIntents.isEmpty }
    /// How many local-only points are awaiting relay to iPhone.
    var offlineDelta: Int { pendingIntents.count }

    // MARK: - Init

    #if os(watchOS)
    /// Production initialiser — uses live WCSession and WatchSessionManager.
    /// Only available on watchOS because WatchSessionManager is a watchOS target class.
    convenience init() {
        self.init(
            isReachable: { WCSession.default.isReachable },
            sendIntent: { WatchSessionManager.shared.sendScoringIntent(side: $0) },
            userDefaults: .standard
        )
    }
    #endif

    /// Testable initialiser — inject any reachability closure, intent sender, and UserDefaults suite.
    /// Used directly by unit tests running in the iOS test host.
    init(
        isReachable: @escaping () -> Bool,
        sendIntent: @escaping (Side) -> Void,
        userDefaults: UserDefaults = .standard
    ) {
        self.isReachable = isReachable
        self.sendIntent = sendIntent
        self.userDefaults = userDefaults
        #if os(watchOS)
        WatchSessionManager.shared.onStateReceived = { [weak self] payload in
            self?.receiveStateFromiPhone(payload)
        }
        #endif
        restoreFromUserDefaults()
    }

    // MARK: - Scoring

    /// Score a point for the given side. Sends intent to iPhone if reachable,
    /// otherwise uses local MatchEngine for immediate UI feedback and queues
    /// the intent for relay when connectivity is restored.
    func scorePoint(for side: Side) {
        guard let currentState = state, currentState.matchPhase == .inProgress else { return }

        if isReachable() && !localEngine {
            // Online: send intent to iPhone for authoritative processing
            sendIntent(side)
        } else {
            // Offline: score locally and queue intent for relay on reconnect
            isOffline = true
            localEngine = true
            pendingIntents.append(PendingIntent(side: side, timestamp: Date()))
        }

        // Always apply locally for immediate UI update
        state = MatchEngine.apply(event: .scorePoint(side), to: currentState)
        persistToUserDefaults()

        // If match just completed via local scoring, end workout
        if !isMatchActive {
            #if os(watchOS)
            let wm = workoutManager
            Task { await wm.endWorkout() }
            #endif
        }
    }

    /// Start workout if match is in progress but workout hasn't started yet.
    /// Called on restore from UserDefaults to resume workout tracking.
    func startWorkoutIfNeeded() async {
        #if os(watchOS)
        if state?.matchPhase == .inProgress && !workoutManager.isWorkoutActive {
            try? await workoutManager.startWorkout()
        }
        #endif
    }

    // MARK: - Receiving State from iPhone

    /// iPhone-authoritative: adopt the iPhone's state on reconnection.
    ///
    /// Offline reconciliation: if the Watch accumulated local-only scoring
    /// intents while offline, they are replayed to iPhone before adopting its
    /// state. iPhone will process the queued delta and echo back the merged
    /// authoritative state, which we then adopt on the next call.
    func receiveStateFromiPhone(_ payload: SyncPayload) {
        let wasActive = state?.matchPhase == .inProgress
        let previousGamesCount = state?.games.count ?? 0
        let wasLocallyUpdated = localEngine

        // Offline reconciliation: replay queued intents so iPhone can apply
        // the delta authoritatively before we adopt its state.
        if wasLocallyUpdated && !pendingIntents.isEmpty {
            if isReachable() {
                replayPendingIntents()
                // Adopt iPhone baseline; the next echo will carry the merged state.
            } else {
                // Still not reachable — keep local state and wait for next iPhone push.
                return
            }
        }

        state = payload.matchState.toMatchState()
        localEngine = false
        isOffline = false

        let isNowActive = state?.matchPhase == .inProgress

        #if os(watchOS)
        let wm = workoutManager
        if !wasActive && isNowActive {
            // Match just started -- begin HealthKit workout
            Task { try? await wm.startWorkout() }
        } else if wasActive && !isNowActive {
            // Match just ended -- end HealthKit workout
            Task { await wm.endWorkout() }
        }

        if !payload.isMatchActive {
            // Match ended on iPhone; keep final state for display
            Task { await wm.endWorkout() }
        }
        #endif

        // Play haptic for iPhone-initiated changes only.
        // Skip if localEngine was true — Watch already played haptic for this point.
        if !wasLocallyUpdated {
            playReceiveHaptic(previousGamesCount: previousGamesCount,
                              wasActive: wasActive,
                              isNowActive: isNowActive)
        }

        persistToUserDefaults()
    }

    // MARK: - UserDefaults Persistence

    /// Persist current state to UserDefaults for SIGKILL recovery.
    func persistToUserDefaults() {
        guard let state = state else { return }

        let codable = CodableMatchState(from: state)
        if let data = try? JSONEncoder().encode(codable) {
            userDefaults.set(data, forKey: "watchMatchState")
        }
        userDefaults.set(isOffline, forKey: "watchIsOffline")

        // Persist pending offline intents so they survive SIGKILL.
        if let intentData = try? JSONEncoder().encode(pendingIntents) {
            userDefaults.set(intentData, forKey: "watchPendingIntents")
        }
    }

    /// Restore state from UserDefaults on launch.
    func restoreFromUserDefaults() {
        guard let data = userDefaults.data(forKey: "watchMatchState") else { return }
        guard let codable = try? JSONDecoder().decode(CodableMatchState.self, from: data) else { return }

        let restored = codable.toMatchState()
        guard restored.matchPhase == .inProgress else {
            // Don't restore completed/abandoned matches
            clearLocalPersistence()
            return
        }

        state = restored
        isOffline = userDefaults.bool(forKey: "watchIsOffline")
        if isOffline {
            localEngine = true
        }

        // Restore pending offline intents.
        if let intentData = userDefaults.data(forKey: "watchPendingIntents"),
           let intents = try? JSONDecoder().decode([PendingIntent].self, from: intentData) {
            pendingIntents = intents
        }
    }

    /// Clear persisted state (called when match ends or is dismissed).
    func clearLocalPersistence() {
        userDefaults.removeObject(forKey: "watchMatchState")
        userDefaults.removeObject(forKey: "watchIsOffline")
        userDefaults.removeObject(forKey: "watchPendingIntents")
    }

    // MARK: - Private

    /// Relay queued offline intents to iPhone in chronological order.
    /// Clears the queue immediately so the next iPhone echo is adopted normally.
    private func replayPendingIntents() {
        let intents = pendingIntents
        pendingIntents = []
        userDefaults.removeObject(forKey: "watchPendingIntents")
        for intent in intents {
            sendIntent(intent.side)
        }
    }

    private var hapticEnabled: Bool {
        userDefaults.object(forKey: "hapticFeedbackEnabled") as? Bool ?? true
    }

    private func playReceiveHaptic(previousGamesCount: Int, wasActive: Bool, isNowActive: Bool) {
        #if os(watchOS)
        guard hapticEnabled else { return }
        if wasActive && !isNowActive {
            // Match just ended
            WKInterfaceDevice.current().play(.notification)
        } else if let games = state?.games, games.count > previousGamesCount {
            // Game just completed
            WKInterfaceDevice.current().play(.success)
        } else if isNowActive {
            // Regular point scored
            WKInterfaceDevice.current().play(.click)
        }
        #endif
    }
}
