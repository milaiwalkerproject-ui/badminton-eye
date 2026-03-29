import SwiftUI
import ScoringEngine

struct MatchEndView: View {
    let state: MatchState
    @Environment(\.dismiss) private var dismiss

    private var winnerText: String {
        guard let winner = state.matchWinner else {
            return state.matchPhase == .abandoned ? "Match Abandoned" : "Match Over"
        }
        let names = winner == .sideA ? state.teamANames : state.teamBNames
        return "\(names.joined(separator: " & ")) Win!"
    }

    private var allGames: [GameState] {
        state.games
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Winner display
            Text(winnerText)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Scorecard
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("")
                        .frame(width: 80)
                    Spacer()
                    Text(state.teamANames.first ?? "Team A")
                        .font(.headline)
                        .frame(width: 80)
                    Text(state.teamBNames.first ?? "Team B")
                        .font(.headline)
                        .frame(width: 80)
                }

                Divider()

                // Game rows
                ForEach(Array(allGames.enumerated()), id: \.offset) { index, game in
                    HStack {
                        Text("Game \(index + 1)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Text("\(game.scoreA)")
                            .font(.title2.bold())
                            .foregroundStyle(
                                game.scoreA > game.scoreB
                                    ? .primary : .secondary
                            )
                            .frame(width: 80)
                        Text("\(game.scoreB)")
                            .font(.title2.bold())
                            .foregroundStyle(
                                game.scoreB > game.scoreA
                                    ? .primary : .secondary
                            )
                            .frame(width: 80)
                    }
                }

                Divider()

                // Games won summary
                HStack {
                    Text("Games")
                        .font(.subheadline.bold())
                        .frame(width: 80, alignment: .leading)
                    Spacer()
                    Text("\(state.gamesWon.sideA)")
                        .font(.title2.bold())
                        .frame(width: 80)
                    Text("\(state.gamesWon.sideB)")
                        .font(.title2.bold())
                        .frame(width: 80)
                }
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)

            // Player names for doubles
            if state.format != .singles {
                VStack(spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(state.teamANames, id: \.self) { name in
                                Text(name)
                                    .font(.subheadline)
                            }
                        }
                        Spacer()
                        Text("vs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            ForEach(state.teamBNames, id: \.self) { name in
                                Text(name)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                }
            }

            Spacer()

            // New Match button
            NavigationLink(destination: MatchSetupView().navigationBarBackButtonHidden(true)) {
                Text("New Match")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .navigationBarBackButtonHidden(true)
    }
}
