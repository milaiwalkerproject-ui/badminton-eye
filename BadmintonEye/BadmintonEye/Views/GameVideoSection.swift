// GameVideoSection.swift
// Restructure PR 1 (RESTRUCTURE-PLAN.md): the reusable per-game-video section,
// extracted verbatim from FootageDetailView so the unified MatchDetailView
// (PR 2) and the imported-video screen can share one implementation.
//
// Capabilities are closure-gated: passing nil for the highlight closures hides
// those rows (imported videos), so the component never owns paywall or share
// state — parents keep it, exactly as FootageDetailView always has.

import SwiftUI
import AVKit
import UIKit

/// One game video's full Section: playback, metadata, highlight actions,
/// rally labeling, and full-match analysis.
struct GameVideoSection: View {

    enum PlaybackStyle {
        /// Inline live AVPlayer (FootageDetailView's original behavior).
        case inlinePlayer
        /// Static thumbnail that swaps to a player on tap — for screens that
        /// show several videos at once and must not instantiate N players.
        case thumbnail
    }

    let record: GameVideoRecord
    /// Owning match for live-recorded footage; nil for imports.
    let matchID: UUID?
    /// Shared analysis driver, owned by the parent screen.
    let analysis: FullMatchAnalysisCoordinator
    var playbackStyle: PlaybackStyle = .inlinePlayer
    /// Section header ("Game 2"); nil renders no header.
    var headerText: String?
    /// Presents the trim/zoom highlight editor. nil hides the row.
    var onEditHighlight: ((GameVideoRecord) -> Void)?
    /// Runs the share-highlight flow (paywall gating stays in the parent).
    /// nil hides the row.
    var onShareHighlight: ((GameVideoRecord) -> Void)?

