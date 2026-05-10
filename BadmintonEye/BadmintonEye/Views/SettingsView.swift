import SwiftUI
import SwiftData
import AuthenticationServices

struct SettingsView: View {

    @Bindable private var authManager = AuthManager.shared
    private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.modelContext) private var modelContext
    @State private var showPaywall = false
    @State private var showDeleteAccountAlert = false
    @AppStorage("hapticFeedbackEnabled") private var hapticEnabled = true
    @AppStorage("voiceAnnouncementsEnabled") private var voiceAnnouncementsEnabled = false
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

            voiceSection

            aboutSection
        }
        .navigationTitle(localization.localized("settings.title"))
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .fullScreenCover(isPresented: $authManager.accountDeleted) {
            AccountDeletedView {
                authManager.accountDeleted = false
            }
        }
        .alert(
            localization.localized("settings.deleteAccount.alert"),
            isPresented: $showDeleteAccountAlert
        ) {
            Button(localization.localized("settings.deleteAccount.confirm"),
                   role: .destructive) {
                Task {
                    try? await authManager.deleteAccount(context: modelContext)
                }
            }
            Button(localization.localized("common.cancel"), role: .cancel) {}
        } message: {
            Text(localization.localized("settings.deleteAccount.message"))
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
                        Text(localization.localized("premium.active"))
                            .font(.headline)
                        Text(localization.localized("premium.allUnlocked"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                    HStack {
                        Text(localization.localized("premium.manage"))
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
                            Text(localization.localized("premium.upgrade"))
                                .font(.headline)
                            Text(localization.localized("premium.unlockHawkEye"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text(localization.localized("settings.premium"))
        }
    }

    // MARK: - Signed Out

    private var signInSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "icloud")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)

                Text(localization.localized("icloud.signInPrompt"))
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
            Text(localization.localized("icloud.title"))
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
                Text(localization.localized("icloud.syncActive"))
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) {
                authManager.signOut()
            } label: {
                Text(localization.localized("settings.signOut"))
            }

            // Guideline 5.1.1(v) — account deletion must be available in-app
            Button(role: .destructive) {
                showDeleteAccountAlert = true
            } label: {
                HStack {
                    if authManager.isDeletingAccount {
                        ProgressView()
                            .padding(.trailing, 4)
                    }
                    Text(localization.localized("settings.deleteAccount"))
                }
            }
            .disabled(authManager.isDeletingAccount)
        } header: {
            Text(localization.localized("icloud.account"))
        } footer: {
            Text(localization.localized("settings.deleteAccount.footer"))
                .font(.caption2)
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
                        Text(localization.localized("settings.haptic"))
                            .font(.subheadline)
                        Text(localization.localized("settings.haptic.subtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(localization.localized("settings.scoring"))
        }
    }

    // MARK: - Voice Announcements

    private var voiceSection: some View {
        Section {
            Toggle(isOn: $voiceAnnouncementsEnabled) {
                HStack(spacing: 12) {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(.purple)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localization.localized("settings.voiceAnnouncements"))
                            .font(.subheadline)
                        Text(localization.localized("settings.voiceAnnouncements.subtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(localization.localized("settings.audio"))
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Text(localization.localized("settings.version"))
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(localization.localized("settings.build"))
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task {
                    await subscriptionManager.restorePurchases()
                }
            } label: {
                Text(localization.localized("settings.restorePurchases"))
            }
        } header: {
            Text(localization.localized("settings.about"))
        }
    }
}
