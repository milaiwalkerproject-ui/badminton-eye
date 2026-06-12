import SwiftUI
import SwiftData

struct PlayerPickerView: View {
    @Binding var selectedName: String
    let label: String
    let excludeNames: [String]

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Player.name) private var allPlayers: [Player]
    @Query(sort: \PersistedMatch.startedAt, order: .reverse) private var recentMatches: [PersistedMatch]

    @State private var searchText = ""

    private var recentOpponents: [String] {
        Self.recentOpponents(
            fromMatchNameLists: recentMatches.map { match in
                [match.playerAName, match.playerBName,
                 match.playerA2Name, match.playerB2Name].compactMap { $0 }
            },
            excluding: excludeNames
        )
    }

    // MARK: - Recents derivation (placeholder-aware, testable)

    /// Default names the app substitutes when a match is started without real
    /// player names — `MatchState` falls back to "Player 1"/"Player 2" for
    /// singles and `MatchSetupView` fills "Player A1"… for doubles/mixed.
    /// They're bookkeeping placeholders, not people, so they must never
    /// surface as "Recent Opponents".
    static let placeholderPlayerNames: Set<String> = [
        "Player 1", "Player 2",
        "Player A1", "Player A2", "Player B1", "Player B2",
        "Side A", "Side B",
    ]

    /// Derives the recent-opponent chips from per-match name lists (most
    /// recent match first): de-duplicated, placeholder and excluded names
    /// dropped, capped at `limit`. Pure function so the filtering is unit
    /// tested without SwiftData.
    static func recentOpponents(
        fromMatchNameLists nameLists: [[String]],
        excluding excludeNames: [String],
        limit: Int = 5
    ) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for names in nameLists {
            for name in names {
                guard !name.isEmpty,
                      !placeholderPlayerNames.contains(name),
                      !excludeNames.contains(name),
                      !seen.contains(name) else { continue }
                seen.insert(name)
                result.append(name)
                if result.count >= limit { return result }
            }
        }
        return result
    }

    private var filteredPlayers: [Player] {
        let excluded = Set(excludeNames)
        let base = allPlayers.filter { !excluded.contains($0.name) }
        if searchText.isEmpty { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            // Recent Opponents chips
            if !recentOpponents.isEmpty && searchText.isEmpty {
                Section("Recent Opponents") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recentOpponents, id: \.self) { name in
                                Button {
                                    selectedName = name
                                    dismiss()
                                } label: {
                                    Text(name)
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.12))
                                        .foregroundStyle(.primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            // Full player list
            Section("All Players") {
                if filteredPlayers.isEmpty {
                    Text("No matching players")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredPlayers) { player in
                        Button {
                            selectedName = player.name
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                PlayerListView().avatarView(for: player, size: 32)
                                Text(player.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search players")
        .navigationTitle("Select \(label)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
