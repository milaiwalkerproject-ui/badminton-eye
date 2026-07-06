import SwiftUI
import SwiftData
import PhotosUI
import AVKit

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
                // Resolved outside the picker label: PhotosPicker's label
                // closure is nonisolated in the iOS 18.5 SDK, so it can't
                // touch the main-actor LocalizationManager directly.
                let importToFootageTitle = LocalizationManager.shared.localized("footage.importToFootage")
                Menu {
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

    // MARK: - Photo-library import into Footage (wave 1 Phase 4)

    private func handleFootageImport(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isImportingFootage = true
        _ = item.loadTransferable(type: ImportedVideo.self) { result in
            Task { @MainActor in
                defer {
                    isImportingFootage = false
                    footageImportItem = nil
                }
                do {
                    guard let video = try result.get() else {
                        throw VideoImportError.unsupportedItem
                    }
                    try ImportedVideo.validate(url: video.url)
                    let record = try GameVideoRecord.makeImported(copyingFrom: video.url)
                    modelContext.insert(record)
                    try? modelContext.save()
                    try? FileManager.default.removeItem(at: video.url)
                } catch {
                    footageImportError = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Imported video detail (wave 1 Phase 4)

/// Slim detail screen for a photo-library import: playback (thumbnail,
/// tap-to-play), full-match analysis, and rally labeling — all via the shared
/// `GameVideoSection` (restructure PR 1). Highlight actions are hidden
/// (nil closures): imports have no match context for the highlight flow yet.
private struct ImportedFootageDetailView: View {
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
