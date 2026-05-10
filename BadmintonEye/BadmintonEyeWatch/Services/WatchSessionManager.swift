import Foundation
import os.log
import WatchConnectivity
import ScoringEngine

private let logger = Logger(subsystem: "com.badmintoneye.app.watchkitapp", category: "WatchSessionManager")

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
    /// when reachable, and updateApplicationContext as fallback for guaranteed delivery.
    func sendScoringIntent(side: Side) {
        let dict: [String: Any] = [
            "action": "scorePoint",
            "side": side.rawValue,
            "timestamp": Date().timeIntervalSince1970
        ]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(dict, replyHandler: nil) { error in
                // sendMessage failed mid-flight (session became unreachable after isReachable check).
                // Log the failure and fall back to applicationContext for guaranteed delivery.
                logger.error("sendMessage failed: \(error.localizedDescription, privacy: .public) — retrying via updateApplicationContext")
                try? WCSession.default.updateApplicationContext(dict)
            }
        } else {
            // Not reachable — go straight to applicationContext for guaranteed delivery.
            try? WCSession.default.updateApplicationContext(dict)
        }
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
