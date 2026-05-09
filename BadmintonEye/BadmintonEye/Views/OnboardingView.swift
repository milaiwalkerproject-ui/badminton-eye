import SwiftUI

/// 3-screen onboarding walkthrough shown on first app launch.
struct OnboardingView: View {

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "sportscourt.fill",
            iconColor: .blue,
            title: "Track Every Point",
            description: "Score matches in real time with one tap. Live scoring keeps both sides, serves, and game history perfectly in sync — even on your Apple Watch."
        ),
        OnboardingPage(
            icon: "chart.bar.xaxis",
            iconColor: .indigo,
            title: "Analyse Your Game",
            description: "Browse shot statistics, rally lengths, and full match history. Spot trends in your win rate and see exactly where points are won and lost."
        ),
        OnboardingPage(
            icon: "trophy.fill",
            iconColor: .orange,
            title: "Level Up",
            description: "Unlock AI-powered Hawk Eye line calling, trajectory replay, and confidence analysis. Train smarter and compete with precision."
        ),
    ]

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
                    Button("Skip") {
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
                Text("Next")
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
                Text("Get Started")
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
