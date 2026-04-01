import SwiftUI
import SwiftData

struct StatsView: View {
    @Query private var allMatches: [PersistedMatch]
    @State private var viewModel = MatchStatsViewModel()
    @State private var localization = LocalizationManager.shared

    var body: some View {
        Group {
            if viewModel.hasEnoughData {
                statsContent
            } else {
                emptyState
            }
        }
        .navigationTitle(localization.localized("stats.title"))
        .onAppear {
            viewModel.update(matches: allMatches)
        }
        .onChange(of: allMatches.count) {
            viewModel.update(matches: allMatches)
        }
    }

    // MARK: - Stats Content

    private var statsContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                summaryCard
                WinRateTrendChart(viewModel: viewModel)
                ScoringPatternsChart(viewModel: viewModel)
            }
            .padding()
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 24) {
                VStack {
                    Text("\(viewModel.totalWins)")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.green)
                    Text(localization.localized("stats.wins"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("-")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)

                VStack {
                    Text("\(viewModel.totalLosses)")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.red)
                    Text(localization.localized("stats.losses"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(String(format: localization.localized("stats.winRateFormat"), viewModel.winRate))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if viewModel.currentWinStreak > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text(String(format: localization.localized("stats.streakFormat"), viewModel.currentWinStreak))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Color.orange.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8)
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(localization.localized("chart.notEnoughData"), systemImage: "chart.bar")
        } description: {
            Text(localization.localized("stats.playMore"))
        } actions: {
            Text(String(format: localization.localized("stats.matchesOf"), viewModel.completedMatches.count))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
