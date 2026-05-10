import Foundation
import WatchConnectivity
import ScoringEngine

/// iOS-side WCSessionDelegate singleton.
/// Sends match state to the Watch via dual transport (applicationContext + message).
/// Receives scoring intents from the Watch and forwards via callback.
final class WatchSyncManager: NSObject, WCSessionDelegate, @unchecked Sendable {

    static let shared = WatchSyncManager()

    /// Called when the Watch sends a scoring intent (scorePoint for a side).
    var onScoringIntentReceived: ((Side) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - Activation

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Sending State to Watch

    func sendStateUpdate(_ state: MatchState, isActive: Bool) {
        guard WCSession.default.activationState == .activated else { return }

        let payload = SyncPayload(from: state, isActive: isActive)
        guard let dict = payload.toDictionary() else { return }

        // Guaranteed delivery (persisted, delivered on next launch)
        try? WCSession.default.updateApplicationContext(dict)

        // Fast path (immediate if reachable, non-fatal if not)
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(dict, replyHandler: nil) { _ in }
        }
    }

    func sendMatchEnd(_ state: MatchState) {
        sendStateUpdate(state, isActive: false)
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // No-op; activation is fire-and-forget on iOS
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        // Required on iOS for multi-watch support
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate for next session (multi-watch support)
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleIncomingMessage(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncomingMessage(message)
    }

    // MARK: - Handling Watch Scoring Intents

    private func handleIncomingMessage(_ message: [String: Any]) {
        // Watch sends scoring intents as: ["action": "scorePoint", "side": sideRawValue, "timestamp": TimeInterval]
        guard let action = message["action"] as? String,
              action == "scorePoint",
              let sideRaw = message["side"] as? String,
              let side = Side(rawValue: sideRaw) else {
            return
        }

        Task { @MainActor in
            self.onScoringIntentReceived?(side)
        }
    }
}
