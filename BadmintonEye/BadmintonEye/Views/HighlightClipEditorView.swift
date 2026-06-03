import SwiftUI
import SwiftData
import AVKit
import AVFoundation
import UIKit

/// Trim / zoom highlight editor for a single recorded game video.
///
/// A "highlight" here is a `ClipRef` — a time-range OFFSET (start/end seconds)
/// into the already-recorded per-game video referenced by `GameVideoRecord`,
/// NOT a separate clip file. The editor lets the user:
///   - scrub the game video,
///   - drag trim in/out handles to bound a rally segment,
///   - optionally zoom the preview to inspect the action,
///   - preview the trimmed range, and
///   - save the `ClipRef` to the model and/or export+share the trimmed segment.
///
/// UI/UX rules applied (iOS subset):
///   - SF Symbols only; every icon-only control has an `.accessibilityLabel`.
///   - Controls are native `Button`/`Slider`; touch targets ≥ 44×44pt, ≥ 8pt
///     apart; visible press feedback via system button styling.
///   - Semantic colors (`.primary`/`.secondary`/`.tint`/`Color(.systemBackground)`),
///     so light & dark mode both work; color is never the only signal (handles
///     carry SF Symbols + text time labels).
///   - Dynamic Type via semantic `.font` text styles; ≥ 16pt body.
///   - 8pt spacing rhythm via `BE.Space`; respects safe areas.
///   - Animations 150–300ms, transform/opacity only, honor Reduce Motion.
struct HighlightClipEditorView: View {

    // MARK: - Inputs

    let record: GameVideoRecord

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - State

    @State private var player = AVPlayer()
    @State private var assetDuration: Double = 0
    @State private var loadFailed = false

    /// Trim in/out, in seconds. Kept valid via `ClipRef.clamped`.
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 0

    /// Preview zoom (1.0 = fit). Transform-only, so it honors Reduce Motion.
    @State private var zoom: Double = 1.0

    @State private var isExporting = false
    @State private var exportError: String?
    @State private var shareItem: ShareItem?
    @State private var didSaveConfirmation = false

