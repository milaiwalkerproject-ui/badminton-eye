import SwiftUI
import SwiftData
import ImageIO

struct PlayerListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Player.name) private var players: [Player]
    /// Only completed matches with a decided winner can contribute to the
    /// win/loss tallies below, so filter at the store level. The previous
    /// unfiltered `@Query` materialized EVERY match row (in-progress and
    /// abandoned included) just to compute the tallies — the dominant cost of
    /// first showing this tab. Equivalence with a full scan is pinned by
    /// `PlayerRecordsPredicateTests`.
    @Query(filter: #Predicate<PersistedMatch> { $0.isComplete && $0.winnerSide != nil })
    private var matches: [PersistedMatch]

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

    /// Win/loss record keyed by player name, computed in a SINGLE pass over
    /// the completed matches. Previously each row called `winLossRecord(for:)`,
    /// which re-scanned every match for every player on every body
    /// evaluation — O(players × matches) on each tab switch / render. This
    /// reduces that to O(matches) once per render.
    private var recordsByName: [String: WinLoss] {
        Self.winLossRecords(from: matches)
    }

    /// Single-pass tally. Internal + static so the unit test can feed it both
    /// the predicate-filtered set and a full scan and assert equal results.
    /// Keeps the original isComplete/winner guards, so it is agnostic to
    /// whether the input was pre-filtered by the store predicate.
    static func winLossRecords(from matches: [PersistedMatch]) -> [String: WinLoss] {
        var records: [String: WinLoss] = [:]
        for match in matches where match.isComplete {
            guard let winner = match.winnerSide else { continue }
            let sideAWon = winner == "sideA"
            let sideBWon = winner == "sideB"
            guard sideAWon || sideBWon else { continue }

            func tally(_ name: String?, didWin: Bool) {
                guard let name, !name.isEmpty else { return }
                var rec = records[name, default: WinLoss(wins: 0, losses: 0)]
                if didWin { rec.wins += 1 } else { rec.losses += 1 }
                records[name] = rec
            }
            tally(match.playerAName, didWin: sideAWon)
            tally(match.playerA2Name, didWin: sideAWon)
            tally(match.playerBName, didWin: sideBWon)
            tally(match.playerB2Name, didWin: sideBWon)
        }
        return records
    }

    var body: some View {
        let records = recordsByName
        return List {
            ForEach(filteredPlayers) { player in
                NavigationLink {
                    HeadToHeadView(player: player)
                } label: {
                    playerRow(player, record: records[player.name] ?? WinLoss(wins: 0, losses: 0))
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
    private func playerRow(_ player: Player, record: WinLoss) -> some View {
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

    func avatarView(for player: Player, size: CGFloat) -> some View {
        PlayerAvatarView(name: player.name, photoData: player.photoData, size: size)
    }

    struct WinLoss: Equatable {
        var wins: Int
        var losses: Int
    }
}

// MARK: - Avatar

/// Player avatar that decodes photos as downscaled thumbnails, off the main
/// thread, with the initials circle as an immediate placeholder.
///
/// Previously each row ran `UIImage(data:)` on the full-resolution photo
/// synchronously during list rendering. Photos saved before
/// `PlayerProfileView` started downscaling to 200px can be multi-megapixel,
/// so that decode was a per-row main-thread stall on the first tab switch.
struct PlayerAvatarView: View {
    let name: String
    let photoData: Data?
    let size: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            // The synchronous cache probe avoids a placeholder flash for
            // photos that have already been decoded once this session.
            if let image = thumbnail ?? photoData.flatMap(AvatarThumbnailStore.cached) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                initialsCircle
            }
        }
        .task(id: photoData) {
            // Empty data == "no photo": legacy NULL blobs read back as empty
            // Data after the externalStorage migration.
            guard let photoData, !photoData.isEmpty else {
                thumbnail = nil
                return
            }
            if let hit = AvatarThumbnailStore.cached(photoData) {
                thumbnail = hit
                return
            }
            thumbnail = await AvatarThumbnailStore.thumbnail(
                from: photoData,
                maxPixelSize: size * displayScale
            )
        }
    }

    private var initialsCircle: some View {
        let initial = name.first.map(String.init) ?? "?"
        let colorIndex = abs(name.hashValue) % PlayerListView.avatarColors.count
        return Circle()
            .fill(PlayerListView.avatarColors[colorIndex])
            .frame(width: size, height: size)
            .overlay {
                Text(initial.uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

/// Downscale-on-decode cache for player avatars. `CGImageSource` thumbnailing
/// caps the decode at the rendered pixel size instead of inflating the full
/// image, and the `NSCache` makes repeat renders free.
enum AvatarThumbnailStore {
    // NSCache is documented thread-safe ("you can add, remove, and query
    // items in the cache from different threads without having to lock the
    // cache yourself"), so this shared instance is safe despite not being
    // statically Sendable.
    nonisolated(unsafe) private static let cache = NSCache<NSData, UIImage>()

    static func cached(_ data: Data) -> UIImage? {
        cache.object(forKey: data as NSData)
    }

    /// Decodes off the calling actor. `maxPixelSize` is in pixels
    /// (point size × display scale).
    static func thumbnail(from data: Data, maxPixelSize: CGFloat) async -> UIImage? {
        if let hit = cached(data) { return hit }
        let decoded = await Task.detached(priority: .userInitiated) {
            decode(data, maxPixelSize: maxPixelSize)
        }.value
        if let decoded {
            cache.setObject(decoded, forKey: data as NSData)
        }
        return decoded
    }

    private static func decode(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixelSize, 1)
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
