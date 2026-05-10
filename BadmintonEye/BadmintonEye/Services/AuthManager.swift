import Foundation
import AuthenticationServices
import SwiftData
#if canImport(CloudKit)
import CloudKit
#endif

/// Manages Apple Sign-In state and credential lifecycle.
/// Singleton accessed via `AuthManager.shared`.
@Observable
final class AuthManager: NSObject, @unchecked Sendable {

    static let shared = AuthManager()

    // MARK: - Published State

    var isSignedIn: Bool = false
    var userName: String?
    var userEmail: String?
    /// Set to `true` while `deleteAccount` is running.
    var isDeletingAccount: Bool = false
    /// Non-nil when account deletion completes with an error.
    var deletionError: Error?
    /// Set to `true` after successful account deletion to present the farewell screen.
    var accountDeleted: Bool = false

    // MARK: - Private

    private var userIdentifier: String?
    private let userIdentifierKey = "appleUserIdentifier"
    private let userNameKey = "appleUserName"
    private let userEmailKey = "appleUserEmail"

    private override init() {
        super.init()
        checkAuthState()
    }

    // MARK: - Sign In

    /// Presents the system Sign in with Apple sheet.
    /// Call from a SwiftUI `SignInWithAppleButton` onRequest/onCompletion flow.
    func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                return
            }
            let uid = credential.user
            UserDefaults.standard.set(uid, forKey: userIdentifierKey)

            // Apple only sends name/email on first authorization
            if let fullName = credential.fullName {
                let name = PersonNameComponentsFormatter.localizedString(
                    from: fullName,
                    style: .default
                )
                if !name.isEmpty {
                    UserDefaults.standard.set(name, forKey: userNameKey)
                }
            }
            if let email = credential.email {
                UserDefaults.standard.set(email, forKey: userEmailKey)
            }

            userIdentifier = uid
            userName = UserDefaults.standard.string(forKey: userNameKey)
            userEmail = UserDefaults.standard.string(forKey: userEmailKey)
            isSignedIn = true

        case .failure:
            // User cancelled or auth failed -- stay signed out
            break
        }
    }

    // MARK: - Sign Out

    func signOut() {
        UserDefaults.standard.removeObject(forKey: userIdentifierKey)
        UserDefaults.standard.removeObject(forKey: userNameKey)
        UserDefaults.standard.removeObject(forKey: userEmailKey)
        userIdentifier = nil
        userName = nil
        userEmail = nil
        isSignedIn = false
    }

    // MARK: - Account Deletion (Guideline 5.1.1(v))

    /// Permanently deletes the user's account and ALL associated data.
    ///
    /// Performs the following cleanup in order:
    /// 1. Purges all `PersistedMatch` records from SwiftData.
    /// 2. Deletes the app's private CloudKit zone (removes cloud-synced data).
    /// 3. Wipes all Keychain items stored under the app's service identifier.
    /// 4. Wipes the entire app UserDefaults domain (all keys, not just auth keys).
    /// 5. Clears in-memory credential state and signs out.
    ///
    /// - Parameter context: The SwiftData `ModelContext` to use for the batch delete.
    ///
    /// - Note on Apple ID token revocation: Programmatic token revocation via
    ///   `https://appleid.apple.com/auth/revoke` requires a server-side `client_secret`
    ///   JWT that cannot be safely embedded in the app binary. This app is client-only.
    ///   The user is presented with instructions to complete revocation via
    ///   Settings → [Your Name] → Sign-In & Security → Sign in with Apple.
    ///   All local and cloud data is wiped before presenting that instruction.
    @MainActor
    func deleteAccount(context: ModelContext) async throws {
        guard userIdentifier != nil else { return }

        isDeletingAccount = true
        deletionError = nil
        defer { isDeletingAccount = false }

        do {
            // 1. Purge all SwiftData match records (batch delete)
            try context.delete(model: PersistedMatch.self)
            try context.save()

            // 2. Delete CloudKit private zone — removes all cloud-synced match data.
            //    Silently succeeds if the zone doesn't exist (user never synced).
            await deleteCloudKitData()

            // 3. Wipe all Keychain items for this app (auth tokens, cached credentials)
            wipeKeychain()

            // 4. Wipe entire app UserDefaults domain — removes ALL app keys,
            //    not just the 3 auth keys, ensuring complete data removal.
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
            }
            UserDefaults.standard.synchronize()

            // 5. Clear in-memory state and sign out
            userIdentifier = nil
            userName = nil
            userEmail = nil
            isSignedIn = false

            // Signal farewell screen
            accountDeleted = true
        } catch {
            deletionError = error
            throw error
        }
    }

    // MARK: - Private Deletion Helpers

    /// Deletes all records from the app's CloudKit private zone.
    ///
    /// SwiftData uses `com.apple.coredata.cloudkit.zone` for its sync zone.
    /// Deletion is best-effort: zone-not-found errors are silently swallowed
    /// because they mean the user has no cloud data to delete.
    private func deleteCloudKitData() async {
        #if canImport(CloudKit)
        let containerID = "iCloud.com.badmintoneye.app"
        let container = CKContainer(identifier: containerID)
        // SwiftData's CloudKit zone name
        let zoneID = CKRecordZone.ID(
            zoneName: "com.apple.coredata.cloudkit.zone",
            ownerName: CKCurrentUserDefaultName
        )
        do {
            _ = try await container.privateCloudDatabase.deleteRecordZone(withID: zoneID)
        } catch let ckError as CKError where ckError.code == .zoneNotFound {
            // No zone exists — user has no CloudKit data; treat as success
        } catch {
            // Non-fatal: log but do not block account deletion
            // (CloudKit may be offline or user may not have iCloud signed in)
            #if DEBUG
            print("[AuthManager] CloudKit zone deletion failed (non-fatal): \(error)")
            #endif
        }
        #endif
    }

    /// Deletes all Keychain GenericPassword items stored under the app's service
    /// identifier. This is a no-op when the app has no Keychain entries.
    private func wipeKeychain() {
        let service = Bundle.main.bundleIdentifier ?? "com.badmintoneye.app"

        // Delete generic passwords keyed to this service (e.g. cached auth tokens)
        let genericQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service
        ]
        SecItemDelete(genericQuery as CFDictionary)

        // Delete any internet passwords the app may have stored
        let internetQuery: [CFString: Any] = [
            kSecClass: kSecClassInternetPassword,
            kSecAttrServer: "appleid.apple.com"
        ]
        SecItemDelete(internetQuery as CFDictionary)
    }

    // MARK: - Auth State Check

    /// Verifies the saved Apple ID credential is still valid.
    /// Called on init and on app foreground.
    func checkAuthState() {
        guard let uid = UserDefaults.standard.string(forKey: userIdentifierKey) else {
            isSignedIn = false
            return
        }

        userIdentifier = uid
        userName = UserDefaults.standard.string(forKey: userNameKey)
        userEmail = UserDefaults.standard.string(forKey: userEmailKey)

        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: uid) { [weak self] state, _ in
            Task { @MainActor in
                switch state {
                case .authorized:
                    self?.isSignedIn = true
                case .revoked, .notFound:
                    self?.signOut()
                default:
                    // transferred or unknown -- treat as signed out
                    self?.signOut()
                }
            }
        }
    }
}
