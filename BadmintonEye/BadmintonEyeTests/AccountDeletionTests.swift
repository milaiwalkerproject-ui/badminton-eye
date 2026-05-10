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
//   - Keychain wipe: items stored under app service are removed
//   - CloudKit deletion: deleteAccount completes even when CKContainer is offline

import XCTest
import SwiftData
import Security
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

    // MARK: - Keychain Wipe

    /// Seeds a GenericPassword Keychain item under the app's service, then
    /// verifies it is gone after deleteAccount runs.
    func testDeleteAccountWipesKeychainItems() async throws {
        let service = "com.badmintoneye.app"

        // Seed a Keychain item
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "testKeychainItem",
            kSecValueData: "fake-token".data(using: .utf8)!
        ]
        // Remove any previous entry from a prior test run
        SecItemDelete(addQuery as CFDictionary)
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        XCTAssertEqual(addStatus, errSecSuccess, "Keychain seed should succeed")

        // Verify item is present before deletion
        let checkQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let statusBefore = SecItemCopyMatching(checkQuery as CFDictionary, &result)
        XCTAssertEqual(statusBefore, errSecSuccess, "Item must exist before deleteAccount")

        // Run account deletion
        seedAuthState()
        let context = try makeInMemoryContext()
        try await AuthManager.shared.deleteAccount(context: context)

        // Verify item has been wiped
        let statusAfter = SecItemCopyMatching(checkQuery as CFDictionary, &result)
        XCTAssertEqual(statusAfter, errSecItemNotFound,
                       "Keychain item must be deleted by deleteAccount (wipeKeychain)")
    }

    // MARK: - CloudKit Offline Resilience

    /// Verifies that deleteAccount completes successfully even when CloudKit
    /// is unavailable (offline / no iCloud account) — CKError must not propagate.
    func testDeleteAccountSucceedsWhenCloudKitUnavailable() async throws {
        // Simulate no iCloud sign-in: deleteCloudKitData should not throw.
        // The CloudKit zone delete is best-effort; if CKError.notAuthenticated
        // or CKError.zoneNotFound occurs, deleteAccount still completes.
        seedAuthState()
        let context = try makeInMemoryContext()
        let manager = AuthManager.shared
        manager.accountDeleted = false

        // Should not throw even on a simulator without iCloud configured
        await XCTAssertNoThrowAsync(try await manager.deleteAccount(context: context))

        XCTAssertTrue(manager.accountDeleted,
                      "accountDeleted must be true even if CloudKit was unavailable")
        XCTAssertFalse(manager.isSignedIn,
                       "User must be signed out even if CloudKit was unavailable")
    }
}

// MARK: - XCTest Async Helpers

extension XCTestCase {
    func XCTAssertNoThrowAsync(
        _ expression: @autoclosure () async throws -> some Any,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
        } catch {
            XCTFail("Unexpected throw: \(error). \(message())", file: file, line: line)
        }
    }
}
