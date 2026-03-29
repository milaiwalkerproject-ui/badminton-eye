import ActivityKit
import WidgetKit
import SwiftUI

struct BadmintonEyeLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MatchActivityAttributes.self) { context in
            // Lock screen expanded view
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Dynamic Island
                DynamicIslandExpandedRegion(.center) {
                    expandedIslandView(context: context)
                }
            } compactLeading: {
                Text("\(context.state.scoreA)")
                    .font(.headline)
                    .fontWeight(.bold)
            } compactTrailing: {
                Text("\(context.state.scoreB)")
                    .font(.headline)
                    .fontWeight(.bold)
            } minimal: {
                Text("\(context.state.scoreA)")
                    .font(.caption)
                    .fontWeight(.bold)
            }
        }
    }

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<MatchActivityAttributes>) -> some View {
        VStack(spacing: 6) {
            // Player names
            HStack {
                Text(context.attributes.teamAName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Text("vs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(context.attributes.teamBName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }

            // Large current score with server indicator
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    if context.state.serverSide == "sideA" {
                        Image(systemName: "arrowtriangle.right.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    Text("\(context.state.scoreA)")
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.bold)
                }

                Text("-")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text("\(context.state.scoreB)")
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.bold)
                    if context.state.serverSide == "sideB" {
                        Image(systemName: "arrowtriangle.left.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
            }

            // Game indicator dots (best of 3)
            HStack(spacing: 8) {
                gameDots(won: context.state.gamesWonA, label: "A")
                Spacer()
                Text("Game \(context.state.gameNumber)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                gameDots(won: context.state.gamesWonB, label: "B")
            }

            // Tap hint
            if !context.state.isComplete {
                Text("Tap to open")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Match Complete")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .padding()
    }

    // MARK: - Expanded Dynamic Island

    @ViewBuilder
    private func expandedIslandView(context: ActivityViewContext<MatchActivityAttributes>) -> some View {
        VStack(spacing: 4) {
            // Names
            HStack {
                Text(context.attributes.teamAName)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text(context.attributes.teamBName)
                    .font(.caption)
                    .lineLimit(1)
            }

            // Score
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    if context.state.serverSide == "sideA" {
                        Image(systemName: "arrowtriangle.right.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow)
                    }
                    Text("\(context.state.scoreA)")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                Text("-")
                    .font(.body)
                    .foregroundStyle(.secondary)
                HStack(spacing: 2) {
                    Text("\(context.state.scoreB)")
                        .font(.title2)
                        .fontWeight(.bold)
                    if context.state.serverSide == "sideB" {
                        Image(systemName: "arrowtriangle.left.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow)
                    }
                }
            }

            // Game dots
            HStack(spacing: 4) {
                gameDots(won: context.state.gamesWonA, label: "A")
                Spacer()
                gameDots(won: context.state.gamesWonB, label: "B")
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Game Dots Helper

    @ViewBuilder
    private func gameDots(won: Int, label: String) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index < won ? Color.accentColor : Color.clear)
                    .stroke(index < won ? Color.clear : Color.secondary, lineWidth: 1)
                    .frame(width: 8, height: 8)
            }
        }
    }
}
