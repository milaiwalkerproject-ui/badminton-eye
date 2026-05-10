import SwiftUI

/// Full-screen confirmation shown after successful account deletion.
/// Gives the user a clear signal that all data has been removed before
/// routing them back to the onboarding / sign-in flow.
struct AccountDeletedView: View {

    private var localization = LocalizationManager.shared
    /// Called when the user taps "Get Started" to reset app state.
    var onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text(localization.localized("account.deleted.title"))
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text(localization.localized("account.deleted.message"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Text(localization.localized("account.deleted.appleNote"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            Button {
                onGetStarted()
            } label: {
                Text(localization.localized("account.deleted.getStarted"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea()
    }
}
