import SwiftUI
import AuthenticationServices

struct SettingsView: View {

    @Bindable private var authManager = AuthManager.shared

    var body: some View {
        List {
            if authManager.isSignedIn {
                signedInSection
            } else {
                signInSection
            }

            aboutSection
        }
        .navigationTitle("Settings")
    }

    // MARK: - Signed Out

    private var signInSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "icloud")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)

                Text("Sign in to sync matches and players across your devices.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    authManager.handleSignInResult(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
            }
            .padding(.vertical, 8)
        } header: {
            Text("iCloud Sync")
        }
    }

    // MARK: - Signed In

    private var signedInSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(authManager.userName ?? "Apple User")
                        .font(.headline)
                    if let email = authManager.userEmail {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)

            HStack {
                Image(systemName: "checkmark.icloud.fill")
                    .foregroundStyle(.green)
                Text("iCloud Sync Active")
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                authManager.signOut()
            } label: {
                Text("Sign Out")
            }
        } header: {
            Text("Account")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Build")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("About")
        }
    }
}
