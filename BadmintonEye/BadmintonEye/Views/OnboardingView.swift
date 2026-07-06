import SwiftUI
import SwiftData
import AuthenticationServices

// MARK: - Onboarding step model (pure — unit-tested in OnboardingFlowTests)

/// Ordered steps of the first-run onboarding flow. A pure value type so the
/// sequencing logic is testable without a running UI.
///
/// Order: welcome → sign in → auto-scoring intro → first court calibration →
/// Hawk Eye challenge intro → ready.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case signIn
    case autoScoring
    case calibration
    case challenge
    case ready

    var id: Int { rawValue }

    /// The next step, or `nil` when already at the end.
    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    /// The previous step, or `nil` when already at the start.
    var previous: OnboardingStep? { rawValue == 0 ? nil : OnboardingStep(rawValue: rawValue - 1) }

    var isFirst: Bool { rawValue == 0 }
    var isLast: Bool { next == nil }
}

// MARK: - Persisted completion flag

/// Single source of truth for the "has the user finished first-run onboarding"
/// flag. Stored under a versioned key so a future onboarding revamp can
/// re-trigger the flow by bumping the version.
enum OnboardingStore {
    /// UserDefaults / `@AppStorage` key. Bump the suffix to re-show onboarding.
    static let completedKey = "hasCompletedOnboarding_v1"

    static var hasCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: completedKey) }
        set { UserDefaults.standard.set(newValue, forKey: completedKey) }
    }
}

// MARK: - Onboarding View

/// First-run onboarding: walks a new user through sign-in, the automatic
/// scoring system, a first court calibration, and the Hawk Eye challenge
/// system (which they can use or subscribe to). Calls `onFinish` when the
/// user completes or skips the flow.
struct OnboardingView: View {

    /// Invoked when the user finishes (or skips) onboarding. The caller is
    /// responsible for flipping the persisted completion flag.
    var onFinish: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var localization = LocalizationManager.shared
    @State private var auth = AuthManager.shared
    @State private var subscriptions = SubscriptionManager.shared

    @State private var step: OnboardingStep = .welcome
    @State private var showCalibration = false
    @State private var showPaywall = false
    @State private var savedVenueName: String?

