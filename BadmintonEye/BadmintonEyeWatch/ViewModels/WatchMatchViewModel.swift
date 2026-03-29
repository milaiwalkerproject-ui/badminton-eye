import Foundation
import WatchConnectivity
import ScoringEngine

/// ViewModel driving the Watch match UI.
/// Supports offline scoring via local MatchEngine when iPhone is unreachable.
/// Persists state to UserDefaults after every point for SIGKILL protection.
/// iPhone-authoritative: adopts iPhone state on reconnection.
@Observable
final class WatchMatchViewModel {

    private(set) var state: MatchState?
    private(set) var isOffline: Bool = false
    private var localEngine: Bool = false

    // MARK: - Computed Properties

    var scoreA: Int { state?.currentGame.scoreA ?? 0 }
    var scoreB: Int { state?.currentGame.scoreB ?? 0 }
    var teamAName: String { state?.teamANames.first ?? "Side A" }
    var teamBName: String { state?.teamBNames.first ?? "Side B" }
    var servingSide: Side? { state?.currentServer.side }
    var currentGameNumber: Int { state?.currentGame.gameNumber ?? 0 }
    var isMatchActive: Bool { state != nil && state?.matchPhase == .inProgress }
    var completedGames: [GameState] { state?.games ?? [] }

    // MARK: - Init

    init() {
        WatchSessionManager.shared.onStateReceived = { [weak self] payload in
            self?.receiveStateFromiPhone(payload)
        }
        restoreFromUserDefaults()
    }

    // MARK: - Scoring

    /// Score a point for the given side. Sends intent to iPhone if reachable,
    /// otherwise uses local MatchEngine for immediate UI feedback.
    /// Always persists to UserDefaults.
    func scorePoint(for side: Side) {
        guard let currentState = state, currentState.matchPhase == .inProgress else { return }

        if WCSession.default.isReachable && !localEngine {
            // Online: send intent to iPhone for authoritative processing
            WatchSessionManager.shared.sendScoringIntent(side: side)
        } else {
            // Offline: score locally
            isOffline = true
            localEngine = true
        }

        // Always apply locally for immediate UI update
        state = MatchEngine.apply(event: .scorePoint(side), to: currentState)
        persistToUserDefaults()
    }

    // MARK: - Receiving State from iPhone

    /// iPhone-authoritative: adopt the iPhone's state unconditionally.
    func receiveStateFromiPhone(_ payload: SyncPayload) {
        state = payload.matchState.toMatchState()
        localEngine = false
        isOffline = false

        if !payload.isMatchActive {
            // Match ended on iPhone; keep final state for display
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
    }

    /// Clear persisted state (called when match ends or is dismissed).
    func clearLocalPersistence() {
        UserDefaults.standard.removeObject(forKey: "watchMatchState")
        UserDefaults.standard.removeObject(forKey: "watchIsOffline")
    }
}
