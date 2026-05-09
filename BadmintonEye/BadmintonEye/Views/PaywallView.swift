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
                    featurePreviewSection
                    productOptionsSection
                    subscribeButton
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

            Text("Unlock Hawk Eye")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("AI-powered line calling for your matches")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    // MARK: - Feature Preview

    private var featurePreviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            featureRow(icon: "eye.circle", title: "AI-powered line calling")
            featureRow(icon: "sportscourt", title: "Visual trajectory replay")
            featureRow(icon: "chart.bar", title: "Confidence analysis")
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func featureRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)
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
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(product.displayName)
                            .font(.headline)
                        if isYearly {
                            Text("Save 50%")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.green)
                                .clipShape(Capsule())
                        }
                    }

                    if isYearly {
                        Text("\(product.displayPrice)/year")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                    Text("Subscribe")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(selectedProduct == nil || isPurchasing)
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
