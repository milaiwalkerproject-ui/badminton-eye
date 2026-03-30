import SwiftUI
import WatchKit
import ScoringEngine

struct WatchScoringView: View {
    @State var viewModel: WatchMatchViewModel
    @State private var previousGameCount: Int = 0
    @State private var wasMatchActive: Bool = true
    @AppStorage("hapticFeedbackEnabled") private var hapticEnabled = true

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Side A tap zone (top half)
                Button {
                    let gamesBefore = viewModel.completedGames.count
                    viewModel.scorePoint(for: .sideA)
                    playHaptic(gamesBefore: gamesBefore)
                } label: {
                    WatchScoreDisplay(
                        score: viewModel.scoreA,
                        teamName: viewModel.teamAName,
                        isServing: viewModel.servingSide == .sideA,
                        color: .blue
                    )
                }
                .buttonStyle(.plain)
                .frame(height: geo.size.height / 2)

                // Side B tap zone (bottom half)
                Button {
                    let gamesBefore = viewModel.completedGames.count
                    viewModel.scorePoint(for: .sideB)
                    playHaptic(gamesBefore: gamesBefore)
                } label: {
                    WatchScoreDisplay(
                        score: viewModel.scoreB,
                        teamName: viewModel.teamBName,
                        isServing: viewModel.servingSide == .sideB,
                        color: .red
                    )
                }
                .buttonStyle(.plain)
                .frame(height: geo.size.height / 2)
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .center) {
            GameDotsIndicator(
                currentGame: viewModel.currentGameNumber,
                totalGames: viewModel.state?.scoringRules.maxGames ?? 3
            )
        }
        .overlay(alignment: .topTrailing) {
            if viewModel.isOffline {
                Image(systemName: "wifi.slash")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .padding(4)
            }
        }
    }

    private func playHaptic(gamesBefore: Int) {
        guard hapticEnabled else { return }
        if !viewModel.isMatchActive {
            WKInterfaceDevice.current().play(.notification)
        } else if viewModel.completedGames.count > gamesBefore {
            WKInterfaceDevice.current().play(.success)
        } else {
            WKInterfaceDevice.current().play(.click)
        }
    }
}

struct GameDotsIndicator: View {
    let currentGame: Int
    let totalGames: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...totalGames, id: \.self) { game in
                Circle()
                    .fill(game <= currentGame ? Color.white : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.black.opacity(0.5))
        .clipShape(Capsule())
    }
}
