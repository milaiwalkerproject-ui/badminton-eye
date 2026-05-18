import SwiftUI
import ScoringEngine

struct GameEndOverlay: View {
    let viewModel: LiveMatchViewModel
    @State private var localization = LocalizationManager.shared

    private var completedGame: GameState? { viewModel.justCompletedGame }

    private var winnerName: String {
        guard let game = completedGame else { return "" }
        return game.scoreA > game.scoreB
            ? (viewModel.state.teamANames.first ?? "Team A")
            : (viewModel.state.teamBNames.first ?? "Team B")
    }

    private var winnerIsA: Bool {
        guard let g = completedGame else { return true }
        return g.scoreA > g.scoreB
    }

    var body: some View {
        ZStack {
            // Blurred backdrop reveals the live match underneath — feels iOS-native.
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.15).ignoresSafeArea())

            VStack(spacing: BE.Space.l) {
                Text(localization.localized("game.over"))
                    .font(BE.eyebrow)
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.7))

                if let game = completedGame {
                    Text("\(localization.localized("match.game")) \(game.gameNumber)")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)

                    HStack(spacing: BE.Space.l) {
                        scoreColumn(game.scoreA, dimmed: !winnerIsA, accent: BE.TeamA.accent)
                        Text("–")
                            .font(.system(size: 40, weight: .light, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                        scoreColumn(game.scoreB, dimmed: winnerIsA, accent: BE.TeamB.accent)
                    }

                    Label {
                        Text("\(winnerName) wins the game")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                    } icon: {
                        Image(systemName: "trophy.fill")
                    }
                    .foregroundStyle(BE.serveAccent)
                    .padding(.horizontal, BE.Space.m)
                    .padding(.vertical, BE.Space.s)
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                }

                HStack(spacing: BE.Space.m) {
                    Button {
                        viewModel.undo()
                    } label: {
                        Label(localization.localized("match.undo"), systemImage: "arrow.uturn.backward")
                            .font(.system(.headline, design: .rounded).weight(.semibold))
                            .padding(.horizontal, BE.Space.l)
                            .padding(.vertical, 14)
                            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                            .foregroundStyle(.white)
                    }

                    Button {
                        viewModel.showGameEndOverlay = false
                    } label: {
                        Text(localization.localized("game.continue"))
                            .font(.system(.headline, design: .rounded).weight(.semibold))
                            .padding(.horizontal, BE.Space.l)
                            .padding(.vertical, 14)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.white)
                            )
                            .foregroundStyle(.black)
                    }
                }
            }
            .padding(BE.Space.xl)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        .task {
            try? await Task.sleep(for: .seconds(3))
            if viewModel.showGameEndOverlay {
                viewModel.showGameEndOverlay = false
            }
        }
    }

    private func scoreColumn(_ score: Int, dimmed: Bool, accent: Color) -> some View {
        Text("\(score)")
            .font(.system(size: 76, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(dimmed ? .white.opacity(0.55) : .white)
            .shadow(color: dimmed ? .clear : accent.opacity(0.6), radius: 14)
    }
}
