import SwiftUI

/// 3-screen onboarding walkthrough shown on first app launch.
struct OnboardingView: View {

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0
    @State private var localization = LocalizationManager.shared

    private var pages: [OnboardingPage] {
        [
            OnboardingPage(
                icon: "sportscourt.fill",
                iconColor: .blue,
                title: localization.localized("onboarding.page1.title"),
                description: localization.localized("onboarding.page1.description")
            ),
            OnboardingPage(
                icon: "chart.bar.xaxis",
                iconColor: .indigo,
                title: localization.localized("onboarding.page2.title"),
                description: localization.localized("onboarding.page2.description")
            ),
            OnboardingPage(
                icon: "trophy.fill",
                iconColor: .orange,
                title: localization.localized("onboarding.page3.title"),
                description: localization.localized("onboarding.page3.description")
            ),
        ]
    }

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            // Skip button — visible on pages 0 and 1
            if currentPage < pages.count - 1 {
                HStack {
                    Spacer()
                    Button(localization.localized("common.skip")) {
                        hasCompletedOnboarding = true
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 20)
                    .padding(.top, 56)
                }
            }
        }
    }

    // MARK: - Page layout

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(page.iconColor.opacity(0.12))
                    .frame(width: 120, height: 120)
                Image(systemName: page.icon)
                    .font(.system(size: 52))
                    .foregroundStyle(page.iconColor)
            }
            .padding(.bottom, 40)

            // Text
            VStack(spacing: 16) {
                Text(page.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(page.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            // Page dots
            pageIndicator
                .padding(.bottom, 24)

            // Bottom action button
            bottomButton
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
        }
    }

    // MARK: - Page indicator dots

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: index == currentPage ? 20 : 8, height: 8)
                    .animation(.spring(response: 0.3), value: currentPage)
            }
        }
    }

    // MARK: - Bottom button

    @ViewBuilder
    private var bottomButton: some View {
        if currentPage < pages.count - 1 {
            Button {
                withAnimation {
                    currentPage += 1
                }
            } label: {
                Text(localization.localized("common.continue"))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        } else {
            Button {
                hasCompletedOnboarding = true
            } label: {
                Text(localization.localized("onboarding.getStarted"))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

// MARK: - Data model

private struct OnboardingPage {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
}

#Preview {
    OnboardingView()
}
