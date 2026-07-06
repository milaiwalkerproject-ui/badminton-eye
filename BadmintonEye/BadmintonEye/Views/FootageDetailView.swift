import SwiftUI
import SwiftData
import AVKit
import UIKit

/// Per-match footage screen. Shows every `GameVideoRecord` attached to the
/// match in order, with inline playback and metadata, plus a premium-gated
/// "Share Highlight" action.
///
/// Restructure PR 1: the per-game section body lives in the reusable
/// `GameVideoSection` (shared with the imported-video screen and, next, the
/// unified MatchDetailView). This view keeps ONLY the parent-owned state:
/// paywall gating, the highlight editor sheet, and the share flow.
struct FootageDetailView: View {

    let match: PersistedMatch

    @State private var showPaywall = false
    @State private var pendingRecord: GameVideoRecord?

    /// Record currently being edited in the trim/zoom highlight editor.
    @State private var editingRecord: GameVideoRecord?

    // Full-match analysis (wave 1 Phase 2): one video at a time, progress is
    // session-local; completed chunks persist in FullMatchAnalysisStore and
    // a rerun resumes where it stopped.
    @State private var analysis = FullMatchAnalysisCoordinator()

    /// Premium entitlement, read directly from the app's `SubscriptionManager`.
    private var isSubscribed: Bool { SubscriptionManager.shared.isPremium }

    private var games: [GameVideoRecord] {
        // Direct relationship access — `PersistedMatch.gameVideos` is a wired
        // SwiftData @Relationship.
        (match.gameVideos ?? []).sorted { $0.gameNumber < $1.gameNumber }
    }

    var body: some View {
        Group {
            if games.isEmpty {
                ContentUnavailableView {
                    Label("No game videos", systemImage: "film")
                } description: {
                    Text("This match has no recorded game footage. Future matches will record each game automatically.")
                        .multilineTextAlignment(.center)
                }
            } else {
                List {
                    ForEach(games) { rec in
                        GameVideoSection(
                            record: rec,
                            matchID: match.id,
                            analysis: analysis,
                            playbackStyle: .inlinePlayer,
                            headerText: "Game \(rec.gameNumber)",
                            onEditHighlight: { editingRecord = $0 },
                            onShareHighlight: { record in
                                pendingRecord = record
                                if isSubscribed {
                                    runHighlightPipeline(for: record)
                                } else {
                                    showPaywall = true
                                }
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle("Match Footage")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(item: $shareURL) { wrapper in
            ShareSheet(items: [wrapper.url])
        }
        .sheet(item: $editingRecord) { rec in
            HighlightClipEditorView(record: rec)
        }
    }

    /// URL of a game video queued for sharing (the "highlight" export). Wrapped
    /// so it's `Identifiable` for `.sheet(item:)`.
    @State private var shareURL: ShareURL?

    private struct ShareURL: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    // MARK: - Highlight share flow

    /// Produces a shareable highlight for the game. If a `ClipRef` has been
    /// saved via the trim/zoom editor, the trimmed segment is exported and
    /// shared; otherwise the whole game video is shared (so the action stays
    /// functional even before a highlight is created). No-op if the file is
    /// missing.
    private func runHighlightPipeline(for record: GameVideoRecord) {
        guard let url = record.resolvedURL() else { return }
        guard let clip = record.clipRef else {
            shareURL = ShareURL(url: url)
            return
        }
        Task {
            if let outURL = try? await HighlightExporter.exportTrimmed(
                sourceURL: url, clip: clip
            ) {
                await MainActor.run { shareURL = ShareURL(url: outURL) }
            } else {
                // Fall back to the full video if export fails.
                await MainActor.run { shareURL = ShareURL(url: url) }
            }
        }
    }
}

// MARK: - Share sheet

/// Thin `UIActivityViewController` wrapper for sharing/exporting a recorded
/// game video (Save to Files, AirDrop, Messages, etc.).
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