    var body: some View {
        // Resolve once per render — drives the player/placeholder, the
        // disabled state of the actions, AND the explanatory footer so a
        // grayed row is never left unexplained (no dead taps).
        let recordingAvailable = record.resolvedURL() != nil
        Section {
            playback

            LabeledContent("Score", value: "\(record.scoreA) – \(record.scoreB)")
            LabeledContent("Rallies", value: "\(record.rallyCount)")
            LabeledContent("Duration", value: Self.durationLabel(record.duration))
            if let loc = record.locationName, !loc.isEmpty {
                LabeledContent("Location", value: loc)
            }

            if record.clipRef != nil {
                LabeledContent("Highlight", value: Self.highlightLabel(record))
            }

            if let onEditHighlight {
                // Trim/zoom highlight editor entry point. Lets the user bound
                // a rally segment, preview, save the ClipRef, and export+share
                // the trimmed clip.
                Button {
                    onEditHighlight(record)
                } label: {
                    Label {
                        Text(record.clipRef == nil ? "Create Highlight" : "Edit Highlight")
                    } icon: {
                        Image(systemName: "scissors")
                    }
                }
                .disabled(!recordingAvailable)
                .accessibilityLabel(record.clipRef == nil
                    ? "Create highlight for game \(record.gameNumber)"
                    : "Edit highlight for game \(record.gameNumber)")
            }

            if let onShareHighlight {
                Button {
                    onShareHighlight(record)
                } label: {
                    Label {
                        Text("Share Highlight")
                    } icon: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .disabled(!recordingAvailable)
            }

            // Wave 1 Phase 1: "Who won this rally?" ground-truth labeler.
            NavigationLink {
                RallyLabelingView(record: record, matchID: matchID)
            } label: {
                Label {
                    Text(LocalizationManager.shared.localized("footage.labelRallies"))
                } icon: {
                    Image(systemName: "checkmark.rectangle.stack")
                }
            }
            .disabled(!recordingAvailable)

            analysisRows(recordingAvailable: recordingAvailable)
        } header: {
            if let headerText {
                Text(headerText)
            }
        } footer: {
            if !recordingAvailable {
                Text("Recording unavailable — this game's video file is missing, so highlight actions are disabled.")
            }
        }
    }

    // MARK: - Playback

    @ViewBuilder
    private var playback: some View {
        if let url = record.resolvedURL() {
            switch playbackStyle {
            case .inlinePlayer:
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
            case .thumbnail:
                VideoThumbnailView(url: url)
                    .listRowInsets(EdgeInsets())
            }
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
    }

    // MARK: - Full-match analysis rows (wave 1 Phase 2)

    @ViewBuilder
    private func analysisRows(recordingAvailable: Bool) -> some View {
        if analysis.analyzingStem == record.videoStem, let progress = analysis.progress {
            HStack {
                ProgressView(value: Double(progress.completed),
                             total: Double(max(1, progress.total)))
                Text(String(format: LocalizationManager.shared.localized("footage.analyze.progress"),
                            progress.completed, progress.total))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } else if analysis.doneStem == record.videoStem {
            Label {
                Text(LocalizationManager.shared.localized("footage.analyze.done"))
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        } else {
            Button {
                if let url = record.resolvedURL() {
                    analysis.start(url: url, stem: record.videoStem)
                }
            } label: {
                Label {
                    Text(LocalizationManager.shared.localized("footage.analyze"))
                } icon: {
                    Image(systemName: "waveform.badge.magnifyingglass")
                }
            }
            .disabled(!recordingAvailable || analysis.analyzingStem != nil)
        }
        if let message = analysis.errorMessage, analysis.errorStem == record.videoStem {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Labels

    static func durationLabel(_ s: TimeInterval) -> String {
        guard s > 0 else { return "—" }
        let total = Int(s.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Short "0:05 – 0:18" label for a saved highlight clip.
    static func highlightLabel(_ record: GameVideoRecord) -> String {
        guard let clip = record.clipRef else { return "—" }
        func fmt(_ s: Double) -> String {
            let t = Int(s.rounded())
            return String(format: "%d:%02d", t / 60, t % 60)
        }
        return "\(fmt(clip.startTime)) – \(fmt(clip.endTime))"
    }
}

// MARK: - Video thumbnail (tap-to-play)

/// Static first-look thumbnail that swaps to a live AVPlayer on tap. Screens
/// that list several videos must use this instead of inline players — one
/// AVPlayer per row was measured as a perf trap in the design review.
struct VideoThumbnailView: View {
    let url: URL
    var height: CGFloat = 220

    @State private var thumbnail: UIImage?
    @State private var playing = false

    var body: some View {
        if playing {
            VideoPlayer(player: AVPlayer(url: url))
                .frame(height: height)
        } else {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.black.opacity(0.08)
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 4)
            }
            .contentShape(Rectangle())
            .onTapGesture { playing = true }
            .task(id: url) {
                thumbnail = await Self.generateThumbnail(for: url)
            }
        }
    }

    /// Nonisolated: AVAssetImageGenerator work stays off the main actor; only
    /// the (Sendable) UIImage crosses back.
    static func generateThumbnail(for url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1024, height: 1024)
        guard let cgImage = try? await generator.image(
            at: CMTime(seconds: 1, preferredTimescale: 600)).image
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Full-match analysis coordinator (wave 1 Phase 2)

/// Main-actor state holder driving `FullMatchAnalyzer` for one video at a
/// time. A @MainActor class is implicitly Sendable, so the analyzer's
/// @Sendable progress callback can safely hop back to it — the view struct
/// itself must never be captured across that boundary (Swift 6.1).
/// Lives here because every GameVideoSection consumer needs one.
@MainActor
@Observable
final class FullMatchAnalysisCoordinator {
    private(set) var analyzingStem: String?
    private(set) var progress: (completed: Int, total: Int)?
    private(set) var errorMessage: String?
    private(set) var errorStem: String?
    private(set) var doneStem: String?
    private var task: Task<Void, Never>?

    func start(url: URL, stem: String) {
        guard analyzingStem == nil, !stem.isEmpty else { return }
        analyzingStem = stem
        progress = (0, 1)
        errorMessage = nil
        errorStem = nil
        UIApplication.shared.isIdleTimerDisabled = true

        task = Task {
            let analyzer = FullMatchAnalyzer()
            do {
                try await analyzer.analyze(videoURL: url, videoStem: stem) { completed, total in
                    Task { @MainActor [weak self] in
                        guard let self, self.analyzingStem == stem else { return }
                        self.progress = (completed, total)
                    }
                }
                doneStem = stem
            } catch is CancellationError {
                // Cancelled: completed chunks are persisted; a rerun resumes.
            } catch {
                errorMessage = error.localizedDescription
                errorStem = stem
            }
            UIApplication.shared.isIdleTimerDisabled = false
            analyzingStem = nil
            progress = nil
        }
    }

    func cancel() {
        task?.cancel()
    }
}
