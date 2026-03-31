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
        var data: [GameScoreData] = []
        for avg in averages {
            data.append(GameScoreData(game: "Game \(avg.game)", type: "Scored", value: avg.avgScored))
            data.append(GameScoreData(game: "Game \(avg.game)", type: "Conceded", value: avg.avgConceded))
        }
        return data
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
                    "Scored": Color.green,
                    "Conceded": Color.red
                ])
                .frame(height: 180)
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
