import SwiftUI
import SwiftData
import PhotosUI
import AVKit

/// RETIRED from the tab shell (restructure PR 5) — kept compiling for one
/// release per RESTRUCTURE-PLAN.md, then delete this file (and its pbxproj
/// entries FV1001/FV2001). Its jobs moved to:
/// - per-match footage → unified `MatchDetailView` (PR 2)
/// - photo-library import + imported-videos list → home screen
///   (`MatchHistoryView`, sharing `FootageImporter` and
///   `ImportedFootageDetailView` from here).
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

    // Imported (photo-library) videos — standalone records with no match.
    // Leaf-table SQL predicate per the launch-perf convention.
    @Query(
        filter: #Predicate<GameVideoRecord> { record in
            record.match == nil && !record.fileName.isEmpty
        },
        sort: \GameVideoRecord.startedAt,
        order: .reverse
    )
    private var importedVideos: [GameVideoRecord]

    /// Presents the shared video-import / Hawk-Eye challenge flow
    /// (`ChallengeVideoView`). Footage is where users look for "Import Video",
    /// so the entry point lives here in addition to the Matches tab.
    @State private var showVideoImport = false

    // Wave 1 Phase 4: photo-library import INTO Footage (analyzable/labelable,
    // exported with unmasked_import provenance).
    @Environment(\.modelContext) private var modelContext
    @State private var footageImportItem: PhotosPickerItem?
    @State private var isImportingFootage = false
    @State private var footageImportError: String?

    var body: some View {
        Group {
            if matches.isEmpty && importedVideos.isEmpty {
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
                    if !importedVideos.isEmpty {
                        Section {
                            ForEach(importedVideos) { record in
                                NavigationLink {
                                    ImportedFootageDetailView(record: record)
                                } label: {
                                    Label {
                                        Text(record.startedAt, style: .date)
                                    } icon: {
                                        Image(systemName: "square.and.arrow.down.on.square")
                                    }
                                }
                            }
                        } header: {
                            Text(LocalizationManager.shared.localized("footage.imported.section"))
                        }
                    }
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
                importMenu
            }
        }
        .sheet(isPresented: $showVideoImport) {
            ChallengeVideoView()
        }
        .onChange(of: footageImportItem) { _, item in
            handleFootageImport(item)
        }
        .alert("Import failed", isPresented: .constant(footageImportError != nil)) {
            Button("OK") { footageImportError = nil }
        } message: {
            Text(footageImportError ?? "")
        }
    }

    // MARK: - Import menu

    private var importMenu: some View {
        // Resolved outside the picker label: PhotosPicker's label closure is
        // nonisolated in the iOS 18.5 SDK, so it can't touch the main-actor
        // LocalizationManager directly.
        let importToFootageTitle = LocalizationManager.shared.localized("footage.importToFootage")
        return Menu {
            PhotosPicker(selection: $footageImportItem, matching: .videos) {
                Label(importToFootageTitle,
                      systemImage: "square.and.arrow.down.on.square")
            }
            Button {
                showVideoImport = true
            } label: {
                Label("Hawk Eye Challenge", systemImage: "eye")
            }
        } label: {
            if isImportingFootage {
                ProgressView()
            } else {
                Label("Import Video", systemImage: "square.and.arrow.down.on.square")
            }
        }
        .disabled(isImportingFootage)
        .accessibilityLabel("Import video")
    }

    // MARK: - Photo-library import into Footage (wave 1 Phase 4)

    private func handleFootageImport(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isImportingFootage = true
        Task {
            let errorMessage = await FootageImporter.importVideo(
                item, modelContext: modelContext
            )
            isImportingFootage = false
            footageImportItem = nil
            footageImportError = errorMessage
        }
    }
}

// MARK: - Imported video detail (wave 1 Phase 4)

/// Slim detail screen for a photo-library import: playback (thumbnail,
/// tap-to-play), full-match analysis, and rally labeling — all via the shared
/// `GameVideoSection` (restructure PR 1). Highlight actions are hidden
/// (nil closures): imports have no match context for the highlight flow yet.
/// Internal (not private): the home screen's imported-videos section pushes
/// it too (restructure PR 5). Move it out of this file when FootageView dies.
struct ImportedFootageDetailView: View {
    let record: GameVideoRecord

    @State private var analysis = FullMatchAnalysisCoordinator()

    var body: some View {
        List {
            GameVideoSection(
                record: record,
                matchID: nil,
                analysis: analysis,
                playbackStyle: .thumbnail,
                headerText: nil,
                onEditHighlight: nil,
                onShareHighlight: nil
            )
            Section {
            } footer: {
                Text(LocalizationManager.shared.localized("footage.imported.footer"))
            }
        }
        .navigationTitle(LocalizationManager.shared.localized("footage.imported.title"))
        .navigationBarTitleDisplayMode(.inline)
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
