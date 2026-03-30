import SwiftUI
import SwiftData

struct StatsView: View {
    @Query private var allMatches: [PersistedMatch]
    @State private var viewModel = MatchStatsViewModel()

    var body: some View {
        Group {
            if viewModel.hasEnoughData {
                statsContent
            } else {
                emptyState
            }
        }
        .navigationTitle("Stats")
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
                trendPlaceholder
                scoringPlaceholder
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
                    Text("Wins")
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
                    Text("Losses")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(String(format: "%.0f%% win rate", viewModel.winRate))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if viewModel.currentWinStreak > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(viewModel.currentWinStreak) match streak")
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

    // MARK: - Placeholder Sections

    private var trendPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performance Trend")
                .font(.headline)
            Text("Coming soon")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
        )
    }

    private var scoringPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scoring Patterns")
                .font(.headline)
            Text("Coming soon")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Not Enough Data", systemImage: "chart.bar")
        } description: {
            Text("Play more matches to unlock analytics")
        } actions: {
            Text("\(viewModel.completedMatches.count) of 3 matches completed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
