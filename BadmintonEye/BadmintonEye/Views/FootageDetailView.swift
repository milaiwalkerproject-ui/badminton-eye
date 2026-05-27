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
            .disabled(rec.resolvedURL() == nil)
        } header: {
            Text("Game \(rec.gameNumber)")
        }
    }

    // MARK: - Helpers

    private func durationLabel(_ s: TimeInterval) -> String {
        guard s > 0 else { return "—" }
        let total = Int(s.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Produces a shareable highlight for the game. The full
    /// trim/zoom/slow-mo/super-rally editor is a follow-up; for now this
    /// surfaces the recorded game video through the system share sheet so the
    /// action is actually functional (it previously no-op'd, which is what made
    /// the feature feel broken). No-op if the file is missing.
    private func runHighlightPipeline(for record: GameVideoRecord) {
        guard let url = record.resolvedURL() else { return }
        shareURL = ShareURL(url: url)
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
