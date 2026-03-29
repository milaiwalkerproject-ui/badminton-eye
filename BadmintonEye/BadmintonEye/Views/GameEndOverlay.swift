import SwiftUI
import ScoringEngine

struct GameEndOverlay: View {
    let viewModel: LiveMatchViewModel
    @State private var isVisible = true

    private var completedGame: GameState? {
        viewModel.justCompletedGame
    }

    private var winnerName: String {
        guard let game = completedGame else { return "" }
        if game.scoreA > game.scoreB {
            return viewModel.state.teamANames.first ?? "Team A"
        } else {
            return viewModel.state.teamBNames.first ?? "Team B"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Game Over")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                if let game = completedGame {
                    Text("Game \(game.gameNumber)")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))

                    HStack(spacing: 20) {
                        Text("\(game.scoreA)")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("-")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("\(game.scoreB)")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    Text("\(winnerName) wins!")
                        .font(.title2)
                        .foregroundStyle(.yellow)
                }

                HStack(spacing: 20) {
                    Button {
                        viewModel.undo()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.2))
                            .clipShape(Capsule())
                            .foregroundStyle(.white)
                    }

                    Button {
                        viewModel.showGameEndOverlay = false
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.yellow)
                            .clipShape(Capsule())
                            .foregroundStyle(.black)
                    }
                }
            }
            .padding(32)
        }
        .task {
            try? await Task.sleep(for: .seconds(3))
            if viewModel.showGameEndOverlay {
                viewModel.showGameEndOverlay = false
            }
        }
    }
}
