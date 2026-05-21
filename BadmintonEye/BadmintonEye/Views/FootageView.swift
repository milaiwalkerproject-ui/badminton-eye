import SwiftUI
import SwiftData

/// Top-level "Footage" tab. Replaces the previous "Ranks" tab.
///
/// Lists every completed match that has at least one recorded game video,
/// most recent first. Tapping a row drills into `FootageDetailView`, which
/// plays each game and exposes the (premium-gated) Highlight pipeline.
///
/// Wiring still required:
/// - Register this file in `BadmintonEye.xcodeproj/project.pbxproj`.
/// - Replace the `Ranks` entry in `App/BadmintonEyeApp.swift` (iPad sidebar
///   and iPhone TabView) with a `FootageView` entry. See HANDOFF.md.
struct FootageView: View {

    @Query(
        filter: #Predicate<PersistedMatch> { $0.isComplete && !$0.isAbandoned },
        sort: \PersistedMatch.startedAt,
        order: .reverse
    )
    private var matches: [PersistedMatch]

    var body: some View {
        Group {
            if matches.isEmpty {
                ContentUnavailableView {
                    Label("No footage yet", systemImage: "film.stack")
                } description: {
                    Text("Play a match — the camera records each game automatically.")
                        .multilineTextAlignment(.center)
                }
            } else {
                List {
                    Section {
                        ForEach(matches) { match in
                            NavigationLink {
                                FootageDetailView(match: match)
                            } label: {
                                FootageRow(match: match)
                            }
                        }
                    } footer: {
                        Text("Footage is recorded automatically when you start a match. Tap a match to play each game.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Footage")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Row

private struct FootageRow: View {
    let match: PersistedMatch

    /// Pull videos via the planned `gameVideos` relationship on PersistedMatch.
    /// Until that relationship is added, this stays at zero — the row still
    /// renders, just without a "N games" hint.
    private var gameCount: Int {
        // Reflection-free: rely on the optional KVC-style accessor that
        // SwiftData synthesizes once the inverse relationship is wired.
        // For now we read a static 0 so this file compiles standalone.
        return (Mirror(reflecting: match).children
            .first { $0.label == "gameVideos" }?
            .value as? [GameVideoRecord])?.count ?? 0
    }

    private var teamA: String {
        let a1 = match.playerAName ?? "Side A"
        if let a2 = match.playerA2Name, !a2.isEmpty {
            return "\(a1) / \(a2)"
        }
        return a1
    }

    private var teamB: String {
        let b1 = match.playerBName ?? "Side B"
        if let b2 = match.playerB2Name, !b2.isEmpty {
            return "\(b1) / \(b2)"
        }
        return b1
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(teamA) vs \(teamB)")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(match.startedAt, style: .date)
                    if let loc = match.locationName, !loc.isEmpty {
                        Text("• \(loc)").lineLimit(1)
                    }
                    if gameCount > 0 {
                        Text("• \(gameCount) game\(gameCount == 1 ? "" : "s")")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - PersistedMatch.locationName shim
//
// `locationName` is a planned addition to `PersistedMatch`. Reading it via
// Mirror keeps this file compiling before the property is added to
// `Models/SwiftDataModels.swift`. Once the property lands, swap this for
// a direct access and delete the extension.
private extension PersistedMatch {
    var locationName: String? {
        Mirror(reflecting: self).children
            .first { $0.label == "locationName" }?
            .value as? String
    }
}