    private func t(_ key: String) -> String { localization.localized(key) }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            TabView(selection: $step) {
                ForEach(OnboardingStep.allCases) { stepCase in
                    page(for: stepCase)
                        .tag(stepCase)
                        .padding(.horizontal, BE.Space.l)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(BE.ease, value: step)

            bottomBar
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .fullScreenCover(isPresented: $showCalibration) {
            CourtCalibrationView { profile in
                modelContext.insert(profile)
                try? modelContext.save()
                savedVenueName = profile.venueName
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            Spacer()
            Button(t("onboarding.skip")) { onFinish() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                // Keep the row height stable so the page doesn't jump when the
                // Skip control disappears on the final step.
                .opacity(step.isLast ? 0 : 1)
                .disabled(step.isLast)
        }
        .padding(.horizontal, BE.Space.l)
        .padding(.top, BE.Space.s)
        .frame(height: 30)
    }

    private var bottomBar: some View {
        VStack(spacing: BE.Space.m) {
            progressDots

            Button(action: advance) {
                Text(step.isLast ? t("onboarding.ready.start") : t("onboarding.continue"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor, in: BE.card(14))
                    .foregroundStyle(.white)
            }

            Button(t("onboarding.back")) {
                if let previous = step.previous {
                    withAnimation(BE.ease) { step = previous }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .opacity(step.isFirst ? 0 : 1)
            .disabled(step.isFirst)
        }
        .padding(.horizontal, BE.Space.l)
        .padding(.bottom, BE.Space.l)
        .padding(.top, BE.Space.s)
    }

    private var progressDots: some View {
        HStack(spacing: BE.Space.s) {
            ForEach(OnboardingStep.allCases) { stepCase in
                Capsule()
                    .fill(stepCase == step ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: stepCase == step ? 22 : 7, height: 7)
            }
        }
        .animation(BE.ease, value: step)
        .accessibilityHidden(true)
    }

    private func advance() {
        if step.isLast {
            onFinish()
        } else if let next = step.next {
            withAnimation(BE.ease) { step = next }
        }
    }

    // MARK: - Pages

    @ViewBuilder
    private func page(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome:     welcomePage
        case .signIn:      signInPage
        case .autoScoring: autoScoringPage
        case .calibration: calibrationPage
        case .challenge:   challengePage
        case .ready:       readyPage
        }
    }

    private var welcomePage: some View {
        pageScaffold(
            icon: "sportscourt.fill",
            iconTint: BE.TeamA.top,
            title: t("onboarding.welcome.title"),
            subtitle: t("onboarding.welcome.subtitle")
        ) { EmptyView() }
    }

    private var signInPage: some View {
        pageScaffold(
            icon: "person.crop.circle.badge.checkmark",
            iconTint: BE.TeamA.top,
            title: AppMode.freeAppleIDMode ? t("onboarding.signIn.freeTitle") : t("onboarding.signIn.title"),
            subtitle: AppMode.freeAppleIDMode ? t("onboarding.signIn.freeSubtitle") : t("onboarding.signIn.subtitle")
        ) {
            if !AppMode.freeAppleIDMode {
                VStack(spacing: BE.Space.m) {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        auth.handleSignInResult(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(BE.card(12))

                    Button(t("onboarding.signIn.continueWithout")) { advance() }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                infoCard(icon: "lock.shield", text: t("onboarding.signIn.freeSubtitle"))
            }
        }
    }

    private var autoScoringPage: some View {
        pageScaffold(
            icon: "wand.and.stars",
            iconTint: BE.serveAccent,
            title: t("onboarding.autoScore.title"),
            subtitle: t("onboarding.autoScore.subtitle")
        ) {
            featureCard {
                bullet("bolt.fill", t("onboarding.autoScore.point1"))
                bullet("hand.tap.fill", t("onboarding.autoScore.point2"))
                bullet("pencil.and.list.clipboard", t("onboarding.autoScore.point3"))
            }
        }
    }

    private var calibrationPage: some View {
        pageScaffold(
            icon: "viewfinder",
            iconTint: BE.TeamA.top,
            title: t("onboarding.calibration.title"),
            subtitle: t("onboarding.calibration.subtitle")
        ) {
            featureCard {
                bullet("iphone.gen3", t("onboarding.calibration.point1"))
                bullet("square.grid.3x3.topleft.filled", t("onboarding.calibration.point2"))
                bullet("tag.fill", t("onboarding.calibration.point3"))
            }

            if let venue = savedVenueName, !venue.isEmpty {
                Label(
                    String(format: t("onboarding.calibration.savedFormat"), venue),
                    systemImage: "checkmark.seal.fill"
                )
                .font(.callout.weight(.medium))
                .foregroundStyle(.green)
            } else {
                Button {
                    showCalibration = true
                } label: {
                    Label(t("onboarding.calibration.calibrateNow"), systemImage: "camera.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(BE.TeamA.gradient, in: BE.card(14))
                        .foregroundStyle(.white)
                }
            }

            Text(t("onboarding.calibration.later"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var challengePage: some View {
        pageScaffold(
            icon: "eye.trianglebadge.exclamationmark",
            iconTint: BE.TeamB.top,
            title: t("onboarding.challenge.title"),
            subtitle: t("onboarding.challenge.subtitle")
        ) {
            featureCard {
                bullet("eye.circle.fill", t("onboarding.challenge.point1"))
                bullet("play.circle.fill", t("onboarding.challenge.point2"))
            }

            if subscriptions.isPremium {
                infoCard(
                    icon: "checkmark.seal.fill",
                    title: t("onboarding.challenge.includedTitle"),
                    text: t("onboarding.challenge.includedSubtitle"),
                    tint: .green
                )
            } else {
                Button {
                    showPaywall = true
                } label: {
                    Label(t("onboarding.challenge.subscribe"), systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(BE.TeamB.gradient, in: BE.card(14))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private var readyPage: some View {
        pageScaffold(
            icon: "checkmark.seal.fill",
            iconTint: .green,
            title: t("onboarding.ready.title"),
            subtitle: t("onboarding.ready.subtitle")
        ) { EmptyView() }
    }

    // MARK: - Building blocks

    private func pageScaffold<Content: View>(
        icon: String,
        iconTint: Color,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(spacing: BE.Space.l) {
                Spacer(minLength: BE.Space.xl)

                ZStack {
                    Circle()
                        .fill(iconTint.opacity(0.14))
                        .frame(width: 132, height: 132)
                    Image(systemName: icon)
                        .font(.system(size: 60, weight: .regular))
                        .foregroundStyle(iconTint)
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityHidden(true)

                VStack(spacing: BE.Space.s) {
                    Text(title)
                        .font(BE.displayTitle)
                        .multilineTextAlignment(.center)
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                content()

                Spacer(minLength: BE.Space.l)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func featureCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: BE.Space.m) {
            content()
        }
        .padding(BE.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: BE.card(16))
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: BE.Space.m) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30, alignment: .center)
            Text(text)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func infoCard(icon: String, title: String? = nil, text: String, tint: Color = .accentColor) -> some View {
        HStack(alignment: .top, spacing: BE.Space.m) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title).font(.callout.weight(.semibold))
                }
                Text(text)
                    .font(.callout)
                    .foregroundStyle(title == nil ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(BE.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: BE.card(16))
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
