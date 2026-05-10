import Foundation
import WatchConnectivity
import WatchKit
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
@Observable
@MainActor
final class WatchMatchViewModel {

    // MARK: - Types

    /// A scoring intent queued while the Watch was offline.
    private struct PendingIntent: Codable {
        let side: Side
        let timestamp: Date
    }

    // MARK: - State

    private(set) var state: MatchState?
    private(set) var isOffline: Bool = false
    private var localEngine: Bool = false
    /// Scoring intents accumulated while the Watch was offline.
    private var pendingIntents: [PendingIntent] = []

    private let workoutManager = WorkoutManager.shared

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

    init() {
        WatchSessionManager.shared.onStateReceived = { [weak self] payload in
            self?.receiveStateFromiPhone(payload)
        }
        restoreFromUserDefaults()
    }

    // MARK: - Scoring

    /// Score a point for the given side. Sends intent to iPhone if reachable,
    /// otherwise uses local MatchEngine for immediate UI feedback and queues
    /// the intent for relay when connectivity is restored.
    func scorePoint(for side: Side) {
        guard let currentState = state, currentState.matchPhase == .inProgress else { return }

        if WCSession.default.isReachable && !localEngine {
            // Online: send intent to iPhone for authoritative processing
            WatchSessionManager.shared.sendScoringIntent(side: side)
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
            let wm = workoutManager
            Task { await wm.endWorkout() }
        }
    }

    /// Start workout if match is in progress but workout hasn't started yet.
    /// Called on restore from UserDefaults to resume workout tracking.
    func startWorkoutIfNeeded() async {
        if state?.matchPhase == .inProgress && !workoutManager.isWorkoutActive {
            try? await workoutManager.startWorkout()
        }
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
            if WCSession.default.isReachable {
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
            UserDefaults.standard.set(data, forKey: "watchMatchState")
        }
        UserDefaults.standard.set(isOffline, forKey: "watchIsOffline")

        // Persist pending offline intents so they survive SIGKILL.
        if let intentData = try? JSONEncoder().encode(pendingIntents) {
            UserDefaults.standard.set(intentData, forKey: "watchPendingIntents")
        }
    }

    /// Restore state from UserDefaults on launch.
    func restoreFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: "watchMatchState") else { return }
        guard let codable = try? JSONDecoder().decode(CodableMatchState.self, from: data) else { return }

        let restored = codable.toMatchState()
        guard restored.matchPhase == .inProgress else {
            // Don't restore completed/abandoned matches
            clearLocalPersistence()
            return
        }

        state = restored
        isOffline = UserDefaults.standard.bool(forKey: "watchIsOffline")
        if isOffline {
            localEngine = true
        }

        // Restore pending offline intents.
        if let intentData = UserDefaults.standard.data(forKey: "watchPendingIntents"),
           let intents = try? JSONDecoder().decode([PendingIntent].self, from: intentData) {
            pendingIntents = intents
        }
    }

    /// Clear persisted state (called when match ends or is dismissed).
    func clearLocalPersistence() {
        UserDefaults.standard.removeObject(forKey: "watchMatchState")
        UserDefaults.standard.removeObject(forKey: "watchIsOffline")
        UserDefaults.standard.removeObject(forKey: "watchPendingIntents")
    }

    // MARK: - Private

    /// Relay queued offline intents to iPhone in chronological order.
    /// Clears the queue immediately so the next iPhone echo is adopted normally.
    private func replayPendingIntents() {
        let intents = pendingIntents
        pendingIntents = []
        UserDefaults.standard.removeObject(forKey: "watchPendingIntents")
        for intent in intents {
            WatchSessionManager.shared.sendScoringIntent(side: intent.side)
        }
    }

    private var hapticEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticFeedbackEnabled") as? Bool ?? true
    }

    private func playReceiveHaptic(previousGamesCount: Int, wasActive: Bool, isNowActive: Bool) {
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
    }
}
