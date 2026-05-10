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

    /// Permanently deletes the user's account and all locally stored data.
    ///
    /// Performs the following cleanup in order:
    /// 1. Deletes all `PersistedMatch` records from SwiftData.
    /// 2. Wipes the entire app UserDefaults domain (all keys, not just auth keys).
    /// 3. Clears in-memory credential state and signs out.
    ///
    /// - Parameter context: The SwiftData `ModelContext` to use for the batch delete.
    ///
    /// - Note on Apple ID token revocation: This app has no server component, so the
    ///   Apple REST token-revocation endpoint (`https://appleid.apple.com/auth/revoke`)
    ///   cannot be called from the client. The user must revoke the app's Apple ID access
    ///   manually via Settings → [Your Name] → Sign-In & Security → Sign in with Apple.
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

            // 2. Wipe entire app UserDefaults domain — removes ALL app keys,
            //    not just the 3 auth keys, ensuring complete data removal.
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
            }
            UserDefaults.standard.synchronize()

            // 3. Clear in-memory state and sign out
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
