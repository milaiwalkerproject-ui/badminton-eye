// FullMatchAnalyzer.swift
// Wave 1 Phase 2 — chunked, resumable, thermal/storage-guarded TrackNet pass
// over a full recorded game video (see .planning/FULLMATCH-PHASE2-SPEC.md).
//
// Design:
//   - Bypasses the live TrackNetWindowAdapter (its stride-4 cache and
//     call-order frame indices are wrong for offline work). Reads the file
//     with AVAssetReader decoding straight to 512×288 BGRA (VideoToolbox does
//     the scaling — no CI preprocessing pass), batches non-overlapping
//     8-frame windows into TrackNetShuttleDetector.detect, and harvests all
//     8 observations per prediction.
//   - Canonical frame index f = round(t × 30), t = sample PTS seconds.
//     Sources above 30 fps map multiple frames to one f; the max-confidence
//     detection per f wins.
//   - One chunk ≈ 30 s of video. Each completed chunk is persisted via
//     FullMatchAnalysisStore BEFORE the next begins, so a kill/interruption
//     loses at most one chunk; analyze() resumes from the store.
//   - Guards: storage precheck; thermal pause between chunks (pause at
//     .serious/.critical, resume at .fair or better).
//   - Windows never span a chunk boundary; a trailing remainder of <8 frames
//     per chunk is dropped (python drops the per-video remainder — at 60 fps
//     this costs ≤0.12 s per 30 s chunk, acceptable for v1).
//
// Swift 6.1: AVAssetReader/CMSampleBuffer are non-Sendable — everything
// AV-typed stays confined inside analyzeChunk; only Sendable values escape.

@preconcurrency import AVFoundation
import Foundation

final class FullMatchAnalyzer: @unchecked Sendable {

    struct Config: Sendable {
        var chunkSeconds: Double = 30
        var minFreeBytes: Int64 = 500_000_000
        var canonicalFPS: Double = 30
    }

    enum AnalysisError: LocalizedError {
        case videoUnreadable
        case insufficientStorage

        var errorDescription: String? {
            switch self {
            case .videoUnreadable: return "The video file could not be read."
            case .insufficientStorage: return "Not enough free storage to analyze."
            }
        }
    }

    private let config: Config
    private let detector = TrackNetShuttleDetector()

    init(config: Config = Config()) {
        self.config = config
    }

    /// Runs (or resumes) the full analysis of one game video. Progress is
    /// reported as (completedChunks, totalChunks) after every chunk.
    /// Cancellation (Task.cancel) stops cleanly between chunks; completed
    /// chunks stay persisted.
    func analyze(videoURL: URL, videoStem: String,
                 onProgress: @escaping @Sendable (Int, Int) -> Void) async throws {
        guard !videoStem.isEmpty else { throw AnalysisError.videoUnreadable }
        try checkStorage()

        let asset = AVURLAsset(url: videoURL)
        let duration = try await CMTimeGetSeconds(asset.load(.duration))
        guard duration.isFinite, duration > 0 else { throw AnalysisError.videoUnreadable }

        let totalChunks = max(1, Int(ceil(duration / config.chunkSeconds)))
        var completed = FullMatchAnalysisStore.contiguousCompletedChunks(
            FullMatchAnalysisStore.chunks(videoStem: videoStem))
        onProgress(min(completed, totalChunks), totalChunks)

        while completed < totalChunks {
            try Task.checkCancellation()
            await waitWhileThermallyConstrained()

            let start = Double(completed) * config.chunkSeconds
            let length = min(config.chunkSeconds, duration - start)
            let detections = try await analyzeChunk(
                url: videoURL, startSeconds: start, lengthSeconds: length)

            let fStart = Int((start * config.canonicalFPS).rounded())
            let fEnd = Int(((start + length) * config.canonicalFPS).rounded()) - 1
            FullMatchAnalysisStore.append(
                AnalyzedChunk(chunk: completed, fStart: fStart,
                              fEnd: max(fStart, fEnd), detections: detections),
                videoStem: videoStem)

            completed += 1
            onProgress(completed, totalChunks)
        }
    }

