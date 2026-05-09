import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct LiveScoreEntry: TimelineEntry {
    let date: Date
    let data: LiveScoreData?

    static var placeholder: LiveScoreEntry {
        LiveScoreEntry(date: Date(), data: .placeholder)
    }
}

// MARK: - Timeline provider

struct LiveScoreProvider: TimelineProvider {
    typealias Entry = LiveScoreEntry

    func placeholder(in context: Context) -> LiveScoreEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (LiveScoreEntry) -> Void) {
        let data = LiveScoreData.load()
        completion(LiveScoreEntry(date: Date(), data: data ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LiveScoreEntry>) -> Void) {
        let data = LiveScoreData.load()
        let entry = LiveScoreEntry(date: Date(), data: data)

        // If a live match is ongoing refresh every 30 seconds, otherwise check every 5 minutes.
        let nextRefresh: Date
        if let d = data, !d.isComplete {
            nextRefresh = Calendar.current.date(byAdding: .second, value: 30, to: Date()) ?? Date()
        } else {
            nextRefresh = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
        }

        let timeline = Timeline(entries: [entry], policy: .after(nextRefresh))
        completion(timeline)
    }
}

// MARK: - Small widget view (score only)

struct SmallLiveScoreView: View {
    let entry: LiveScoreEntry

    private var data: LiveScoreData { entry.data ?? .placeholder }

    var body: some View {
        VStack(spacing: 4) {
            Text("LIVE")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(data.isComplete ? .secondary : .red)

            HStack(alignment: .center, spacing: 12) {
                scoreColumn(name: data.sideAName, score: data.scoreA)
                Text("—")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                scoreColumn(name: data.sideBName, score: data.scoreB)
            }

            Text("G\(data.gameNumber) · \(data.gamesWonA)–\(data.gamesWonB)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .containerBackground(Color(.systemBackground), for: .widget)
    }

    private func scoreColumn(name: String, score: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(score)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
            Text(name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Medium widget view (score + server indicator)

struct MediumLiveScoreView: View {
    let entry: LiveScoreEntry

    private var data: LiveScoreData { entry.data ?? .placeholder }

    var body: some View {
        HStack(spacing: 0) {
            // Left: score block
            VStack(alignment: .leading, spacing: 6) {
                liveLabel

                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    sideScoreRow(
                        name: data.sideAName,
                        score: data.scoreA,
                        isServing: data.serverSide == "sideA"
                    )
                    Text("–")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    sideScoreRow(
                        name: data.sideBName,
                        score: data.scoreB,
                        isServing: data.serverSide == "sideB"
                    )
                }

                Text("Game \(data.gameNumber) of \(maxGames)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().padding(.vertical, 4)

            // Right: games-won tally
            VStack(spacing: 4) {
                Text("Games")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    gamesWonBadge(count: data.gamesWonA, name: data.sideAName)
                    gamesWonBadge(count: data.gamesWonB, name: data.sideBName)
                }
            }
            .padding(.leading, 12)
        }
        .padding(.horizontal, 16)
        .containerBackground(Color(.systemBackground), for: .widget)
    }

    private var liveLabel: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(data.isComplete ? Color.secondary : Color.red)
                .frame(width: 6, height: 6)
            Text(data.isComplete ? "ENDED" : "LIVE")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(data.isComplete ? .secondary : .red)
        }
    }

    private var maxGames: Int { 3 }

    private func sideScoreRow(name: String, score: Int, isServing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text("\(score)")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                if isServing {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                        .offset(y: -12)
                }
            }
            Text(name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.secondary)
        }
    }

    private func gamesWonBadge(count: Int, name: String) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.semibold)
            Text(name)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

// MARK: - Widget definition

struct LiveScoreWidget: Widget {
    static let kind = "LiveScoreWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: LiveScoreProvider()) { entry in
            LiveScoreWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Live Score")
        .description("Shows the current game score for an active Badminton Eye match.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Entry view dispatcher

struct LiveScoreWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LiveScoreEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallLiveScoreView(entry: entry)
        case .systemMedium:
            MediumLiveScoreView(entry: entry)
        default:
            SmallLiveScoreView(entry: entry)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Small", as: .systemSmall) {
    LiveScoreWidget()
} timeline: {
    LiveScoreEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    LiveScoreWidget()
} timeline: {
    LiveScoreEntry.placeholder
}
#endif
