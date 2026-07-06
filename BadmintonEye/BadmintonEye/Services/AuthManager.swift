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

    // MARK: - Private

    private var userIdentifier: String?
    private let userIdentifierKey = "appleUserIdentifier"
    private let userNameKey = "appleUserName"
    private let userEmailKey = "appleUserEmail"

    private override init() {
        super.init()
        if !AppMode.freeAppleIDMode {
            checkAuthState()
        }
    }

    // MARK: - Sign In

    /// Presents the system Sign in with Apple sheet.
    /// Call from a SwiftUI `SignInWithAppleButton` onRequest/onCompletion flow.
    func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        // Sign in with Apple requires the `applesignin` entitlement, which is
        // unavailable on a free Apple ID. Free-mode users stay anonymous.
        if AppMode.freeAppleIDMode { return }
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

    // MARK: - Auth State Check

    /// Verifies the saved Apple ID credential is still valid.
    /// Called on init and on app foreground.
    func checkAuthState() {
        if AppMode.freeAppleIDMode {
            isSignedIn = false
            return
        }
        guard let uid = UserDefaults.standard.string(forKey: userIdentifierKey) else {
            isSignedIn = false
            return
        }

        userIdentifier = uid
        userName = UserDefaults.standard.string(forKey: userNameKey)
        userEmail = UserDefaults.standard.string(forKey: userEmailKey)

        let provider = ASAuthorizationAppleIDProvider()
        provider.getCredentialState(forUserID: uid) { state, _ in
            // No self capture: sending a weakly-captured reference into a
            // main-actor task trips Swift 6.1's region analysis (Xcode 16.4).
            // AuthManager is a singleton, so resolve it inside the task.
            Task { @MainActor in
                let auth = AuthManager.shared
                switch state {
                case .authorized:
                    auth.isSignedIn = true
                case .revoked, .notFound:
                    auth.signOut()
                default:
                    // transferred or unknown -- treat as signed out
                    auth.signOut()
                }
            }
        }
    }
}
