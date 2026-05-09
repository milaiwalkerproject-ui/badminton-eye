import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct WinRateEntry: TimelineEntry {
    let date: Date
    let data: WinRateSummaryData?

    static var placeholder: WinRateEntry {
        WinRateEntry(date: Date(), data: .placeholder)
    }
}

// MARK: - Timeline provider

struct WinRateProvider: TimelineProvider {
    typealias Entry = WinRateEntry

    func placeholder(in context: Context) -> WinRateEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (WinRateEntry) -> Void) {
        let data = WinRateSummaryData.load()
        completion(WinRateEntry(date: Date(), data: data ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WinRateEntry>) -> Void) {
        let data = WinRateSummaryData.load()
        let entry = WinRateEntry(date: Date(), data: data)

        // Refresh every 15 minutes — new matches don't happen in real-time at widget granularity.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }
}

// MARK: - Win-rate ring view

/// A circular ring that fills proportionally to the win rate.
struct WinRateRing: View {
    let rate: Double  // 0.0–1.0
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: rate)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: rate)
        }
    }

    private var ringColor: Color {
        switch rate {
        case 0.7...: return .green
        case 0.4..<0.7: return .orange
        default: return .red
        }
    }
}

// MARK: - Small widget view

struct SmallWinRateView: View {
    let entry: WinRateEntry

    private var data: WinRateSummaryData { entry.data ?? .placeholder }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                WinRateRing(rate: data.winRate, lineWidth: 10)
                    .frame(width: 72, height: 72)

                VStack(spacing: 0) {
                    Text("\(data.winRatePercent)%")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Win")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Text("\(data.wins)W – \(data.losses)L")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .containerBackground(Color(.systemBackground), for: .widget)
    }
}

// MARK: - Medium widget view

struct MediumWinRateView: View {
    let entry: WinRateEntry

    private var data: WinRateSummaryData { entry.data ?? .placeholder }

    var body: some View {
        HStack(spacing: 20) {
            // Ring
            ZStack {
                WinRateRing(rate: data.winRate, lineWidth: 12)
                    .frame(width: 90, height: 90)

                VStack(spacing: 0) {
                    Text("\(data.winRatePercent)%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Win rate")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Stats grid
            VStack(alignment: .leading, spacing: 8) {
                statRow(label: "Matches", value: "\(data.totalMatches)")
                statRow(label: "Wins", value: "\(data.wins)", color: .green)
                statRow(label: "Losses", value: "\(data.losses)", color: .red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .containerBackground(Color(.systemBackground), for: .widget)
    }

    private func statRow(label: String, value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Widget definition

struct WinRateSummaryWidget: Widget {
    static let kind = "WinRateSummaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: WinRateProvider()) { entry in
            WinRateWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Win Rate")
        .description("Shows your overall win/loss record and win-rate percentage.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Entry view dispatcher

struct WinRateWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WinRateEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWinRateView(entry: entry)
        case .systemMedium:
            MediumWinRateView(entry: entry)
        default:
            SmallWinRateView(entry: entry)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Win Rate Small", as: .systemSmall) {
    WinRateSummaryWidget()
} timeline: {
    WinRateEntry.placeholder
}

#Preview("Win Rate Medium", as: .systemMedium) {
    WinRateSummaryWidget()
} timeline: {
    WinRateEntry.placeholder
}
#endif
