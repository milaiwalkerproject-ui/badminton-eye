// WatchSyncManagerTests.swift
// Unit tests for WatchSyncManager (iOS-side WC session handler).
// Uses MockWCSession to test sendMessage → errorHandler fallback path
// without requiring a live Watch or WCSession.

import XCTest
import WatchConnectivity
@testable import BadmintonEye

// MARK: - MockWCSession

/// Test double for WCSessionProtocol.
/// Records calls to sendMessage and updateApplicationContext for assertion.
final class MockWCSession: WCSessionProtocol {

    // MARK: Configuration

    /// Controls the value returned by `isReachable`.
    var stubbedIsReachable: Bool = false

    /// Controls the value returned by `activationState`.
    var stubbedActivationState: WCSessionActivationState = .activated

    // MARK: Recorded Calls

    private(set) var sendMessageCalls: [[String: Any]] = []
    private(set) var applicationContextUpdates: [[String: Any]] = []

    /// If set, the next `sendMessage` call will invoke this error handler instead of succeeding.
    var sendMessageError: Error?

    // MARK: - WCSessionProtocol

    var isReachable: Bool { stubbedIsReachable }
    var activationState: WCSessionActivationState { stubbedActivationState }

    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((Error) -> Void)?
    ) {
        sendMessageCalls.append(message)
        if let error = sendMessageError {
            errorHandler?(error)
        }
    }

    func updateApplicationContext(_ applicationContext: [String: Any]) throws {
        applicationContextUpdates.append(applicationContext)
    }
}

// MARK: - WatchSyncManagerTests

final class WatchSyncManagerTests: XCTestCase {

    private var mockSession: MockWCSession!
    private var manager: WatchSyncManager!

    override func setUp() {
        super.setUp()
        mockSession = MockWCSession()
        manager = WatchSyncManager(session: mockSession)
    }

    override func tearDown() {
        manager = nil
        mockSession = nil
        super.tearDown()
    }

    // MARK: - sendStateUpdate: Not Activated

    func testSendStateUpdateDoesNothingWhenNotActivated() {
        mockSession.stubbedActivationState = .notActivated
        mockSession.stubbedIsReachable = true

        let state = MatchState.newSinglesMatch()
        manager.sendStateUpdate(state, isActive: true)

        XCTAssertTrue(mockSession.sendMessageCalls.isEmpty,
                      "No sendMessage when session is not activated")
        XCTAssertTrue(mockSession.applicationContextUpdates.isEmpty,
                      "No updateApplicationContext when session is not activated")
    }

    // MARK: - sendStateUpdate: Reachable Path

    func testSendStateUpdateUsesSendMessageWhenReachable() {
        mockSession.stubbedActivationState = .activated
        mockSession.stubbedIsReachable = true

        let state = MatchState.newSinglesMatch()
        manager.sendStateUpdate(state, isActive: true)

        // Guaranteed delivery (applicationContext) + fast path (sendMessage)
        XCTAssertEqual(mockSession.applicationContextUpdates.count, 1,
                       "applicationContext used for guaranteed delivery")
        XCTAssertEqual(mockSession.sendMessageCalls.count, 1,
                       "sendMessage used for fast delivery when reachable")
    }

    // MARK: - sendStateUpdate: Unreachable Path

    func testSendStateUpdateUsesOnlyApplicationContextWhenNotReachable() {
        mockSession.stubbedActivationState = .activated
        mockSession.stubbedIsReachable = false

        let state = MatchState.newSinglesMatch()
        manager.sendStateUpdate(state, isActive: true)

        XCTAssertEqual(mockSession.applicationContextUpdates.count, 1,
                       "applicationContext used even when not reachable")
        XCTAssertTrue(mockSession.sendMessageCalls.isEmpty,
                      "sendMessage must NOT be called when not reachable")
    }

    // MARK: - sendMessage → errorHandler Fallback

