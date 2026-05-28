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

    // Any finished match (completed OR abandoned) that has at least one
    // recorded game video. Footage is recorded for both completed and
    // abandoned matches — abandoned matches finalize their in-flight game on
    // teardown.
    //
    // PERF: the "has a non-empty video" filter is pushed into the predicate so
    // SQLite evaluates it — previously `body` filtered in Swift via
    // `allFinished.filter { $0.gameVideos?.contains … }`, which FAULTED the
    // `gameVideos` to-many relationship for every finished match on the main
    // thread. Because this tab is built eagerly inside the root `TabView`, that
    // relationship-faulting ran during launch and was a measured top cost of
    // the cold-launch main-thread hang (Time Profiler: `_newValuesForRelationship`
    // / `objectIDsForRelationshipNamed:`). Filtering in SQL avoids materializing
    // those rows at all.
    @Query(
        filter: #Predicate<PersistedMatch> { match in
            (match.isComplete || match.isAbandoned) &&
            (match.gameVideos?.contains { !$0.fileName.isEmpty } ?? false)
        },
        sort: \PersistedMatch.startedAt,
        order: .reverse
    )
    private var matches: [PersistedMatch]

    /// Presents the shared video-import / Hawk-Eye challenge flow
    /// (`ChallengeVideoView`). Footage is where users look for "Import Video",
    /// so the entry point lives here in addition to the Matches tab.
    @State private var showVideoImport = false

    var body: some View {
        Group {
            if matches.isEmpty {
                ContentUnavailableView {
                    Label("No footage yet", systemImage: "film.stack")
                } description: {
                    Text("Play a match — the camera records each game automatically.")
                        .multilineTextAlignment(.center)
                } actions: {
                    Button {
                        showVideoImport = true
                    } label: {
                        Label("Import Video", systemImage: "square.and.arrow.down.on.square")
                    }
                    .buttonStyle(.borderedProminent)
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showVideoImport = true
                } label: {
                    Label("Import Video", systemImage: "square.and.arrow.down.on.square")
                }
                .accessibilityLabel("Import video")
            }
        }
        .sheet(isPresented: $showVideoImport) {
            ChallengeVideoView()
        }
    }
}

// MARK: - Row

private struct FootageRow: View {
    let match: PersistedMatch

    /// Number of recorded game videos via the wired `gameVideos` relationship.
    private var gameCount: Int {
        match.gameVideos?.count ?? 0
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
