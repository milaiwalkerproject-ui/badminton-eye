import SwiftUI
import SwiftData
import AVKit
import UIKit

/// Per-match footage screen. Shows every `GameVideoRecord` attached to the
/// match in order, with inline playback and metadata, plus a premium-gated
/// "Generate Highlight" action.
///
/// Wiring still required:
/// - `GameVideoRecord` must be registered in the `ModelContainer` and as a
///   relationship on `PersistedMatch.gameVideos`. Until that lands, the
///   record list will be empty and this view shows the empty state.
/// - The Highlight pipeline (trim trash time / zoom / slow-mo / super-rally)
///   is a follow-up. The button currently no-ops for subscribed users and
///   shows the paywall for free users — see TODO(highlight-pipeline).
struct FootageDetailView: View {

    let match: PersistedMatch

    @State private var showPaywall = false
    @State private var pendingRecord: GameVideoRecord?

    /// Record currently being edited in the trim/zoom highlight editor.
    @State private var editingRecord: GameVideoRecord?

    /// Premium entitlement, read directly from the app's `SubscriptionManager`.
    private var isSubscribed: Bool { SubscriptionManager.shared.isPremium }

    private var games: [GameVideoRecord] {
        // Direct relationship access — `PersistedMatch.gameVideos` is now a
        // wired SwiftData @Relationship. (The previous Mirror lookup never
        // resolved the synthesized stored property, so the list was always
        // empty and the screen permanently showed "No game videos".)
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
                        gameSection(for: rec)
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

    // MARK: - Per-game section

    @ViewBuilder
    private func gameSection(for rec: GameVideoRecord) -> some View {
        // Resolve once per render — drives the player/placeholder, the
        // disabled state of both highlight actions, AND the explanatory
        // footer so a grayed row is never left unexplained (no dead taps).
        let recordingAvailable = rec.resolvedURL() != nil
        Section {
            if let url = rec.resolvedURL() {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
            } else {
                ZStack {
                    Color.black.opacity(0.05)
                    VStack(spacing: 6) {
                        Image(systemName: "film.slash")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Recording not available")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 160)
                .listRowInsets(EdgeInsets())
            }

            LabeledContent("Score", value: "\(rec.scoreA) – \(rec.scoreB)")
            LabeledContent("Rallies", value: "\(rec.rallyCount)")
            LabeledContent("Duration", value: durationLabel(rec.duration))
            if let loc = rec.locationName, !loc.isEmpty {
                LabeledContent("Location", value: loc)
            }

            if rec.clipRef != nil {
                LabeledContent("Highlight", value: highlightLabel(rec))
            }

            // Trim/zoom highlight editor entry point. Lets the user bound a
            // rally segment, preview, save the ClipRef, and export+share the
            // trimmed clip.
            Button {
                editingRecord = rec
            } label: {
                Label {
                    Text(rec.clipRef == nil ? "Create Highlight" : "Edit Highlight")
                } icon: {
                    Image(systemName: "scissors")
                }
            }
            .disabled(!recordingAvailable)
            .accessibilityLabel(rec.clipRef == nil
                ? "Create highlight for game \(rec.gameNumber)"
                : "Edit highlight for game \(rec.gameNumber)")

            Button {
                pendingRecord = rec
                if isSubscribed {
                    runHighlightPipeline(for: rec)
                } else {
                    showPaywall = true
                }
            } label: {
                Label {
                    Text("Share Highlight")
                } icon: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            .disabled(!recordingAvailable)
        } header: {
            Text("Game \(rec.gameNumber)")
        } footer: {
            if !recordingAvailable {
                Text("Recording unavailable — this game's video file is missing, so highlight actions are disabled.")
            }
        }
    }

    // MARK: - Helpers

    private func durationLabel(_ s: TimeInterval) -> String {
        guard s > 0 else { return "—" }
        let total = Int(s.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Short "0:05 – 0:18" label for a saved highlight clip.
    private func highlightLabel(_ record: GameVideoRecord) -> String {
        guard let clip = record.clipRef else { return "—" }
        func fmt(_ s: Double) -> String {
            let t = Int(s.rounded())
            return String(format: "%d:%02d", t / 60, t % 60)
        }
        return "\(fmt(clip.startTime)) – \(fmt(clip.endTime))"
    }

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
