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
            VStack(spacing: BE.Space.m) {
                summaryCard
                WinRateTrendChart(viewModel: viewModel)
                ScoringPatternsChart(viewModel: viewModel)
            }
            .padding(BE.Space.m)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: - Summary Card

    private var summaryCardAccessibilityLabel: String {
        let wins = localization.localized("stats.wins")
        let losses = localization.localized("stats.losses")
        let winRateStr = String(format: localization.localized("stats.winRateFormat"), viewModel.winRate)
        var parts = ["\(viewModel.totalWins) \(wins), \(viewModel.totalLosses) \(losses). \(winRateStr)."]
        if viewModel.currentWinStreak > 0 {
            parts.append(String(format: localization.localized("stats.streakFormat"), viewModel.currentWinStreak))
        }
        return parts.joined(separator: " ")
    }

    private var summaryCard: some View {
        VStack(spacing: BE.Space.m) {
            HStack(spacing: BE.Space.l) {
                statColumn(value: viewModel.totalWins,
                           label: localization.localized("stats.wins"),
                           tint: BE.TeamA.top)
                Divider().frame(height: 56)
                statColumn(value: viewModel.totalLosses,
                           label: localization.localized("stats.losses"),
                           tint: BE.TeamB.top)
            }

            // Win-rate bar
            VStack(spacing: 6) {
                HStack {
                    Text(String(format: localization.localized("stats.winRateFormat"), viewModel.winRate))
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(round(viewModel.winRate)))%")
                        .font(.system(.footnote, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(BE.TeamA.top)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.tertiarySystemFill))
                        Capsule()
                            .fill(BE.TeamA.gradient)
                            .frame(width: max(6, proxy.size.width * (viewModel.winRate / 100)))
                    }
                }
                .frame(height: 6)
            }

            if viewModel.currentWinStreak > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text(String(format: localization.localized("stats.streakFormat"), viewModel.currentWinStreak))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule(style: .continuous).fill(Color.orange.opacity(0.15)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BE.Space.l)
        .padding(.horizontal, BE.Space.l)
        .background(BE.card(20).fill(Color(.secondarySystemGroupedBackground)))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summaryCardAccessibilityLabel)
    }

    private func statColumn(value: Int, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(BE.eyebrow)
                .tracking(1.0)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
