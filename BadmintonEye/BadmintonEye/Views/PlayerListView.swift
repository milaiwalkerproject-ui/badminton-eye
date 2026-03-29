import SwiftUI
import SwiftData

struct PlayerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Player.name) private var players: [Player]
    @Query private var matches: [PersistedMatch]

    @State private var searchText = ""
    @State private var showNewPlayerSheet = false
    @State private var playerToEdit: Player?

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
                    Button("Edit") {
                        playerToEdit = player
                    }
                    .tint(.blue)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search players")
        .navigationTitle("Players")
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
                    "No Players",
                    systemImage: "person.2",
                    description: Text("Tap + to add your first player.")
                )
            }
        }
    }

    // MARK: - Player Row

    @ViewBuilder
    private func playerRow(_ player: Player) -> some View {
        HStack(spacing: 12) {
            avatarView(for: player, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.name)
                    .font(.body)
                    .fontWeight(.medium)

                let record = winLossRecord(for: player)
                Text("\(record.wins)W - \(record.losses)L")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
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
