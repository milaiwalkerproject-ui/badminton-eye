import SwiftUI
import AuthenticationServices

struct SettingsView: View {

    @Bindable private var authManager = AuthManager.shared
    private var subscriptionManager = SubscriptionManager.shared
    @State private var showPaywall = false
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
            preferencesSection
            aboutSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(localization.localized("settings.title"))
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: - Premium

    private var premiumSection: some View {
        Section {
            if subscriptionManager.isPremium {
                HStack(spacing: BE.Space.m) {
                    SettingsIconTile(systemName: "checkmark.seal.fill", tint: .green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localization.localized("premium.active"))
                            .font(.system(.body, design: .rounded).weight(.semibold))
                        Text(localization.localized("premium.allUnlocked"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)

                Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                    HStack(spacing: BE.Space.m) {
                        SettingsIconTile(systemName: "creditcard.fill", tint: .indigo)
                        Text(localization.localized("premium.manage"))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button { showPaywall = true } label: {
                    HStack(spacing: BE.Space.m) {
                        SettingsIconTile(systemName: "eye.trianglebadge.exclamationmark", tint: .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localization.localized("premium.upgrade"))
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(localization.localized("premium.unlockHawkEye"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            sectionHeader(localization.localized("settings.premium"))
        }
    }

    // MARK: - Signed Out

    private var signInSection: some View {
        Section {
            VStack(spacing: BE.Space.m) {
                Image(systemName: "icloud")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.blue)
                    .padding(.top, BE.Space.s)

                Text(localization.localized("icloud.signInPrompt"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BE.Space.s)

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    authManager.handleSignInResult(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .clipShape(BE.card(12))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, BE.Space.s)
        } header: {
            sectionHeader(localization.localized("icloud.title"))
        }
    }

    // MARK: - Signed In

    private var signedInSection: some View {
        Section {
            HStack(spacing: BE.Space.m) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.blue.gradient)

                VStack(alignment: .leading, spacing: 2) {
                    Text(authManager.userName ?? "Apple User")
                        .font(.system(.headline, design: .rounded))
                    if let email = authManager.userEmail {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)

            HStack(spacing: BE.Space.m) {
                SettingsIconTile(systemName: "checkmark.icloud.fill", tint: .green)
                Text(localization.localized("icloud.syncActive"))
            }

            Button(role: .destructive) {
                authManager.signOut()
            } label: {
                HStack(spacing: BE.Space.m) {
                    SettingsIconTile(systemName: "rectangle.portrait.and.arrow.right", tint: .red)
                    Text(localization.localized("settings.signOut"))
                }
            }
        } header: {
            sectionHeader(localization.localized("icloud.account"))
        }
    }

    // MARK: - Preferences (language / haptic / voice unified)

    private var preferencesSection: some View {
        Section {
            // Language
            Picker(selection: $localization.currentLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    HStack(spacing: 8) {
                        Text(language.flag)
                        Text(language.nativeName)
                    }
                    .tag(language)
                }
            } label: {
                HStack(spacing: BE.Space.m) {
                    SettingsIconTile(systemName: "globe", tint: .blue)
                    Text(localization.localized("settings.language"))
                }
            }

            // Haptics
            Toggle(isOn: $hapticEnabled) {
                HStack(spacing: BE.Space.m) {
                    SettingsIconTile(systemName: "hand.tap.fill", tint: .orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(localization.localized("settings.haptic"))
                        Text(localization.localized("settings.haptic.subtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Voice
            Toggle(isOn: $voiceAnnouncementsEnabled) {
                HStack(spacing: BE.Space.m) {
                    SettingsIconTile(systemName: "speaker.wave.2.fill", tint: .purple)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(localization.localized("settings.voiceAnnouncements"))
                        Text(localization.localized("settings.voiceAnnouncements.subtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            sectionHeader("Preferences")
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack(spacing: BE.Space.m) {
                SettingsIconTile(systemName: "info.circle.fill", tint: Color(.systemGray))
                Text(localization.localized("settings.version"))
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: BE.Space.m) {
                SettingsIconTile(systemName: "hammer.fill", tint: Color(.systemGray2))
                Text(localization.localized("settings.build"))
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button {
                Task { await subscriptionManager.restorePurchases() }
            } label: {
                HStack(spacing: BE.Space.m) {
                    SettingsIconTile(systemName: "arrow.clockwise", tint: .teal)
                    Text(localization.localized("settings.restorePurchases"))
                        .foregroundStyle(.primary)
                }
            }
        } header: {
            sectionHeader(localization.localized("settings.about"))
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(.footnote, design: .rounded).weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}
