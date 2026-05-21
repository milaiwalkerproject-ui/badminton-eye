import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

// MARK: - TrackNetWindowAdapter

/// Adapts the windowed `TrackNetShuttleDetector` (which consumes 8 frames at
/// a time and emits 8 observations) to the per-frame `ShuttleDetecting`
/// contract that `TrajectoryRallySuggestor` already understands.
///
/// Behaviour summary:
/// - Maintains an internal FIFO rolling window of size 8 of recent
///   `CVPixelBuffer`s plus a monotonically-increasing global frame index.
/// - During warm-up (fewer than 8 frames seen) every call returns `[]`. The
///   suggestor tolerates empty per-call results — its coin-flip fallback
///   kicks in only if the *total* detections across the whole suggestion
///   window stays below 2.
/// - Once warm, inference is triggered at most once per `inferenceStride`
///   (= 4) new frames. Stride of 4 means each window of 8 has ~50% overlap
///   with its predecessor — empirically a good tradeoff between freshness
///   and ML budget (8× call rate / 4 = 2× inference rate vs naive).
/// - In-between inferences, the cached 8-observation window is reused and
///   the entry corresponding to the current frame is returned.
///
/// The adapter is `@unchecked Sendable` because mutation of its rolling
/// window + cache is serialised by an `NSLock`, mirroring the style of
/// `CoreMLShuttleDetector`.
final class TrackNetWindowAdapter: ShuttleDetecting, @unchecked Sendable {

    // MARK: - Tunables

    /// Re-run inference once the window has advanced this many frames since
    /// the last inference. 4 means ~50% temporal overlap between consecutive
    /// 8-frame windows.
    private let inferenceStride: Int = 4

    // MARK: - Dependencies

    private let underlying = TrackNetShuttleDetector()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - State (guarded by `lock`)

    private let lock = NSLock()
    private var window: [CVPixelBuffer] = []
    /// Global index of the most recently enqueued frame (monotonic).
    private var currentFrameIndex: Int = -1
    /// Global index at which the cached observations were produced.
    private var lastInferenceFrameIndex: Int = Int.min
    /// Cached 8 observations from the last successful inference, aligned to
    /// the window that ended at `lastInferenceFrameIndex`.
    private var cached: [TrackNetWindowObservation] = []

    /// Reusable buffer pool for the 288x512 RGB preprocessed frames. Saves
    /// allocations across the hot loop.
    private var bufferPool: CVPixelBufferPool?

    // MARK: - ShuttleDetecting

    let modelName: String = "TrackNetV3"

    func detect(in pixelBuffer: CVPixelBuffer) async throws -> [ShuttleObservation] {
        // 1) Enqueue and snapshot what we need for inference.
        let snapshot = enqueueAndSnapshot(pixelBuffer)

        // Warm-up: not enough frames yet.
        guard snapshot.windowReady else { return [] }

        // 2) If cache is fresh enough, reuse it.
        if let obs = snapshot.cachedObservation {
            return obs.map { [$0] } ?? []
        }

        // 3) Preprocess all 8 frames + background, then run inference.
        let preprocessedFrames = try snapshot.frames.map { try preprocess($0) }
        // TODO(bg-median): replace with a median blend across the 8 frames
        // for cleaner backgrounds. Oldest-frame is the cheap stand-in.
        let background = try preprocess(snapshot.frames[0])

        let results = try await underlying.detect(
            frames: preprocessedFrames,
            background: background
        )

        // 4) Cache the result keyed to the index of the most-recent frame
        //    in the window we just ran on.
        storeCache(results, at: snapshot.frameIndex)

        // 5) Surface the observation for the current (most-recent) frame
        //    — windowFrameIndex 7 corresponds to the latest input.
        return observationsForCurrentFrame(
            from: results,
            currentIndex: snapshot.frameIndex
        )
    }

    /// Placeholder/simulation path is not supported by a real ML detector.
    /// Returning `[]` keeps callers that exercise the simulation path from
    /// crashing — the suggestor's coin-flip fallback will activate.
    func detect(imageSize: CGSize, frameCount: Int) async throws -> [ShuttleObservation] {
        return []
    }

    // MARK: - Window management

    private struct EnqueueSnapshot {
        let frames: [CVPixelBuffer]
        let frameIndex: Int
        let windowReady: Bool
        /// `.some(nil)` = cache hit but the latest slot has no detection.
        /// `.some(.some(...))` = cache hit with a detection.
        /// `nil` = cache miss, need to run inference.
        let cachedObservation: ShuttleObservation??
    }

