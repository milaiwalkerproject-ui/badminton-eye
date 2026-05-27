import SwiftUI
import SwiftData

struct HeadToHeadView: View {
    let player: Player

    @Query private var allMatches: [PersistedMatch]

    @State private var selectedOpponent: String?
    @State private var localization = LocalizationManager.shared

    private var playerMatches: [PersistedMatch] {
        allMatches.filter { match in
            match.isComplete && (
                match.playerAName == player.name ||
                match.playerBName == player.name ||
                match.playerA2Name == player.name ||
                match.playerB2Name == player.name
            )
        }
        .sorted { ($0.startedAt) > ($1.startedAt) }
    }

    private var displayedMatches: [PersistedMatch] {
        guard let opponent = selectedOpponent else {
            return playerMatches
        }
        return playerMatches.filter { match in
            match.playerAName == opponent ||
            match.playerBName == opponent ||
            match.playerA2Name == opponent ||
            match.playerB2Name == opponent
        }
    }

    private var overallRecord: (wins: Int, losses: Int) {
        computeRecord(from: displayedMatches)
    }

    private var winRate: Double {
        let total = overallRecord.wins + overallRecord.losses
        guard total > 0 else { return 0 }
        return Double(overallRecord.wins) / Double(total) * 100
    }

    private var opponentBreakdown: [(name: String, wins: Int, losses: Int)] {
        var opponents: [String: (wins: Int, losses: Int)] = [:]

        for match in playerMatches {
            let opponentNames = extractOpponents(from: match)
            let isWin = isPlayerWin(match)

            for opponent in opponentNames {
                var record = opponents[opponent, default: (0, 0)]
                if isWin { record.wins += 1 } else { record.losses += 1 }
                opponents[opponent] = record
            }
        }

        return opponents
            .map { (name: $0.key, wins: $0.value.wins, losses: $0.value.losses) }
            .sorted { $0.wins + $0.losses > $1.wins + $1.losses }
    }

    var body: some View {
        List {
            // Header: Avatar + Name + Overall Record
            Section {
                VStack(spacing: 12) {
                    avatarView(size: 80)

                    Text(player.name)
                        .font(.title2)
                        .fontWeight(.bold)

                    HStack(spacing: 24) {
                        VStack {
                            Text("\(overallRecord.wins)")
                                .font(.system(size: 44, weight: .bold))
                                .foregroundStyle(.green)
                            Text(localization.localized("stats.wins"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text("-")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.secondary)

                        VStack {
                            Text("\(overallRecord.losses)")
                                .font(.system(size: 44, weight: .bold))
                                .foregroundStyle(.red)
                            Text(localization.localized("stats.losses"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(String(format: "%.0f%% win rate", winRate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let opponent = selectedOpponent {
                        Button {
                            selectedOpponent = nil
                        } label: {
                            Label("vs \(opponent)", systemImage: "xmark.circle.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            // Opponent Breakdown
            if !opponentBreakdown.isEmpty && selectedOpponent == nil {
                Section(localization.localized("headtohead.opponents")) {
                    ForEach(opponentBreakdown, id: \.name) { opponent in
                        Button {
                            selectedOpponent = opponent.name
                        } label: {
                            HStack {
                                Text(opponent.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(opponent.wins)W - \(opponent.losses)L")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }

            // Match History
            Section(selectedOpponent != nil ? String(format: localization.localized("headtohead.matchesVs"), selectedOpponent!) : localization.localized("headtohead.allMatches")) {
                if displayedMatches.isEmpty {
                    Text(localization.localized("history.noMatches"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(displayedMatches) { match in
                        matchRow(match)
                    }
                }
            }
        }
        .navigationTitle(localization.localized("headtohead.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    StatsView(playerName: player.name)
                } label: {
                    Label(localization.localized("stats.title"), systemImage: "chart.bar.xaxis")
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func avatarView(size: CGFloat) -> some View {
        if let photoData = player.photoData,
           let uiImage = UIImage(data: photoData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            let initial = player.name.first.map(String.init) ?? "?"
            let colorIndex = abs(player.name.hashValue) % PlayerListView.avatarColors.count
            Circle()
                .fill(PlayerListView.avatarColors[colorIndex])
                .frame(width: size, height: size)
                .overlay {
                    Text(initial.uppercased())
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(.white)
                }
        }
    }

    @ViewBuilder
    private func matchRow(_ match: PersistedMatch) -> some View {
        let won = isPlayerWin(match)
        let opponents = extractOpponents(from: match)

        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("vs " + opponents.joined(separator: " & "))
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(match.startedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(scoreText(for: match))
                .font(.caption)
                .monospaced()
                .foregroundStyle(.secondary)

            Text(won ? "W" : "L")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(won ? .green : .red)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    (won ? Color.green : Color.red).opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 4)
                )
        }
    }

    // MARK: - Helpers

    private func computeRecord(from matches: [PersistedMatch]) -> (wins: Int, losses: Int) {
        var wins = 0, losses = 0
        for match in matches {
            if isPlayerWin(match) { wins += 1 } else { losses += 1 }
        }
        return (wins, losses)
    }

    private func isPlayerWin(_ match: PersistedMatch) -> Bool {
        let isSideA = match.playerAName == player.name || match.playerA2Name == player.name
        if isSideA { return match.winnerSide == "sideA" }
        return match.winnerSide == "sideB"
    }

    private func extractOpponents(from match: PersistedMatch) -> [String] {
        let isSideA = match.playerAName == player.name || match.playerA2Name == player.name
        var opponents: [String] = []

        if isSideA {
            if let name = match.playerBName, !name.isEmpty { opponents.append(name) }
            if let name = match.playerB2Name, !name.isEmpty { opponents.append(name) }
        } else {
            if let name = match.playerAName, !name.isEmpty { opponents.append(name) }
            if let name = match.playerA2Name, !name.isEmpty { opponents.append(name) }
        }

        return opponents.isEmpty ? ["Unknown"] : opponents
    }

    private func scoreText(for match: PersistedMatch) -> String {
        var games: [String] = []
        games.append("\(match.game1ScoreA)-\(match.game1ScoreB)")
        if let s2a = match.game2ScoreA, let s2b = match.game2ScoreB {
            games.append("\(s2a)-\(s2b)")
        }
        if let s3a = match.game3ScoreA, let s3b = match.game3ScoreB {
            games.append("\(s3a)-\(s3b)")
        }
        return games.joined(separator: " ")
    }
}
