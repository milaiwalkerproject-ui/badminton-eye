import SwiftUI
import SwiftData

struct PlayerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Player.name) private var players: [Player]
    @Query private var matches: [PersistedMatch]

    @State private var searchText = ""
    @State private var showNewPlayerSheet = false
    @State private var playerToEdit: Player?
    @State private var localization = LocalizationManager.shared

    private var filteredPlayers: [Player] {
        if searchText.isEmpty {
            return players
        }
        return players.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            ForEach(filteredPlayers) { player in
                NavigationLink {
                    HeadToHeadView(player: player)
                } label: {
                    playerRow(player)
                }
                .swipeActions(edge: .trailing) {
                    Button(localization.localized("players.edit")) {
                        playerToEdit = player
                    }
                    .tint(.blue)
                }
            }
        }
        .searchable(text: $searchText, prompt: localization.localized("players.search"))
        .navigationTitle(localization.localized("players.title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showNewPlayerSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showNewPlayerSheet) {
            NavigationStack {
                PlayerProfileView(player: nil)
            }
        }
        .sheet(item: $playerToEdit) { player in
            NavigationStack {
                PlayerProfileView(player: player)
            }
        }
        .overlay {
            if filteredPlayers.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if players.isEmpty {
                ContentUnavailableView(
                    localization.localized("players.noPlayers"),
                    systemImage: "person.2",
                    description: Text(localization.localized("players.addFirst"))
                )
            }
        }
    }

    // MARK: - Player Row

    @ViewBuilder
    private func playerRow(_ player: Player) -> some View {
        let record = winLossRecord(for: player)
        let total = record.wins + record.losses
        let winPct = total > 0 ? Int(round(Double(record.wins) / Double(total) * 100)) : 0

        HStack(spacing: BE.Space.m) {
            avatarView(for: player, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(player.name)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                if total > 0 {
                    Text("\(record.wins)W · \(record.losses)L · \(winPct)%")
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text("No matches yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: BE.Space.s)

            if total > 0 {
                Text("\(total)")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule(style: .continuous).fill(Color(.tertiarySystemFill)))
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    static let avatarColors: [Color] = [
        .blue, .green, .orange, .purple,
        .pink, .teal, .indigo, .mint
    ]

    @ViewBuilder
    func avatarView(for player: Player, size: CGFloat) -> some View {
        if let photoData = player.photoData,
           let uiImage = UIImage(data: photoData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            let initial = player.name.first.map(String.init) ?? "?"
            let colorIndex = abs(player.name.hashValue) % Self.avatarColors.count
            Circle()
                .fill(Self.avatarColors[colorIndex])
                .frame(width: size, height: size)
                .overlay {
                    Text(initial.uppercased())
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white)
                }
        }
    }

    struct WinLoss {
        var wins: Int
        var losses: Int
    }

    func winLossRecord(for player: Player) -> WinLoss {
        var wins = 0
        var losses = 0

        for match in matches where match.isComplete {
            let isSideA = match.playerAName == player.name || match.playerA2Name == player.name
            let isSideB = match.playerBName == player.name || match.playerB2Name == player.name

            if isSideA {
                if match.winnerSide == "sideA" { wins += 1 }
                else if match.winnerSide == "sideB" { losses += 1 }
            } else if isSideB {
                if match.winnerSide == "sideB" { wins += 1 }
                else if match.winnerSide == "sideA" { losses += 1 }
            }
        }

        return WinLoss(wins: wins, losses: losses)
    }
}
