import SwiftUI
import AuthenticationServices

struct SettingsView: View {

    @Bindable private var authManager = AuthManager.shared
    private var subscriptionManager = SubscriptionManager.shared
    @State private var showPaywall = false
    @AppStorage("hapticFeedbackEnabled") private var hapticEnabled = true
    @State private var localization = LocalizationManager.shared

    var body: some View {
        List {
            if authManager.isSignedIn {
                signedInSection
            } else {
                signInSection
            }

            premiumSection

            languageSection

            hapticSection

            aboutSection
        }
        .navigationTitle(localization.localized("settings.title"))
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Premium

    private var premiumSection: some View {
        Section {
            if subscriptionManager.isPremium {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hawk Eye Premium Active")
                            .font(.headline)
                        Text("All premium features unlocked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                    HStack {
                        Text("Manage Subscription")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                }
            } else {
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "eye.trianglebadge.exclamationmark")
                            .foregroundStyle(.blue)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Upgrade to Premium")
                                .font(.headline)
                            Text("Unlock Hawk Eye AI line calling")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Premium")
        }
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

    // MARK: - Language

    private var languageSection: some View {
        Section {
            Picker(selection: $localization.currentLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    HStack(spacing: 8) {
                        Text(language.flag)
                        Text(language.nativeName)
                        if language != .english {
                            Text("(\(language.englishName))")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    .tag(language)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .foregroundStyle(.blue)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localization.localized("settings.language"))
                            .font(.subheadline)
                        Text("\(localization.currentLanguage.flag) \(localization.currentLanguage.nativeName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(localization.localized("settings.language"))
        }
    }

    // MARK: - Haptic Feedback

    private var hapticSection: some View {
        Section {
            Toggle(isOn: $hapticEnabled) {
                HStack(spacing: 12) {
                    Image(systemName: "hand.tap.fill")
                        .foregroundStyle(.orange)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Haptic Feedback")
                            .font(.subheadline)
                        Text("Vibrate on score changes during live play")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Scoring")
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

            Button {
                Task {
                    await subscriptionManager.restorePurchases()
                }
            } label: {
                Text("Restore Purchases")
            }
        } header: {
            Text("About")
        }
    }
}
