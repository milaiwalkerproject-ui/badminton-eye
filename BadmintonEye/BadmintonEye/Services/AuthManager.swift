import Foundation
import AuthenticationServices

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

    /// Permanently deletes the user's account credentials and signs out.
    ///
    /// Callers must delete SwiftData records via `ModelContext` **before** invoking
    /// this method (CloudKit sync then removes the corresponding remote copies
    /// automatically via `NSPersistentCloudKitContainer`).
    ///
    /// Performs:
    /// 1. Wipes **all** app `UserDefaults` (auth credentials + stored preferences).
    /// 2. Clears in-memory auth state.
    /// 3. Sets `isSignedIn = false`.
    ///
    /// Note: Apple ID federated credential revocation is user-initiated via
    /// Settings → Apple ID → Password & Security → Sign in with Apple.
    @MainActor
    func deleteAccount() async {
        guard userIdentifier != nil else { return }

        isDeletingAccount = true
        defer { isDeletingAccount = false }

        // 1. Wipe all app UserDefaults (auth credentials + app preferences)
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
            UserDefaults.standard.synchronize()
        }

        // 2. Clear in-memory auth state
        userIdentifier = nil
        userName = nil
        userEmail = nil
        deletionError = nil

        // 3. Sign out
        isSignedIn = false
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
