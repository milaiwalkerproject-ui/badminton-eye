import SwiftUI
import ScoringEngine

struct MatchEndView: View {
    let state: MatchState
    var onNewMatch: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var localization = LocalizationManager.shared

    private var isAbandoned: Bool { state.matchPhase == .abandoned }

    private var winnerNames: [String] {
        guard let winner = state.matchWinner else { return [] }
        return winner == .sideA ? state.teamANames : state.teamBNames
    }

    private var winnerSide: Side? { state.matchWinner }

    private var heroGradient: LinearGradient {
        if isAbandoned {
            return LinearGradient(
                colors: [Color(red: 0.30, green: 0.32, blue: 0.38),
                         Color(red: 0.15, green: 0.16, blue: 0.20)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        return winnerSide == .sideA ? BE.TeamA.gradient : BE.TeamB.gradient
    }

    var body: some View {
        ScrollView {
            VStack(spacing: BE.Space.l) {
                hero
                scorecard
                if state.format != .singles { rosterCard }
                Spacer(minLength: BE.Space.l)
                newMatchButton
            }
            .padding(.horizontal, BE.Space.m)
            .padding(.bottom, BE.Space.l)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack {
            heroGradient
            LinearGradient(
                colors: [.white.opacity(0.22), .clear],
                startPoint: .top, endPoint: .center
            )
            .blendMode(.plusLighter)

            VStack(spacing: BE.Space.s) {
                Image(systemName: isAbandoned ? "flag.slash.fill" : "trophy.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                    .padding(.top, BE.Space.l)

                Text(isAbandoned ? "Match Abandoned" : winnerNames.joined(separator: " & "))
                    .font(BE.displayTitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, BE.Space.l)

                if !isAbandoned {
                    Text("WINS")
                        .font(BE.eyebrow)
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.bottom, BE.Space.s)
                }
            }
            .padding(.bottom, BE.Space.l)
        }
        .clipShape(BE.card(28))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
    }

    // MARK: - Scorecard

    private var scorecard: some View {
        VStack(spacing: BE.Space.m) {
            // Column headers
            HStack {
                Text(" ").frame(width: 88, alignment: .leading)
                Spacer()
                teamHeader(name: state.teamANames.first ?? "Team A", accent: BE.TeamA.top, winning: winnerSide == .sideA)
                teamHeader(name: state.teamBNames.first ?? "Team B", accent: BE.TeamB.top, winning: winnerSide == .sideB)
            }

            ForEach(Array(state.games.enumerated()), id: \.offset) { idx, game in
                HStack {
                    Text("\(localization.localized("match.game")) \(idx + 1)")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 88, alignment: .leading)
                    Spacer()
                    scoreCell(game.scoreA, winning: game.scoreA > game.scoreB)
                    scoreCell(game.scoreB, winning: game.scoreB > game.scoreA)
                }
                if idx < state.games.count - 1 {
                    Divider().opacity(0.4)
                }
            }

            Divider().padding(.vertical, 2)

            HStack {
                Text(localization.localized("match.games"))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .frame(width: 88, alignment: .leading)
                Spacer()
                totalsCell(state.gamesWon.sideA, winning: winnerSide == .sideA)
                totalsCell(state.gamesWon.sideB, winning: winnerSide == .sideB)
            }
        }
        .padding(BE.Space.l)
        .background(BE.card(20).fill(Color(.secondarySystemGroupedBackground)))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private func teamHeader(name: String, accent: Color, winning: Bool) -> some View {
        VStack(spacing: 2) {
            Circle().fill(accent).frame(width: 8, height: 8)
            Text(name)
                .font(.system(.subheadline, design: .rounded).weight(winning ? .bold : .semibold))
                .lineLimit(1)
        }
        .frame(width: 84)
    }

    private func scoreCell(_ value: Int, winning: Bool) -> some View {
        Text("\(value)")
            .font(.system(size: 26, weight: winning ? .bold : .regular, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(winning ? .primary : .secondary)
            .frame(width: 84)
    }

    private func totalsCell(_ value: Int, winning: Bool) -> some View {
        Text("\(value)")
            .font(.system(size: 26, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(winning ? .primary : .secondary)
            .frame(width: 84)
    }

    // MARK: - Roster

    private var rosterCard: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TEAM A").font(BE.eyebrow).tracking(1.4).foregroundStyle(BE.TeamA.top)
                ForEach(state.teamANames, id: \.self) { name in
                    Text(name).font(.system(.subheadline, design: .rounded))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("TEAM B").font(BE.eyebrow).tracking(1.4).foregroundStyle(BE.TeamB.top)
                ForEach(state.teamBNames, id: \.self) { name in
                    Text(name).font(.system(.subheadline, design: .rounded))
                }
            }
        }
        .padding(BE.Space.l)
        .background(BE.card(20).fill(Color(.secondarySystemGroupedBackground)))
    }

    // MARK: - Action

    private var newMatchButton: some View {
        Button {
            if let onNewMatch { onNewMatch() } else { dismiss() }
        } label: {
            Text(localization.localized("match.new"))
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(BE.card(16).fill(Color.accentColor))
                .foregroundStyle(.white)
                .shadow(color: Color.accentColor.opacity(0.3), radius: 12, y: 6)
        }
        .padding(.top, BE.Space.s)
    }
}
