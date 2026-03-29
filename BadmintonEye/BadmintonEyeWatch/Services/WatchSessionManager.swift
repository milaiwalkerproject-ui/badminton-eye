import Foundation
import WatchConnectivity
import ScoringEngine

/// watchOS-side WCSessionDelegate singleton.
/// Receives match state from iPhone and delivers to WatchMatchViewModel.
/// Sends scoring intents back to iPhone when user taps score buttons.
final class WatchSessionManager: NSObject, WCSessionDelegate, @unchecked Sendable {

    static let shared = WatchSessionManager()

    /// Called when a SyncPayload arrives from the iPhone.
    var onStateReceived: ((SyncPayload) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - Activation

    func activate() {
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Sending Scoring Intents to iPhone

    /// Send a scoring intent to the iPhone. Uses sendMessage for immediate delivery
    /// when reachable, and updateApplicationContext as fallback.
    func sendScoringIntent(side: Side) {
        let dict: [String: Any] = [
            "action": "scorePoint",
            "side": side.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(dict, replyHandler: nil, errorHandler: nil)
        }

        // Also send via applicationContext as fallback
        try? WCSession.default.updateApplicationContext(dict)
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // No-op; activation is fire-and-forget on watchOS
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleIncomingState(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncomingState(message)
    }

    // MARK: - Private

    private func handleIncomingState(_ dictionary: [String: Any]) {
        guard let payload = SyncPayload.from(dictionary: dictionary) else { return }

        Task { @MainActor in
            self.onStateReceived?(payload)
        }
    }
}