    private struct ShareItem: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    private static let minZoom: Double = 1.0
    private static let maxZoom: Double = 3.0

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if loadFailed {
                    unavailableState
                } else {
                    editor
                }
            }
            .navigationTitle("Highlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveClip() }
                        .disabled(loadFailed || !isTrimValid)
                }
            }
            .task { await loadAsset() }
            .onDisappear { player.pause() }
            .alert(
                "Export Failed",
                isPresented: Binding(
                    get: { exportError != nil },
                    set: { if !$0 { exportError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
            }
        }
    }

    // MARK: - Editor body

    private var editor: some View {
        VStack(spacing: BE.Space.m) {
            preview
            trimControls
            zoomControls
            actionRow
            Spacer(minLength: 0)
        }
        .padding(BE.Space.m)
    }

    // MARK: - Preview

    private var preview: some View {
        VideoPlayer(player: player)
            .scaleEffect(zoom)
            .frame(maxWidth: .infinity)
            .frame(height: 240)
            .clipped()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.2),
                value: zoom
            )
            .accessibilityLabel("Highlight preview")
            .accessibilityValue("Zoom \(String(format: "%.1f", zoom)) times")
    }

    // MARK: - Trim controls

    private var trimControls: some View {
        VStack(alignment: .leading, spacing: BE.Space.s) {
            HStack {
                Label("In", systemImage: "arrow.right.to.line")
                    .font(.subheadline)
                Spacer()
                Text(timeLabel(trimStart))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Trim in point")
            .accessibilityValue(timeLabel(trimStart))

            Slider(
                value: Binding(
                    get: { trimStart },
                    set: { setTrim(start: $0, end: trimEnd) }
                ),
                in: 0...max(assetDuration, ClipRef.minimumDuration)
            ) {
                Text("Trim in")
            }
            .tint(.accentColor)

            HStack {
                Label("Out", systemImage: "arrow.left.to.line")
                    .font(.subheadline)
                Spacer()
                Text(timeLabel(trimEnd))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Trim out point")
            .accessibilityValue(timeLabel(trimEnd))

            Slider(
                value: Binding(
                    get: { trimEnd },
                    set: { setTrim(start: trimStart, end: $0) }
                ),
                in: 0...max(assetDuration, ClipRef.minimumDuration)
            ) {
                Text("Trim out")
            }
            .tint(.accentColor)

            Text("Clip length \(timeLabel(trimEnd - trimStart))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Zoom controls

    private var zoomControls: some View {
        HStack(spacing: BE.Space.m) {
            Button {
                stepZoom(-0.25)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(zoom <= Self.minZoom + 0.001)
            .accessibilityLabel("Zoom out")

            Slider(value: $zoom, in: Self.minZoom...Self.maxZoom) {
                Text("Zoom")
            }
            .tint(.accentColor)
            .accessibilityLabel("Preview zoom")
            .accessibilityValue("\(String(format: "%.1f", zoom)) times")

            Button {
                stepZoom(0.25)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(zoom >= Self.maxZoom - 0.001)
            .accessibilityLabel("Zoom in")
        }
    }

    // MARK: - Actions

    private var actionRow: some View {
        VStack(spacing: BE.Space.s) {
            Button {
                previewTrimmedRange()
            } label: {
                Label("Preview Clip", systemImage: "play.circle")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(!isTrimValid)

            Button {
                exportAndShare()
            } label: {
                if isExporting {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Label("Export & Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isTrimValid || isExporting)
            .accessibilityLabel("Export and share highlight")

            if didSaveConfirmation {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Unavailable state

    private var unavailableState: some View {
        ContentUnavailableView {
            Label("Recording unavailable", systemImage: "film.slash")
        } description: {
            Text("This game video could not be loaded, so it can’t be edited.")
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Derived

    private var isTrimValid: Bool {
        currentClip() != nil
    }

    /// Builds a clamped `ClipRef` for the current trim in/out, or `nil` if the
    /// range is not valid for this video.
    private func currentClip() -> ClipRef? {
        ClipRef.clamped(
            fileName: record.fileName,
            start: trimStart,
            end: trimEnd,
            duration: assetDuration > 0 ? assetDuration : nil
        )
    }

    // MARK: - Loading

    @MainActor
    private func loadAsset() async {
        guard let url = record.resolvedURL() else {
            loadFailed = true
            return
        }
        let asset = AVURLAsset(url: url)
        do {
            let cmDuration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(cmDuration)
            guard seconds.isFinite, seconds > 0 else {
                loadFailed = true
                return
            }
            assetDuration = seconds

            // Seed trim from a saved clip if present, else the whole video,
            // always routed through the clamping path.
            let seedStart = record.clipRef?.startTime ?? 0
            let seedEnd = record.clipRef?.endTime ?? seconds
            if let seed = ClipRef.clamped(
                fileName: record.fileName, start: seedStart, end: seedEnd, duration: seconds
            ) {
                trimStart = seed.startTime
                trimEnd = seed.endTime
            } else {
                trimStart = 0
                trimEnd = seconds
            }

            player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
            await seek(to: trimStart)
        } catch {
            loadFailed = true
        }
    }

    // MARK: - Trim mutation (single clamping path)

    private func setTrim(start: Double, end: Double) {
        guard let clip = ClipRef.clamped(
            fileName: record.fileName,
            start: start,
            end: end,
            duration: assetDuration > 0 ? assetDuration : nil
        ) else { return }
        trimStart = clip.startTime
        trimEnd = clip.endTime
        didSaveConfirmation = false
        Task { await seek(to: clip.startTime) }
    }

    private func stepZoom(_ delta: Double) {
        zoom = min(Self.maxZoom, max(Self.minZoom, zoom + delta))
    }

    @MainActor
    private func seek(to seconds: Double) async {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func previewTrimmedRange() {
        Task { @MainActor in
            await seek(to: trimStart)
            player.play()
            // Stop at the out point.
            let endTime = CMTime(seconds: trimEnd, preferredTimescale: 600)
            player.currentItem?.forwardPlaybackEndTime = endTime
        }
    }

    // MARK: - Persistence

    private func saveClip() {
        guard let clip = currentClip() else { return }
        record.setClip(clip)
        try? modelContext.save()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            didSaveConfirmation = true
        }
    }

    // MARK: - Export

    private func exportAndShare() {
        guard let url = record.resolvedURL(),
              let clip = currentClip()
        else { return }

        // Persist the clip alongside the export so the two stay in sync.
        record.setClip(clip)
        try? modelContext.save()

        isExporting = true
        Task {
            do {
                let outURL = try await HighlightExporter.exportTrimmed(
                    sourceURL: url, clip: clip
                )
                await MainActor.run {
                    isExporting = false
                    shareItem = ShareItem(url: outURL)
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportError = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Helpers

    private func timeLabel(_ seconds: Double) -> String {
        let s = max(0, seconds)
        let whole = Int(s)
        let frac = Int((s - Double(whole)) * 10)
        return String(format: "%d:%02d.%d", whole / 60, whole % 60, frac)
    }
}

// MARK: - Exporter

/// Trims a time-range out of a source video into a new temporary file using
/// `AVAssetExportSession`. The result is suitable for the system share sheet
/// (Save to Files, AirDrop, Messages, …) — the same export/share path used by
/// the footage pipeline, now bounded to the highlight `ClipRef`.
enum HighlightExporter {

    enum ExportError: LocalizedError {
        case noCompatiblePreset
        case sessionCreationFailed
        case exportFailed(String)

        var errorDescription: String? {
            switch self {
            case .noCompatiblePreset:
                return "No compatible export preset for this video."
            case .sessionCreationFailed:
                return "Could not start the export session."
            case .exportFailed(let reason):
                return "The highlight could not be exported. \(reason)"
            }
        }
    }

    static func exportTrimmed(sourceURL: URL, clip: ClipRef) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)

        let presets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let preset = presets.contains(AVAssetExportPresetHighestQuality)
            ? AVAssetExportPresetHighestQuality
            : (presets.first ?? AVAssetExportPresetPassthrough)
        guard !presets.isEmpty else { throw ExportError.noCompatiblePreset }

        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ExportError.sessionCreationFailed
        }

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("highlight-\(UUID().uuidString).mp4")

        let start = CMTime(seconds: clip.startTime, preferredTimescale: 600)
        let durationCM = CMTime(seconds: clip.duration, preferredTimescale: 600)
        let range = CMTimeRange(start: start, duration: durationCM)

        session.outputURL = outURL
        session.outputFileType = .mp4
        session.timeRange = range
        session.shouldOptimizeForNetworkUse = true

        await session.export()

        switch session.status {
        case .completed:
            return outURL
        case .cancelled:
            throw ExportError.exportFailed("Export was cancelled.")
        default:
            let reason = session.error?.localizedDescription ?? "Unknown error."
            throw ExportError.exportFailed(reason)
        }
    }
}

// MARK: - Share sheet

/// Thin `UIActivityViewController` wrapper for sharing/exporting the trimmed
/// highlight (Save to Files, AirDrop, Messages, …).
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
