import SwiftUI
import Charts

struct GameScoreData: Identifiable {
    let id = UUID()
    let game: String
    let type: String
    let value: Double
}

struct ScoringPatternsChart: View {
    var viewModel: MatchStatsViewModel
    @State private var localization = LocalizationManager.shared

    private var chartData: [GameScoreData] {
        let averages = viewModel.perGameAverages()
        let scoredLabel = localization.localized("chart.scored")
        let concededLabel = localization.localized("chart.conceded")
        var data: [GameScoreData] = []
        for avg in averages {
            let gameLabel = String(format: localization.localized("game.number"), avg.game)
            data.append(GameScoreData(game: gameLabel, type: scoredLabel, value: avg.avgScored))
            data.append(GameScoreData(game: gameLabel, type: concededLabel, value: avg.avgConceded))
        }
        return data
    }

    private var chartAccessibilityLabel: String {
        let averages = viewModel.perGameAverages()
        guard !averages.isEmpty else {
            return localization.localized("chart.scoringPatterns")
        }
        let gameSummaries = averages.map { avg in
            let gameLabel = String(format: localization.localized("game.number"), avg.game)
            return String(format: "%@: %.0f %@, %.0f %@", gameLabel, avg.avgScored, localization.localized("chart.scored"), avg.avgConceded, localization.localized("chart.conceded"))
        }.joined(separator: ". ")
        return "\(localization.localized("chart.scoringPatterns")). \(gameSummaries)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localization.localized("chart.scoringPatterns"))
                .font(.headline)

            if chartData.isEmpty {
                Text(localization.localized("chart.notEnoughData"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(chartData) { item in
                    BarMark(
                        x: .value("Game", item.game),
                        y: .value("Points", item.value)
                    )
                    .foregroundStyle(by: .value("Type", item.type))
                    .position(by: .value("Type", item.type))
                }
                .chartForegroundStyleScale([
                    localization.localized("chart.scored"): Color.green,
                    localization.localized("chart.conceded"): Color.red
                ])
                .frame(height: 180)
                .accessibilityLabel(chartAccessibilityLabel)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        )
    }
}
