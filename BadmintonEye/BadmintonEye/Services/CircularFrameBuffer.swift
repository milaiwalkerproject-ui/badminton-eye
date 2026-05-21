@preconcurrency import AVFoundation
import Foundation

/// Ring buffer of CMSampleBuffers that retains the last N seconds of frames.
/// Used by VideoCaptureManager to keep a rolling window for challenge capture.
final class CircularFrameBuffer: @unchecked Sendable {

    // MARK: - Configuration

    /// Maximum duration of buffered frames in seconds.
    let capacity: TimeInterval

    // MARK: - Storage

    private var buffers: [CMSampleBuffer] = []
    private let lock = NSLock()

    // MARK: - Init

    init(capacity: TimeInterval = 10.0) {
        self.capacity = capacity
    }

    // MARK: - Public API

    /// Appends a sample buffer, evicting oldest frames beyond capacity window.
    func append(_ sampleBuffer: CMSampleBuffer) {
        lock.lock()
        defer { lock.unlock() }

        buffers.append(sampleBuffer)
        evictStaleBuffers()
    }

    /// Duration currently stored in the buffer.
    var bufferedDuration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }

        guard let first = buffers.first, let last = buffers.last else { return 0 }
        let start = CMSampleBufferGetPresentationTimeStamp(first)
        let end = CMSampleBufferGetPresentationTimeStamp(last)
        return CMTimeGetSeconds(end) - CMTimeGetSeconds(start)
    }

    /// Whether the buffer contains zero frames.
    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return buffers.isEmpty
    }

    /// Non-destructive snapshot of the most recent `seconds` of frames, oldest
    /// first. Returns an empty array if the buffer is empty. Used by the
    /// rally-suggestion pipeline to pull a recent window for ML inference
    /// without clearing live capture.
    func recentFrames(seconds: TimeInterval) -> [CMSampleBuffer] {
        lock.lock()
        defer { lock.unlock() }

        guard let last = buffers.last else { return [] }
        let newestTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(last))
        let cutoff = newestTime - seconds

        var firstIndex = 0
        for i in 0..<buffers.count {
            let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffers[i]))
            if pts >= cutoff {
                firstIndex = i
                break
            }
            firstIndex = i + 1
        }
        if firstIndex >= buffers.count { return [] }
        return Array(buffers[firstIndex...])
    }

    /// Drops all buffered frames.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffers.removeAll()
    }

    /// Writes all buffered frames to disk as an HEVC .mp4 via AVAssetWriter.
    /// Clears the buffer after a successful flush.
    /// - Parameters:
    ///   - outputURL: File URL for the output .mp4.
    ///   - codec: Video codec (e.g. `.hevc`).
    ///   - width: Output width in pixels.
    ///   - height: Output height in pixels.
    ///   - fps: Expected frames per second (used for writer input settings).
    /// - Returns: The output URL on success.
    func flush(
        to outputURL: URL,
        codec: AVVideoCodecType,
        width: Int,
        height: Int,
        fps: Double
    ) async throws -> URL {
        // Snapshot and clear under lock
        let snapshot = snapshotAndClear()

        guard !snapshot.isEmpty else {
            throw FlushError.emptyBuffer
        }

        // Create writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)

        let outputSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 10_000_000, // 10 Mbps for high-FPS clarity
                AVVideoExpectedSourceFrameRateKey: fps
            ]
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        writerInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )

        guard writer.canAdd(writerInput) else {
            throw FlushError.cannotAddInput
        }
        writer.add(writerInput)

        guard writer.startWriting() else {
            throw FlushError.writerFailed(writer.error)
        }

        let firstPTS = CMSampleBufferGetPresentationTimeStamp(snapshot[0])
        writer.startSession(atSourceTime: firstPTS)

        // Append frames
        for sampleBuffer in snapshot {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            // Wait for input readiness
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 1_000_000) // 1ms
            }

            adaptor.append(pixelBuffer, withPresentationTime: pts)
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        if let error = writer.error {
            throw FlushError.writerFailed(error)
        }

        return outputURL
    }

    // MARK: - Private

    /// Atomically copies all buffered frames and clears the buffer.
    private func snapshotAndClear() -> [CMSampleBuffer] {
        lock.lock()
        defer { lock.unlock() }
        let copy = buffers
        buffers.removeAll()
        return copy
    }

    /// Removes buffers whose PTS is older than (newest PTS - capacity).
    private func evictStaleBuffers() {
        guard let last = buffers.last else { return }
        let newestTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(last))
        let cutoff = newestTime - capacity

        // Find first index within window
        var firstValid = 0
        for i in 0..<buffers.count {
            let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffers[i]))
            if pts >= cutoff {
                firstValid = i
                break
            }
            firstValid = i + 1
        }

        if firstValid > 0 {
            buffers.removeFirst(firstValid)
        }
    }

    // MARK: - Errors

    enum FlushError: Error, LocalizedError {
        case emptyBuffer
        case cannotAddInput
        case writerFailed(Error?)

        var errorDescription: String? {
            switch self {
            case .emptyBuffer:
                return "CircularFrameBuffer is empty — nothing to flush."
            case .cannotAddInput:
                return "AVAssetWriter cannot add video input."
            case .writerFailed(let underlying):
                return "AVAssetWriter failed: \(underlying?.localizedDescription ?? "unknown error")"
            }
        }
    }
}
