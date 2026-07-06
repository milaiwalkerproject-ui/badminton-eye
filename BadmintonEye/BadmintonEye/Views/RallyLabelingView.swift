// RallyLabelingView.swift
// Wave 1 Phase 1 — in-app "Who won this rally?" labeler.
//
// Presents each rally of one game video (time ranges from the on-device
// TrainingExport JSONL) and collects A / B / Not-a-rally / Skip verdicts as
// `RallyLabel` rows. Verdict button wording is orientation-aware (ADR-0001):
// side_on → left/right players, end_on → near/far players. Skip writes
// nothing (the python contract: absence == unlabeled).
//
// Export (toolbar): renders ALL stored labels + known orientations into
// annotations_human_holdout.jsonl (+ orientation.json) and hands them to the
// share sheet — the file the owner sends back to the training flywheel.

import SwiftUI
import SwiftData
import AVKit

struct RallyLabelingView: View {
    let record: GameVideoRecord
    let matchID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var localization = LocalizationManager.shared

    @State private var items: [RallyLabelQueueItem] = []
    @State private var labeledIDs: Set<Int> = []
    @State private var currentIndex: Int = 0
    @State private var player: AVPlayer?
    @State private var orientation: VideoOrientation?
    @State private var shareURLs: ShareURLs?
    @State private var loaded = false

    private struct ShareURLs: Identifiable {
        let urls: [URL]
        var id: String { urls.map(\.path).joined() }
    }

    var body: some View {
        Group {
            if !loaded {
                ProgressView()
            } else if orientation == nil {
                orientationPrompt
            } else if items.isEmpty {
                emptyState
            } else if currentIndex >= items.count {
                doneState
            } else {
                labelingBody
            }
        }
        .navigationTitle(localized("labeling.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportLabels()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(localized("labeling.export"))
            }
        }
        .sheet(item: $shareURLs) { wrapper in
            ActivityShareSheet(items: wrapper.urls)
        }
        .task { loadIfNeeded() }
        .onDisappear { player?.pause() }
    }

    // MARK: - Orientation prompt (asked once per video)