    func testSendStateUpdateFallsBackToApplicationContextOnSendMessageError() {
        mockSession.stubbedActivationState = .activated
        mockSession.stubbedIsReachable = true
        mockSession.sendMessageError = NSError(
            domain: "WCErrorDomain", code: 7007,
            userInfo: [NSLocalizedDescriptionKey: "Session became unreachable"])

        let state = MatchState.newSinglesMatch()
        manager.sendStateUpdate(state, isActive: true)

        // Guaranteed delivery happens before fast path
        // Fast path calls sendMessage which fires errorHandler — no extra applicationContext
        // because WatchSyncManager's sendStateUpdate error handler is { _ in }
        XCTAssertEqual(mockSession.applicationContextUpdates.count, 1,
                       "Guaranteed delivery applicationContext written before sendMessage attempt")
        XCTAssertEqual(mockSession.sendMessageCalls.count, 1,
                       "sendMessage was attempted (and failed)")
    }
}

// MARK: - WatchSessionManagerSendIntentTests
// Tests the watchOS WatchSessionManager's sendScoringIntent via the shared protocol.
// (No WatchKit/HealthKit required because WatchSessionManager only calls WCSession methods.)

final class WatchSessionManagerSendIntentTests: XCTestCase {

    private var mockSession: MockWCSession!
    private var manager: WatchSessionManager!

    override func setUp() {
        super.setUp()
        mockSession = MockWCSession()
        manager = WatchSessionManager(session: mockSession)
    }

    override func tearDown() {
        manager = nil
        mockSession = nil
        super.tearDown()
    }

    // MARK: - Reachable: sendMessage used

    func testSendScoringIntentUsesSendMessageWhenReachable() {
        mockSession.stubbedIsReachable = true

        manager.sendScoringIntent(side: .sideA)

        XCTAssertEqual(mockSession.sendMessageCalls.count, 1)
        let msg = mockSession.sendMessageCalls[0]
        XCTAssertEqual(msg["action"] as? String, "scorePoint")
        XCTAssertEqual(msg["side"] as? String, Side.sideA.rawValue)
        XCTAssertTrue(mockSession.applicationContextUpdates.isEmpty,
                      "applicationContext should NOT be used when sendMessage succeeds")
    }

    // MARK: - Unreachable: applicationContext used

    func testSendScoringIntentUsesApplicationContextWhenNotReachable() {
        mockSession.stubbedIsReachable = false

        manager.sendScoringIntent(side: .sideB)

        XCTAssertTrue(mockSession.sendMessageCalls.isEmpty,
                      "sendMessage must NOT be called when not reachable")
        XCTAssertEqual(mockSession.applicationContextUpdates.count, 1)
        let ctx = mockSession.applicationContextUpdates[0]
        XCTAssertEqual(ctx["action"] as? String, "scorePoint")
        XCTAssertEqual(ctx["side"] as? String, Side.sideB.rawValue)
    }

    // MARK: - sendMessage → errorHandler fallback (P1 requirement)

    func testSendScoringIntentFallsBackToApplicationContextOnSendMessageError() {
        mockSession.stubbedIsReachable = true
        mockSession.sendMessageError = NSError(
            domain: "WCErrorDomain", code: 7007,
            userInfo: [NSLocalizedDescriptionKey: "Session became unreachable"])

        manager.sendScoringIntent(side: .sideA)

        // sendMessage attempted once
        XCTAssertEqual(mockSession.sendMessageCalls.count, 1,
                       "sendMessage was attempted")
        // errorHandler must have triggered applicationContext fallback
        XCTAssertEqual(mockSession.applicationContextUpdates.count, 1,
                       "errorHandler must fall back to updateApplicationContext")
        let ctx = mockSession.applicationContextUpdates[0]
        XCTAssertEqual(ctx["action"] as? String, "scorePoint",
                       "Fallback applicationContext carries the scoring intent")
    }
}