    // MARK: - One chunk (all AV types confined here)

    private func analyzeChunk(url: URL, startSeconds: Double,
                              lengthSeconds: Double) async throws -> [AnalyzedDetection] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset)
        else { throw AnalysisError.videoUnreadable }

        // Decode directly to the model's input size — VideoToolbox scales.
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: TrackNetConstants.inputWidth,
            kCVPixelBufferHeightKey as String: TrackNetConstants.inputHeight,
        ])
        // Copy sample data: the window retains up to 8 buffers (plus the
        // background for the whole chunk), and holding decoder-pool buffers
        // that long risks stalling the pool. At 512×288 BGRA a copy is cheap.
        output.alwaysCopiesSampleData = true
        guard reader.canAdd(output) else { throw AnalysisError.videoUnreadable }
        reader.add(output)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: startSeconds, preferredTimescale: 600),
            duration: CMTime(seconds: lengthSeconds, preferredTimescale: 600))
        guard reader.startReading() else { throw AnalysisError.videoUnreadable }
        defer { reader.cancelReading() }

        // Best detection per canonical frame index (max confidence wins).
        var best: [Int: AnalyzedDetection] = [:]
        var window: [(buffer: CVPixelBuffer, f: Int)] = []
        var background: CVPixelBuffer?

        func flushWindow() async throws {
            guard window.count == TrackNetConstants.frameWindow,
                  let background else { return }
            let observations = try await detector.detect(
                frames: window.map(\.buffer), background: background)
            for observation in observations {
                guard observation.windowFrameIndex < window.count else { continue }
                let f = window[observation.windowFrameIndex].f
                let detection: AnalyzedDetection
                if let position = observation.position {
                    detection = AnalyzedDetection(
                        f: f, x: Double(position.x), y: Double(position.y),
                        conf: Double(observation.confidence), vis: true)
                } else {
                    detection = AnalyzedDetection(
                        f: f, x: 0, y: 0,
                        conf: Double(observation.confidence), vis: false)
                }
                if let existing = best[f] {
                    best[f] = Self.better(existing, detection)
                } else {
                    best[f] = detection
                }
            }
            window.removeAll(keepingCapacity: true)
        }

        while let sampleBuffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
            let t = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            guard t.isFinite else { continue }
            // Footage recordings start their timeline at ~0 (FootageWriter's
            // startSession(atSourceTime:)); imported videos revisit in Phase 4.
            let f = Int((t * config.canonicalFPS).rounded())

            if background == nil { background = pixelBuffer }   // v0 stand-in, TODO(bg-median)
            window.append((pixelBuffer, f))
            if window.count == TrackNetConstants.frameWindow {
                try await flushWindow()
            }
        }
        // Trailing <8-frame remainder intentionally dropped (see header).

        return best.values.sorted { $0.f < $1.f }
    }

    /// Max-confidence dedupe for multiple frames mapping to one canonical f;
    /// a visible detection always beats an invisible one.
    static func better(_ a: AnalyzedDetection, _ b: AnalyzedDetection) -> AnalyzedDetection {
        if a.vis != b.vis { return a.vis ? a : b }
        return a.conf >= b.conf ? a : b
    }

    // MARK: - Guards

    private func checkStorage() throws {
        guard let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let values = try? support.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let free = values.volumeAvailableCapacityForImportantUsage
        else { return }   // unknown capacity: proceed rather than block
        if free < config.minFreeBytes { throw AnalysisError.insufficientStorage }
    }

    /// Pauses between chunks while the device is thermally constrained:
    /// stops at .serious or worse, resumes at .fair or better.
    private func waitWhileThermallyConstrained() async {
        while ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled { return }
        }
    }
}
