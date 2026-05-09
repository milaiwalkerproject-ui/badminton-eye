import SwiftUI
import StoreKit

/// Modal paywall sheet presenting subscription options with dynamic App Store pricing.
struct PaywallView: View {

    @Environment(\.dismiss) private var dismiss
    private var subscriptionManager = SubscriptionManager.shared

    @State private var selectedProduct: Product?
    @State private var isPurchasing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    ratingChip
                    featurePreviewSection
                    productOptionsSection
                    subscribeButton
                    cancelAnytimeNote
                    restoreButton
                    termsFooter
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.title2)
                    }
                }
            }
            .task {
                // Default to yearly (better value) once products load
                if selectedProduct == nil, let yearly = subscriptionManager.availableProducts.last {
                    selectedProduct = yearly
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "eye.trianglebadge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            Text("Join 10,000+ Players\nImproving Their Game")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Text("AI-powered hawk-eye calls. No more disputes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Rating Chip

    private var ratingChip: some View {
        HStack(spacing: 6) {
            Text("★★★★★")
                .foregroundStyle(.orange)
                .font(.subheadline)
            Text("4.8")
                .fontWeight(.semibold)
                .font(.subheadline)
            Text("·")
                .foregroundStyle(.secondary)
            Text("2K Ratings")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .clipShape(Capsule())
    }

    // MARK: - Feature Preview

    private var featurePreviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            featureRow(title: "Instant hawk-eye line calls — no more disputes")
            featureRow(title: "Shot-by-shot analytics after every match")
            featureRow(title: "Multi-angle replay analysis")
            featureRow(title: "Export & share your best moments")
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func featureRow(title: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("✓")
                .font(.body)
                .fontWeight(.bold)
                .foregroundStyle(.blue)
                .frame(width: 20)
            Text(title)
                .font(.body)
        }
    }

    // MARK: - Product Options

    private var productOptionsSection: some View {
        VStack(spacing: 12) {
            ForEach(subscriptionManager.availableProducts, id: \.id) { product in
                productCard(product)
            }
        }
    }

    private func productCard(_ product: Product) -> some View {
        let isSelected = selectedProduct?.id == product.id
        let isYearly = product.id == "hawkeye_yearly"

        return Button {
            selectedProduct = product
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(product.displayName)
                            .font(.headline)
                        if isYearly {
                            Text("Best Value — Save 50%")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.blue)
                                .clipShape(Capsule())
                        }
                    }

                    if isYearly {
                        Text("\(product.displayPrice)/year")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Less than a shuttlecock per week")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    } else {
                        Text("\(product.displayPrice)/month")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color(.systemGray4), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subscribe Button

    private var subscribeButton: some View {
        Button {
            guard let product = selectedProduct else { return }
            isPurchasing = true
            Task {
                let transaction = try? await subscriptionManager.purchase(product)
                isPurchasing = false
                if transaction != nil {
                    dismiss()
                }
            }
        } label: {
            Group {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(ctaLabel)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.blue)
        .disabled(selectedProduct == nil || isPurchasing)
    }

    private var ctaLabel: String {
        guard let product = selectedProduct else {
            return "Unlock Hawk Eye"
        }
        let isYearly = product.id == "hawkeye_yearly"
        return isYearly
            ? "Unlock Hawk Eye — \(product.displayPrice)/yr"
            : "Start Free Trial"
    }

    // MARK: - Cancel Anytime

    private var cancelAnytimeNote: some View {
        Text("Cancel anytime. No questions asked.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Restore

    private var restoreButton: some View {
        Button {
            Task {
                await subscriptionManager.restorePurchases()
                if subscriptionManager.isPremium {
                    dismiss()
                }
            }
        } label: {
            Text("Restore Purchases")
                .font(.subheadline)
                .foregroundStyle(.blue)
        }
    }

    // MARK: - Terms

    private var termsFooter: some View {
        VStack(spacing: 8) {
            Text("Payment will be charged to your Apple ID account. Subscription automatically renews unless cancelled at least 24 hours before the end of the current period.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Link("Terms of Service",
                     destination: URL(string: "https://badmintoneye.app/terms")!)
                Text("\u{00B7}")
                    .foregroundStyle(.secondary)
                Link("Privacy Policy",
                     destination: URL(string: "https://badmintoneye.app/privacy")!)
            }
            .font(.caption2)
        }
        .padding(.horizontal)
    }
}
