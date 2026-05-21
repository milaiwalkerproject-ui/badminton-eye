import SwiftUI
import SwiftData
import AVKit

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

    /// Subscription state. The exact type/name is project-defined; we read
    /// it via `SubscriptionManager.shared.isSubscribed` if it exists. Falls
    /// back to `false` so the paywall always wins on debug builds without
    /// StoreKit configured.
    @State private var isSubscribed: Bool = SubscriptionGate.isSubscribed

    private var games: [GameVideoRecord] {
        // Mirror lookup keeps this view compiling before
        // `PersistedMatch.gameVideos` is added to SwiftDataModels.swift.
        let raw = Mirror(reflecting: match).children
            .first { $0.label == "gameVideos" }?
            .value as? [GameVideoRecord]
        return (raw ?? []).sorted { $0.gameNumber < $1.gameNumber }
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
            // Falls back gracefully if PaywallView doesn't exist on this
            // branch — we just render a placeholder so the build doesn't
            // break before merge.
            PaywallShim()
        }
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
                    Text("Generate Highlight")
                } icon: {
                    Image(systemName: "sparkles")
                }
            }
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

    /// TODO(highlight-pipeline): wire to `HighlightEditor.makeHighlight(...)`.
    /// For now this is a no-op so the UI works end-to-end behind the paywall.
    private func runHighlightPipeline(for record: GameVideoRecord) {
        _ = record
    }
}

// MARK: - Subscription gate (soft binding)

/// Reads `SubscriptionManager.shared.isSubscribed` reflectively so this file
/// compiles even on branches where the StoreKit layer is feature-flagged off
/// (e.g. free-Apple-ID MVP mode). Replace with a direct call once the manager
/// is guaranteed present.
private enum SubscriptionGate {
    static var isSubscribed: Bool {
        // Look up SubscriptionManager.shared via NSClassFromString-style
        // probing. Returns false on any failure — the user just sees the
        // paywall stub, which is the safer default.
        let candidates: [String] = ["BadmintonEye.SubscriptionManager",
                                    "SubscriptionManager"]
        for name in candidates {
            if let cls = NSClassFromString(name) as? NSObject.Type {
                let sharedSel = NSSelectorFromString("shared")
                if cls.responds(to: sharedSel) {
                    let shared = cls.perform(sharedSel)?
                        .takeUnretainedValue() as? NSObject
                    let isSubSel = NSSelectorFromString("isSubscribed")
                    if let shared = shared, shared.responds(to: isSubSel) {
                        let val = shared.perform(isSubSel)?
                            .takeUnretainedValue()
                        if let b = val as? Bool { return b }
                        if let n = val as? NSNumber { return n.boolValue }
                    }
                }
            }
        }
        return false
    }
}

// MARK: - Paywall shim

/// Lightweight stand-in until this branch has a real PaywallView. The real
/// app target ships `PaywallView` (see `Views/PaywallView.swift`); presenting
/// it directly via `PaywallView()` requires its initializer signature, which
/// varies across branches. Keep this shim minimal to avoid coupling.
private struct PaywallShim: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("Premium feature")
                    .font(.title2).bold()
                Text("Auto-generated highlight reels are available with Badminton Eye Premium.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Spacer()
            }
            .padding(.top, 48)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