    private func enqueueAndSnapshot(_ pb: CVPixelBuffer) -> EnqueueSnapshot {
        lock.lock()
        defer { lock.unlock() }

        window.append(pb)
        if window.count > TrackNetConstants.frameWindow {
            window.removeFirst(window.count - TrackNetConstants.frameWindow)
        }
        currentFrameIndex &+= 1

        let ready = window.count == TrackNetConstants.frameWindow
        guard ready else {
            return EnqueueSnapshot(
                frames: [],
                frameIndex: currentFrameIndex,
                windowReady: false,
                cachedObservation: nil
            )
        }

        // Cache reuse check: only re-run when we have moved on by at least
        // `inferenceStride` frames since the last inference.
        let framesSinceInference = currentFrameIndex - lastInferenceFrameIndex
        if framesSinceInference < inferenceStride && !cached.isEmpty {
            let obs = cachedObservation(forGlobalIndex: currentFrameIndex)
            return EnqueueSnapshot(
                frames: window,
                frameIndex: currentFrameIndex,
                windowReady: true,
                cachedObservation: .some(obs)
            )
        }

        // Cache miss → caller must run inference.
        return EnqueueSnapshot(
            frames: window,
            frameIndex: currentFrameIndex,
            windowReady: true,
            cachedObservation: nil
        )
    }

    private func storeCache(_ results: [TrackNetWindowObservation], at frameIndex: Int) {
        lock.lock()
        defer { lock.unlock() }
        cached = results
        lastInferenceFrameIndex = frameIndex
    }

    /// Map the cached 8-observation window onto the global frame index.
    /// `lastInferenceFrameIndex` corresponds to `windowFrameIndex == 7`
    /// (the newest input frame). Older entries map backwards.
    private func cachedObservation(forGlobalIndex globalIndex: Int) -> ShuttleObservation? {
        let offsetFromNewest = lastInferenceFrameIndex - globalIndex // 0...7
        guard offsetFromNewest >= 0,
              offsetFromNewest < TrackNetConstants.frameWindow else {
            // Out of cache range — best-effort: hand back the newest slot.
            return observation(from: cached.last, globalIndex: globalIndex)
        }
        let windowIdx = (TrackNetConstants.frameWindow - 1) - offsetFromNewest
        return observation(from: cached[windowIdx], globalIndex: globalIndex)
    }

    private func observationsForCurrentFrame(
        from results: [TrackNetWindowObservation],
        currentIndex: Int
    ) -> [ShuttleObservation] {
        // The latest frame is windowFrameIndex == 7 right after inference.
        guard let newest = results.last,
              let obs = observation(from: newest, globalIndex: currentIndex) else {
            return []
        }
        return [obs]
    }

    private func observation(
        from windowed: TrackNetWindowObservation?,
        globalIndex: Int
    ) -> ShuttleObservation? {
        guard let windowed, let position = windowed.position else { return nil }
        // TrackNet's heatmap argmax already lands in normalized [0,1] image
        // coordinates (see `TrackNetShuttleDetector.argmaxPerFrame`), so we
        // pass them through unchanged — the suggestor multiplies by
        // imageWidth/Height itself. The clamp on confidence keeps values in
        // the protocol's documented [0,1] range; the model produces sigmoid
        // peaks which are already in that range, but a clamp is cheap
        // insurance.
        let confidence = max(0, min(1, windowed.confidence))
        return ShuttleObservation(
            position: position,
            confidence: confidence,
            frameIndex: globalIndex
        )
    }

    // MARK: - Preprocessing

    /// Render the input pixel buffer into a 288x512 BGRA buffer that
    /// `TrackNetShuttleDetector.writeRGB` can consume. We go through
    /// `CIContext.render(_:to:)` because (a) it handles arbitrary source
    /// formats (BGRA, 420f, etc.), (b) it stays on-GPU when possible, and
    /// (c) it matches the rendering path already used inside the underlying
    /// detector. A reusable `CVPixelBufferPool` minimises allocations in
    /// the suggestion hot loop.
    private func preprocess(_ source: CVPixelBuffer) throws -> CVPixelBuffer {
        let W = TrackNetConstants.inputWidth
        let H = TrackNetConstants.inputHeight

        let dst = try acquirePooledBuffer(width: W, height: H)

        let srcW = CGFloat(CVPixelBufferGetWidth(source))
        let srcH = CGFloat(CVPixelBufferGetHeight(source))
        guard srcW > 0, srcH > 0 else {
            throw TrackNetDetectorError.predictionFailed("source pixel buffer has zero extent")
        }

        let ciImage = CIImage(cvPixelBuffer: source)
        let scaleX = CGFloat(W) / srcW
        let scaleY = CGFloat(H) / srcH
        let scaled = ciImage.transformed(
            by: CGAffineTransform(scaleX: scaleX, y: scaleY)
        )

        ciContext.render(
            scaled,
            to: dst,
            bounds: CGRect(x: 0, y: 0, width: W, height: H),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return dst
    }

    private func acquirePooledBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        lock.lock()
        let existing = bufferPool
        lock.unlock()

        let pool: CVPixelBufferPool
        if let existing {
            pool = existing
        } else {
            let attrs: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
            ]
            var created: CVPixelBufferPool?
            let status = CVPixelBufferPoolCreate(
                kCFAllocatorDefault,
                nil,
                attrs as CFDictionary,
                &created
            )
            guard status == kCVReturnSuccess, let created else {
                throw TrackNetDetectorError.predictionFailed("CVPixelBufferPool creation failed: \(status)")
            }
            lock.lock()
            bufferPool = created
            lock.unlock()
            pool = created
        }

        var out: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &out)
        guard status == kCVReturnSuccess, let out else {
            throw TrackNetDetectorError.predictionFailed("pool allocation failed: \(status)")
        }
        return out
    }
}
