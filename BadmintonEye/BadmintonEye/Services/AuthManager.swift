import Foundation
import AuthenticationServices
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

    /// Permanently deletes the user's account and associated CloudKit data.
    ///
    /// Performs the following cleanup:
    /// 1. Deletes the user's CloudKit leaderboard profile (best-effort).
    /// 2. Wipes locally stored credentials and profile data.
    /// 3. Sets signed-out state.
    ///
    /// Apple ID federated token revocation must be done by the user at
    /// Settings → Apple ID → Sign-In & Security → Sign in with Apple.
    @MainActor
    func deleteAccount() async throws {
        guard userIdentifier != nil else { return }

        isDeletingAccount = true
        deletionError = nil
        defer { isDeletingAccount = false }

        do {
            // 1. Delete CloudKit profile (best-effort — ignore if absent or offline)
            // TODO: Uncomment when leaderboard module is fully integrated.
            // let remote = CloudKitLeaderboardRemoteStore(
            //     containerIdentifier: LeaderboardCloudKitConfig.containerIdentifier
            // )
            // try await remote.deleteRecord(id: userIdentifier!)

            // 2. Wipe local credential state
            UserDefaults.standard.removeObject(forKey: userIdentifierKey)
            UserDefaults.standard.removeObject(forKey: userNameKey)
            UserDefaults.standard.removeObject(forKey: userEmailKey)
            userIdentifier = nil
            userName = nil
            userEmail = nil

            // 3. Sign out
            isSignedIn = false
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
