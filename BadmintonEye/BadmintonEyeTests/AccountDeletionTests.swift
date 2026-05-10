// AccountDeletionTests.swift
// Tests for AuthManager.deleteAccount — verifies GDPR / App Store 5.1.1(v) compliance.
//
// Coverage:
//   - UserDefaults domain wipe (all keys, not just 3 auth keys)
//   - isDeletingAccount state transitions
//   - accountDeleted flag set on success
//   - SwiftData batch delete via in-memory ModelContainer
//   - Guard: no-op when not signed in
//   - Error state is nil on success

import XCTest
import SwiftData
@testable import BadmintonEye

@MainActor
final class AccountDeletionTests: XCTestCase {

    // MARK: - Helpers

    /// Returns an in-memory ModelContext for isolated SwiftData tests.
    private func makeInMemoryContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PersistedMatch.self, configurations: config)
        return ModelContext(container)
    }

    /// Seeds the auth state so deleteAccount has something to clean up.
    private func seedAuthState() {
        UserDefaults.standard.set("fake-uid-123", forKey: "appleUserIdentifier")
        UserDefaults.standard.set("Test User", forKey: "appleUserName")
        UserDefaults.standard.set("test@example.com", forKey: "appleUserEmail")
        // Extra app prefs to verify full-domain wipe (not just 3 auth keys)
        UserDefaults.standard.set(true, forKey: "hapticFeedbackEnabled")
        UserDefaults.standard.set(42, forKey: "someOtherAppKey")
    }

    // MARK: - UserDefaults Wipe

    func testDeleteAccountWipesAllUserDefaultsKeys() async throws {
        seedAuthState()
        let context = try makeInMemoryContext()
        let manager = AuthManager.shared

        try await manager.deleteAccount(context: context)

        XCTAssertNil(UserDefaults.standard.string(forKey: "appleUserIdentifier"),
                     "appleUserIdentifier must be wiped")
        XCTAssertNil(UserDefaults.standard.string(forKey: "appleUserName"),
                     "appleUserName must be wiped")
        XCTAssertNil(UserDefaults.standard.string(forKey: "appleUserEmail"),
                     "appleUserEmail must be wiped")
        XCTAssertNil(UserDefaults.standard.object(forKey: "hapticFeedbackEnabled"),
                     "hapticFeedbackEnabled must be wiped by domain removal")
        XCTAssertNil(UserDefaults.standard.object(forKey: "someOtherAppKey"),
                     "Extra app keys must be wiped by domain removal")
    }

    // MARK: - State Transitions

    func testDeleteAccountResetsDeletingFlagAfterCompletion() async throws {
        seedAuthState()
        let context = try makeInMemoryContext()
        let manager = AuthManager.shared

        XCTAssertFalse(manager.isDeletingAccount, "isDeletingAccount must start false")
        try await manager.deleteAccount(context: context)
        XCTAssertFalse(manager.isDeletingAccount,
                       "isDeletingAccount must be false after deleteAccount completes (defer resets it)")
    }

    func testDeleteAccountSetsAccountDeletedFlagOnSuccess() async throws {
        seedAuthState()
        let context = try makeInMemoryContext()
        let manager = AuthManager.shared
        manager.accountDeleted = false

        try await manager.deleteAccount(context: context)

        XCTAssertTrue(manager.accountDeleted,
                      "accountDeleted must be true after successful deleteAccount")
    }

    func testDeleteAccountSignsUserOut() async throws {
        seedAuthState()
        let context = try makeInMemoryContext()
        let manager = AuthManager.shared

        try await manager.deleteAccount(context: context)

        XCTAssertFalse(manager.isSignedIn, "isSignedIn must be false after deleteAccount")
        XCTAssertNil(manager.userName, "userName must be nil after deleteAccount")
        XCTAssertNil(manager.userEmail, "userEmail must be nil after deleteAccount")
    }

    // MARK: - SwiftData Purge

    func testDeleteAccountPurgesAllPersistedMatchRecords() async throws {
        seedAuthState()
        let context = try makeInMemoryContext()

        // Insert 3 test records
        for _ in 0..<3 {
            context.insert(PersistedMatch())
        }
        try context.save()

        let before = try context.fetch(FetchDescriptor<PersistedMatch>())
        XCTAssertEqual(before.count, 3, "Expected 3 records before deletion")

        let manager = AuthManager.shared
        try await manager.deleteAccount(context: context)

        let after = try context.fetch(FetchDescriptor<PersistedMatch>())
        XCTAssertEqual(after.count, 0,
                       "All PersistedMatch records must be deleted from SwiftData")
    }

    // MARK: - Guard: no-op when not signed in

    func testDeleteAccountIsNoOpWhenNotSignedIn() async throws {
        // Ensure no user identifier is set
        UserDefaults.standard.removeObject(forKey: "appleUserIdentifier")
        let context = try makeInMemoryContext()
        let manager = AuthManager.shared
        manager.accountDeleted = false

        try await manager.deleteAccount(context: context)

        XCTAssertFalse(manager.accountDeleted,
                       "accountDeleted must remain false when no user is signed in")
    }

    // MARK: - Error State

    func testDeletionErrorIsNilOnSuccess() async throws {
        seedAuthState()
        let context = try makeInMemoryContext()
        let manager = AuthManager.shared
        manager.deletionError = nil

        try await manager.deleteAccount(context: context)

        XCTAssertNil(manager.deletionError,
                     "deletionError must be nil after successful deleteAccount")
    }
}
