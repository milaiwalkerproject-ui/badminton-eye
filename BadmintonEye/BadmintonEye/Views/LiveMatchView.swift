import SwiftUI
import ScoringEngine

struct LiveMatchView: View {
    @State var viewModel: LiveMatchViewModel
    var onMatchEnd: (() -> Void)?
    @State private var showAbandonAlert = false
    @Environment(\.dismiss) private var dismiss

    private var completedGameScores: String {
        viewModel.state.games.map { game in
            "\(game.scoreA)-\(game.scoreB)"
        }.joined(separator: " | ")
    }

    var body: some View {
        ZStack {
            // Half-screen tap zones
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Side A tap zone
                    Button {
                        viewModel.scorePoint(for: .sideA)
                    } label: {
                        ScorePanel(
                            score: viewModel.state.currentGame.scoreA,
                            teamName: viewModel.state.teamANames.first ?? "Team A",
                            isServing: viewModel.state.currentServer.side == .sideA,
                            serviceCourt: viewModel.state.currentServer.side == .sideA
                                ? viewModel.state.serviceCourt : nil,
                            playerNames: viewModel.state.teamANames,
                            backgroundColor: Color.blue.opacity(0.85)
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .frame(
                        width: geometry.size.width / 2,
                        height: geometry.size.height
                    )

                    // Side B tap zone
                    Button {
                        viewModel.scorePoint(for: .sideB)
                    } label: {
                        ScorePanel(
                            score: viewModel.state.currentGame.scoreB,
                            teamName: viewModel.state.teamBNames.first ?? "Team B",
                            isServing: viewModel.state.currentServer.side == .sideB,
                            serviceCourt: viewModel.state.currentServer.side == .sideB
                                ? viewModel.state.serviceCourt : nil,
                            playerNames: viewModel.state.teamBNames,
                            backgroundColor: Color.red.opacity(0.85)
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .frame(
                        width: geometry.size.width / 2,
                        height: geometry.size.height
                    )
                }
            }
            .ignoresSafeArea()

            // Top bar overlay
            VStack {
                HStack {
                    // Undo button
                    Button {
                        viewModel.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .disabled(!viewModel.canUndo)
                    .opacity(viewModel.canUndo ? 1.0 : 0.4)

                    Spacer()

                    // Game info
                    VStack(spacing: 2) {
                        Text("Game \(viewModel.state.currentGame.gameNumber)")
                            .font(.headline)
                            .foregroundStyle(.white)

                        if !viewModel.state.games.isEmpty {
                            Text(completedGameScores)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.3))
                                .clipShape(Capsule())
                        }
                    }

                    Spacer()

                    // End match button
                    Button {
                        showAbandonAlert = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()
            }

            // Game end overlay
            if viewModel.showGameEndOverlay {
                GameEndOverlay(viewModel: viewModel)
            }
        }
        .alert("End Match?", isPresented: $showAbandonAlert) {
            Button("Cancel", role: .cancel) {}
            Button("End Match", role: .destructive) {
                viewModel.abandonMatch()
            }
        } message: {
            Text("The match will be recorded as abandoned.")
        }
        .navigationDestination(
            isPresented: Binding(
                get: { viewModel.state.matchPhase == .complete },
                set: { _ in }
            )
        ) {
            MatchEndView(state: viewModel.state, onNewMatch: onMatchEnd)
        }
        .navigationDestination(
            isPresented: Binding(
                get: { viewModel.state.matchPhase == .abandoned },
                set: { _ in }
            )
        ) {
            MatchEndView(state: viewModel.state, onNewMatch: onMatchEnd)
        }
    }
}
