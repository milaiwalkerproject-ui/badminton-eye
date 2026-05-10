// WatchMatchViewModelTests.swift
// Tests for WatchMatchViewModel's offline scoring reconciliation logic.
//
// Uses the injected isReachable closure + sendIntent closure (task 8b2b9d3f)
// so tests run in the iOS test host without requiring WKInterfaceDevice.
//
// Covers the 4 scenarios required by CTO (task ed7a2c65):
//   1. offline-score-queues-intent
//   2. reconnect-with-reachable-replays-and-clears
//   3. reconnect-unreachable-keeps-local-and-returns-early
//   4. SIGKILL-restores-pendingIntents-from-UserDefaults

import XCTest
import ScoringEngine
@testable import BadmintonEye

@MainActor
final class WatchMatchViewModelTests: XCTestCase {

    // MARK: - Helpers

    /// Isolated UserDefaults suite for each test (avoids polluting .standard).
    private var testDefaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        testDefaults = UserDefaults(suiteName: "WatchMatchViewModelTests-\(UUID().uuidString)")!
    }

    override func tearDown() async throws {
        testDefaults.removePersistentDomain(forName: testDefaults.suiteName!)
        testDefaults = nil
        try await super.tearDown()
    }

    /// Creates a ViewModel with an active in-progress match state already set.
    /// - Parameters:
    ///   - reachable: initial reachability
    ///   - sentIntents: mutable array that records forwarded scoring intents
    private func makeVM(
        reachable: Bool,
        sentIntents: inout [Side]
    ) -> WatchMatchViewModel {
        var capturedIntents = sentIntents
        let vm = WatchMatchViewModel(
            isReachable: { reachable },
            sendIntent: { capturedIntents.append($0) },
            userDefaults: testDefaults
        )
        sentIntents = capturedIntents
        return vm
    }

    /// Creates a VM with a closure-based reachability toggle.
    private func makeVMWithToggle(
        reachableBox: Ref<Bool>,
        sentIntents: inout [Side]
    ) -> WatchMatchViewModel {
        var intents = sentIntents
        let vm = WatchMatchViewModel(
            isReachable: { reachableBox.value },
            sendIntent: { intents.append($0); sentIntents = intents },
            userDefaults: testDefaults
        )
        return vm
    }

    /// Injects a valid in-progress MatchState into the VM via the UserDefaults pathway.
    private func seedMatchState(into vm: WatchMatchViewModel) {
        let state = MatchState.newSinglesMatch()
        let codable = CodableMatchState(from: state)
        if let data = try? JSONEncoder().encode(codable) {
            testDefaults.set(data, forKey: "watchMatchState")
        }
        vm.restoreFromUserDefaults()
    }

    /// Builds a SyncPayload dictionary for a singles match.
    private func makeSyncPayload(isActive: Bool = true) -> SyncPayload {
        let state = MatchState.newSinglesMatch()
        return SyncPayload(from: state, isActive: isActive)
    }

    // MARK: - 1. offline-score-queues-intent

    /// When the Watch is offline (not reachable) and the user taps score,
    /// the intent must be queued in pendingIntents and NOT forwarded to iPhone.
    func testOfflineScoreQueuesIntent() {
        var sent: [Side] = []
        let vm = WatchMatchViewModel(
            isReachable: { false },
            sendIntent: { sent.append($0) },
            userDefaults: testDefaults
        )
        seedMatchState(into: vm)

        vm.scorePoint(for: .sideA)

        XCTAssertTrue(sent.isEmpty,
                      "No intent should be forwarded to iPhone when offline")
        XCTAssertEqual(vm.pendingIntents.count, 1,
                       "Intent must be queued in pendingIntents")
        XCTAssertEqual(vm.pendingIntents.first?.side, .sideA)
        XCTAssertTrue(vm.isOffline, "VM should be marked offline")
        XCTAssertTrue(vm.needsOfflineSync, "needsOfflineSync should be true")
    }

    func testMultipleOfflineScoresQueueAllIntents() {
        var sent: [Side] = []
        let vm = WatchMatchViewModel(
            isReachable: { false },
            sendIntent: { sent.append($0) },
            userDefaults: testDefaults
        )
        seedMatchState(into: vm)

        vm.scorePoint(for: .sideA)
        vm.scorePoint(for: .sideB)
        vm.scorePoint(for: .sideA)

        XCTAssertEqual(vm.pendingIntents.count, 3)
        XCTAssertEqual(vm.offlineDelta, 3)
        XCTAssertTrue(sent.isEmpty)
    }

    // MARK: - 2. reconnect-with-reachable-replays-and-clears

    /// When the iPhone sends a state update while the Watch has queued intents,
    /// and the session IS reachable, the intents must be replayed and then cleared.
    func testReconnectWithReachableReplaysAndClearsPendingIntents() {
        var sent: [Side] = []
        // First, go offline and accumulate intents
        let vm = WatchMatchViewModel(
            isReachable: { false },
            sendIntent: { sent.append($0) },
            userDefaults: testDefaults
        )
        seedMatchState(into: vm)
        vm.scorePoint(for: .sideA)
        vm.scorePoint(for: .sideB)
        XCTAssertEqual(vm.pendingIntents.count, 2)

        // Simulate reconnect: a fresh VM with reachable=true receives iPhone state
        var sentOnReconnect: [Side] = []
        let reachableVM = WatchMatchViewModel(
            isReachable: { true },
            sendIntent: { sentOnReconnect.append($0) },
            userDefaults: testDefaults
        )
        // Restore the offline state (simulates SIGKILL/re-init)
        reachableVM.restoreFromUserDefaults()
        XCTAssertEqual(reachableVM.pendingIntents.count, 2, "Intents restored from UserDefaults")

        let payload = makeSyncPayload(isActive: true)
        reachableVM.receiveStateFromiPhone(payload)

        // Intents replayed to iPhone
        XCTAssertEqual(sentOnReconnect.count, 2,
                       "Both queued intents must be replayed to iPhone on reconnect")
        XCTAssertEqual(sentOnReconnect[0], .sideA)
        XCTAssertEqual(sentOnReconnect[1], .sideB)

        // Queue cleared after replay
        XCTAssertTrue(reachableVM.pendingIntents.isEmpty,
                      "pendingIntents must be cleared after replay")
        XCTAssertFalse(reachableVM.isOffline,
                       "VM should be marked online after adopting iPhone state")
    }

    // MARK: - 3. reconnect-unreachable-keeps-local-and-returns-early

    /// When the iPhone sends a state update while the Watch has queued intents,
    /// but the session is STILL not reachable, the local state must be kept
    /// and the function must return early without adopting iPhone state.
    func testReconnectUnreachableKeepsLocalAndReturnsEarly() {
        var sent: [Side] = []
        let vm = WatchMatchViewModel(
            isReachable: { false },
            sendIntent: { sent.append($0) },
            userDefaults: testDefaults
        )
        seedMatchState(into: vm)

        vm.scorePoint(for: .sideA)
        let localScoreA = vm.scoreA
        XCTAssertEqual(vm.pendingIntents.count, 1)

        // iPhone sends state — but we're still not reachable
        let payload = makeSyncPayload(isActive: true)
        vm.receiveStateFromiPhone(payload)

        // Local state preserved (not replaced by iPhone's fresh-match state)
        XCTAssertEqual(vm.scoreA, localScoreA,
                       "Local score must be preserved when session still unreachable")
        XCTAssertEqual(vm.pendingIntents.count, 1,
                       "pendingIntents must NOT be cleared when still unreachable")
        XCTAssertTrue(vm.isOffline, "VM must remain offline")
        XCTAssertTrue(sent.isEmpty, "No intent forwarded while still unreachable")
    }

    // MARK: - 4. SIGKILL-restores-pendingIntents-from-UserDefaults

    /// After a SIGKILL, the next launch restores pendingIntents from UserDefaults
    /// so queued offline intents are not lost and will be replayed on next reconnect.
    func testSIGKILLRestoresPendingIntentsFromUserDefaults() {
        // Phase 1: score offline to build up intents, then "kill" the app
        let vm1 = WatchMatchViewModel(
            isReachable: { false },
            sendIntent: { _ in },
            userDefaults: testDefaults
        )
        seedMatchState(into: vm1)
        vm1.scorePoint(for: .sideA)
        vm1.scorePoint(for: .sideA)
        vm1.scorePoint(for: .sideB)

        // Verify intents were persisted (persistToUserDefaults called by scorePoint)
        let savedData = testDefaults.data(forKey: "watchPendingIntents")
        XCTAssertNotNil(savedData, "pendingIntents must be persisted to UserDefaults")

        // Phase 2: new VM (simulates re-launch after SIGKILL) restores state
        var sentAfterRestore: [Side] = []
        let vm2 = WatchMatchViewModel(
            isReachable: { true },
            sendIntent: { sentAfterRestore.append($0) },
            userDefaults: testDefaults
        )
        // restoreFromUserDefaults() is called in WatchMatchViewModel.init
        // via the production convenience init, but our testable init also calls it

        XCTAssertEqual(vm2.pendingIntents.count, 3,
                       "All 3 pending intents must survive SIGKILL via UserDefaults")
        XCTAssertEqual(vm2.pendingIntents[0].side, .sideA)
        XCTAssertEqual(vm2.pendingIntents[1].side, .sideA)
        XCTAssertEqual(vm2.pendingIntents[2].side, .sideB)

        // Phase 3: on reconnect, all queued intents are replayed
        let payload = makeSyncPayload(isActive: true)
        vm2.receiveStateFromiPhone(payload)

        XCTAssertEqual(sentAfterRestore.count, 3,
                       "All restored intents must be replayed on reconnect")
        XCTAssertTrue(vm2.pendingIntents.isEmpty,
                      "Queue cleared after successful replay")
    }

    // MARK: - Online path: intent forwarded immediately

    func testOnlineScoreForwardsIntentImmediately() {
        var sent: [Side] = []
        let vm = WatchMatchViewModel(
            isReachable: { true },
            sendIntent: { sent.append($0) },
            userDefaults: testDefaults
        )
        seedMatchState(into: vm)

        vm.scorePoint(for: .sideB)

        XCTAssertEqual(sent.count, 1, "Intent forwarded immediately when online")
        XCTAssertEqual(sent[0], .sideB)
        XCTAssertTrue(vm.pendingIntents.isEmpty, "No pending intents when online")
    }
}

// MARK: - Ref helper (mutable reference box for closure capture)

/// Simple mutable reference box used to toggle reachability inside a closure.
final class Ref<T> {
    var value: T
    init(_ value: T) { self.value = value }
}
