// WCSessionProtocol.swift
// Abstracts WCSession so WatchSyncManager and WatchSessionManager are
// dependency-injectable and unit-testable without a real WCSession.
//
// Compiled into both the iOS (BadmintonEye) and watchOS (BadmintonEyeWatch) targets.

import WatchConnectivity

// MARK: - Protocol

/// Minimal WCSession surface used by WatchSyncManager / WatchSessionManager.
/// Production code uses `WCSession.default`; tests inject `MockWCSession`.
protocol WCSessionProtocol: AnyObject {
    /// Whether the paired counterpart app is reachable right now.
    var isReachable: Bool { get }

    /// Current activation state of the session.
    var activationState: WCSessionActivationState { get }

    /// Send a high-priority message. Calls `errorHandler` on failure.
    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((Error) -> Void)?
    )

    /// Push a key-value context dictionary; delivered on next opportunity.
    func updateApplicationContext(_ applicationContext: [String: Any]) throws
}

// MARK: - WCSession conformance

extension WCSession: WCSessionProtocol {}