    private var orientationPrompt: some View {
        VStack(spacing: BE.Space.l) {
            Spacer()
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(localized("labeling.orientation.question"))
                .font(BE.displayTitle)
                .multilineTextAlignment(.center)
            Text(localized("labeling.orientation.explainer"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            orientationButton(.sideOn,
                              title: localized("labeling.orientation.sideOn"),
                              detail: localized("labeling.orientation.sideOn.detail"),
                              icon: "arrow.left.and.right")
            orientationButton(.endOn,
                              title: localized("labeling.orientation.endOn"),
                              detail: localized("labeling.orientation.endOn.detail"),
                              icon: "arrow.up.and.down")
            Spacer()
        }
        .padding(.horizontal, BE.Space.l)
    }

    private func orientationButton(_ value: VideoOrientation,
                                   title: String, detail: String, icon: String) -> some View {
        Button {
            record.orientation = value
            try? modelContext.save()
            withAnimation(BE.ease) { orientation = value }
            playCurrent()
        } label: {
            HStack(spacing: BE.Space.m) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(BE.Space.m)
            .background(BE.card(16).fill(Color(.secondarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Labeling

    private var labelingBody: some View {
        VStack(spacing: BE.Space.m) {
            if let player {
                VideoPlayer(player: player)
                    .frame(maxHeight: 300)
                    .clipShape(BE.card(16))
            }

            HStack {
                Text(String(format: localized("labeling.progress"),
                            currentIndex + 1, items.count))
                    .font(BE.eyebrow)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    playCurrent()
                } label: {
                    Label(localized("labeling.replay"), systemImage: "arrow.counterclockwise")
                        .font(.subheadline)
                }
            }

            Text(localized("labeling.whoWon"))
                .font(BE.displayTitle)

            HStack(spacing: BE.Space.m) {
                verdictButton(.sideA,
                              title: localized(orientation == .endOn
                                               ? "labeling.nearWon" : "labeling.leftWon"),
                              gradient: BE.TeamA.gradient)
                verdictButton(.sideB,
                              title: localized(orientation == .endOn
                                               ? "labeling.farWon" : "labeling.rightWon"),
                              gradient: BE.TeamB.gradient)
            }

            HStack(spacing: BE.Space.m) {
                Button(localized("labeling.notRally")) { applyVerdict(.notRally) }
                    .buttonStyle(.bordered)
                Button(localized("labeling.skip")) { advance() }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(BE.Space.m)
    }

    private func verdictButton(_ verdict: RallyVerdict, title: String,
                               gradient: LinearGradient) -> some View {
        Button {
            applyVerdict(verdict)
        } label: {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(BE.card(16).fill(gradient))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty / done

    private var emptyState: some View {
        ContentUnavailableView(
            localized("labeling.empty.title"),
            systemImage: "figure.badminton",
            description: Text(localized("labeling.empty.detail"))
        )
    }

    private var doneState: some View {
        VStack(spacing: BE.Space.l) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text(localized("labeling.done.title"))
                .font(BE.displayTitle)
            Text(String(format: localized("labeling.done.detail"), labeledIDs.count))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                exportLabels()
            } label: {
                Label(localized("labeling.export"), systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(BE.Space.l)
    }

    // MARK: - Actions

    private func loadIfNeeded() {
        guard !loaded else { return }
        items = RallyLabelExport.queueItems(matchID: matchID, fileName: record.fileName)
        if items.isEmpty {
            // No live-scored rally clips for this video: fall back to rallies
            // segmented from a full-match analysis pass (Phase 3). The id
            // domains never mix per video — see RallySegmenter.queueItems.
            items = RallySegmenter.queueItems(videoStem: record.videoStem)
        }
        orientation = record.orientation
        if let url = record.resolvedURL() {
            player = AVPlayer(url: url)
        }
        // Resume: start after the last already-labeled rally of this video.
        let stem = record.videoStem
        let descriptor = FetchDescriptor<RallyLabel>(
            predicate: #Predicate { $0.videoStem == stem }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        labeledIDs = Set(existing.map(\.rallyID))
        currentIndex = items.firstIndex { !labeledIDs.contains($0.rallyID) } ?? items.count
        loaded = true
        if orientation != nil { playCurrent() }
    }

    private func applyVerdict(_ verdict: RallyVerdict) {
        guard currentIndex < items.count else { return }
        let item = items[currentIndex]
        RallyLabel.upsert(videoStem: record.videoStem, rallyID: item.rallyID,
                          verdict: verdict, orientation: orientation,
                          in: modelContext)
        labeledIDs.insert(item.rallyID)
        advance()
    }

    private func advance() {
        withAnimation(BE.pop) { currentIndex += 1 }
        playCurrent()
    }

    /// Seeks to the current rally (with 2 s of context padding — clip times
    /// are wall-clock approximations) and plays, stopping at the padded end.
    private func playCurrent() {
        guard let player, currentIndex < items.count else { return }
        let item = items[currentIndex]
        let start = max(0, item.startTime - 2)
        let end = item.endTime + 2
        player.pause()
        player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: start, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    private func exportLabels() {
        let all = (try? modelContext.fetch(FetchDescriptor<RallyLabel>())) ?? []
        let labels = all.compactMap { label -> (videoStem: String, rallyID: Int,
                                                verdict: RallyVerdict,
                                                orientation: VideoOrientation?,
                                                labeledAt: Date)? in
            guard let verdict = label.verdict else { return nil }
            return (label.videoStem, label.rallyID, verdict,
                    label.orientationRaw.flatMap(VideoOrientation.init(rawValue:)),
                    label.labeledAt)
        }
        let videos = (try? modelContext.fetch(FetchDescriptor<GameVideoRecord>())) ?? []
        var orientations: [String: VideoOrientation] = [:]
        for video in videos where !video.videoStem.isEmpty {
            if let known = video.orientation { orientations[video.videoStem] = known }
        }
        var urls = RallyLabelExport.writeExportFiles(labels: labels, orientations: orientations)
        guard !urls.isEmpty else { return }
        // Attach trajectories/<stem>.json for labeled videos that have a
        // full-match analysis — labels made against segmented rallies join
        // the flywheel through these files (same rally ids).
        for stem in Set(labels.map(\.videoStem)) {
            let detections = FullMatchAnalysisStore.allDetections(videoStem: stem)
            guard !detections.isEmpty else { continue }
            let rallies = RallySegmenter.detectRallies(detections)
            if let url = RallySegmenter.writeTrajectoriesFile(
                videoStem: stem, orientation: orientations[stem], rallies: rallies) {
                urls.append(url)
            }
        }
        for label in all { label.exported = true }
        try? modelContext.save()
        shareURLs = ShareURLs(urls: urls)
    }

    private func localized(_ key: String) -> String {
        localization.localized(key)
    }
}

// MARK: - Share sheet (same pattern as FootageDetailView)

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
