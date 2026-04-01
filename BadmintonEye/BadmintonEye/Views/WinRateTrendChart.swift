import SwiftUI
import Charts

enum TrendRange: String, CaseIterable {
    case last10 = "last10"
    case last20 = "last20"
    case last50 = "last50"

    var matchCount: Int {
        switch self {
        case .last10: return 10
        case .last20: return 20
        case .last50: return 50
        }
    }

    var localizationKey: String {
        switch self {
        case .last10: return "chart.last10"
        case .last20: return "chart.last20"
        case .last50: return "chart.last50"
        }
    }
}

struct WinRateTrendChart: View {
    var viewModel: MatchStatsViewModel

    @State private var selectedRange: TrendRange = .last10
    @State private var localization = LocalizationManager.shared

    private var trendData: [(index: Int, rate: Double)] {
        viewModel.winRateOverLast(selectedRange.matchCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localization.localized("chart.performanceTrend"))
                .font(.headline)

            Picker("Range", selection: $selectedRange) {
                ForEach(TrendRange.allCases, id: \.self) { range in
                    Text(localization.localized(range.localizationKey)).tag(range)
                }
            }
            .pickerStyle(.segmented)

            if trendData.isEmpty {
                Text(localization.localized("chart.notEnoughData"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else {
                Chart {
                    ForEach(trendData, id: \.index) { point in
                        AreaMark(
                            x: .value("Match", point.index + 1),
                            y: .value("Win Rate", point.rate)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue.opacity(0.2), .blue.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Match", point.index + 1),
                            y: .value("Win Rate", point.rate)
                        )
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }

                    if let last = trendData.last {
                        PointMark(
                            x: .value("Match", last.index + 1),
                            y: .value("Win Rate", last.rate)
                        )
                        .foregroundStyle(.blue)
                        .annotation(position: .top) {
                            Text(String(format: "%.0f%%", last.rate))
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text("\(v)%")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxisLabel(localization.localized("chart.matchAxis"))
                .frame(height: 200)
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
