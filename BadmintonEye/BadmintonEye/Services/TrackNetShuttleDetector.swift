import CoreGraphics
import CoreImage
import CoreML
import CoreVideo
import Foundation

// MARK: - Constants

enum TrackNetConstants {
    /// Filename (without extension) of the compiled model in the app bundle.
    /// Xcode compiles `TrackNetV3.mlpackage` → `TrackNetV3.mlmodelc` at build time.
    static let modelName = "TrackNetV3"

    /// Input window size — the released checkpoint was trained with seq_len=8.
    static let frameWindow = 8

    /// Model input dimensions (height x width).
    static let inputHeight = 288
    static let inputWidth = 512

    /// Total input channels: 8 RGB frames (24) + 3 channels of background image = 27.
    static let inputChannels = 24 + 3

    /// Minimum heatmap peak value to count as a real shuttle detection.
    static let detectionThreshold: Float = 0.5
}

// MARK: - Window observation

/// One shuttle observation from a window of 8 frames. `position` is in
/// normalized (0...1) image coordinates; `nil` means no shuttle visible
/// (peak below threshold).
struct TrackNetWindowObservation: Sendable, Equatable {
    let position: CGPoint?
    let confidence: Float
    /// Index within the input window (0..<8).
    let windowFrameIndex: Int
}

// MARK: - Errors

enum TrackNetDetectorError: LocalizedError {
    case modelNotFound
    case wrongInputWindow(got: Int, expected: Int)
    case predictionFailed(String)
    case unexpectedOutputShape(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "TrackNetV3.mlmodelc was not found in the app bundle."
        case .wrongInputWindow(let got, let expected):
            return "TrackNetV3 expects \(expected) input frames but got \(got)."
        case .predictionFailed(let reason):
            return "TrackNetV3 inference failed: \(reason)."
        case .unexpectedOutputShape(let what):
            return "TrackNetV3 returned an unexpected output: \(what)."
        }
    }
}

// MARK: - Detector

/// Multi-frame shuttle detector backed by the TrackNetV3 Core ML model.
///
/// Unlike `CoreMLShuttleDetector` (per-frame, Vision-style), TrackNetV3
/// consumes a sliding window of 8 consecutive frames + a 3-channel
/// background image, and returns 8 heatmaps — one per input frame. We
/// argmax each heatmap to get the shuttle position in that frame.
///
/// This detector is intentionally not wired into the `RallySuggesting`
/// pipeline yet — Phase D will compose it with `CircularFrameBuffer` and
/// `TrajectoryCalculator` behind a real `RallySuggesting` implementation.
/// For now it exists so the model can be loaded, smoke-tested on-device,
/// and iterated independently of the UX surface.
final class TrackNetShuttleDetector: @unchecked Sendable {

    // MARK: - Properties

    private var model: MLModel?
    private let lock = NSLock()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Model loading

    /// Lazy, thread-safe load of the compiled `.mlmodelc` bundled with the
    /// app. Returns the cached instance after the first call.
    func loadModelIfNeeded() throws -> MLModel {
        if let cached = model { return cached }
        lock.lock()
        defer { lock.unlock() }
        if let cached = model { return cached }

        guard let url = Bundle.main.url(
            forResource: TrackNetConstants.modelName,
            withExtension: "mlmodelc"
        ) else {
            throw TrackNetDetectorError.modelNotFound
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all  // CPU + GPU + Neural Engine
        do {
            let loaded = try MLModel(contentsOf: url, configuration: config)
            self.model = loaded
            return loaded
        } catch {
            throw TrackNetDetectorError.predictionFailed(error.localizedDescription)
        }
    }

    // MARK: - Inference

    /// Run TrackNetV3 on a window of 8 frames plus a background image.
    /// All inputs must already be downscaled / preprocessed to 288x512 RGB.
    ///
    /// - Parameters:
    ///   - frames: exactly 8 CVPixelBuffers, oldest first.
    ///   - background: median-blended background pixel buffer for the same
    ///     scene window (288x512, RGB). Pass any frame of the window if a
    ///     true median is not yet available — accuracy degrades but the
    ///     model still produces something.
    /// - Returns: 8 observations, one per input frame.
    func detect(
        frames: [CVPixelBuffer],
        background: CVPixelBuffer
    ) async throws -> [TrackNetWindowObservation] {
        guard frames.count == TrackNetConstants.frameWindow else {
            throw TrackNetDetectorError.wrongInputWindow(
                got: frames.count,
                expected: TrackNetConstants.frameWindow
            )
        }

        let model = try loadModelIfNeeded()

        // Build a (1, 27, 288, 512) Float32 MLMultiArray.
        // Channel layout: frame0_R, frame0_G, frame0_B, frame1_R, ..., bg_R, bg_G, bg_B
        let shape: [NSNumber] = [
            1,
            NSNumber(value: TrackNetConstants.inputChannels),
            NSNumber(value: TrackNetConstants.inputHeight),
            NSNumber(value: TrackNetConstants.inputWidth)
        ]
        let input = try MLMultiArray(shape: shape, dataType: .float32)

        // Fill the input. Each pixel buffer is read once and its R/G/B
        // planes copied into the corresponding channels of the multi-array.
        for (i, frame) in frames.enumerated() {
            try writeRGB(
                from: frame,
                into: input,
                channelOffset: i * 3
            )
        }
        try writeRGB(
            from: background,
            into: input,
            channelOffset: TrackNetConstants.frameWindow * 3
        )

        let provider = try MLDictionaryFeatureProvider(dictionary: ["frames": input])
        let prediction: MLFeatureProvider
        do {
            prediction = try await model.prediction(from: provider)
        } catch {
            throw TrackNetDetectorError.predictionFailed(error.localizedDescription)
        }

        guard let heatmap = prediction.featureValue(for: "heatmap")?.multiArrayValue else {
            throw TrackNetDetectorError.unexpectedOutputShape("missing 'heatmap' feature")
        }
        let expectedHeatmapShape: [NSNumber] = [
            1,
            NSNumber(value: TrackNetConstants.frameWindow),
            NSNumber(value: TrackNetConstants.inputHeight),
            NSNumber(value: TrackNetConstants.inputWidth)
        ]
        guard heatmap.shape == expectedHeatmapShape else {
            throw TrackNetDetectorError.unexpectedOutputShape("got \(heatmap.shape)")
        }

        return argmaxPerFrame(heatmap: heatmap)
    }

    // MARK: - Heatmap → observations

    /// Walk each of the 8 heatmaps, find the pixel with the highest sigmoid
    /// activation, and convert it to a normalized CGPoint. Below-threshold
    /// peaks resolve to `nil` (no shuttle visible that frame).
    private func argmaxPerFrame(heatmap: MLMultiArray) -> [TrackNetWindowObservation] {
        let H = TrackNetConstants.inputHeight
        let W = TrackNetConstants.inputWidth
        let frameCount = TrackNetConstants.frameWindow

        var results: [TrackNetWindowObservation] = []
        results.reserveCapacity(frameCount)

        // Stride to walk Float32 plane data directly — avoids per-element
        // ObjC bridging through `[NSNumber]` subscripting.
        let pointer = heatmap.dataPointer.bindMemory(
            to: Float32.self,
            capacity: heatmap.count
        )

        let stridePerFrame = H * W

        for f in 0..<frameCount {
            let base = f * stridePerFrame
            var maxVal: Float32 = -.infinity
            var maxIdx: Int = 0
            for i in 0..<stridePerFrame {
                let v = pointer[base + i]
                if v > maxVal {
                    maxVal = v
                    maxIdx = i
                }
            }

            if maxVal >= TrackNetConstants.detectionThreshold {
                let y = maxIdx / W
                let x = maxIdx % W
                let position = CGPoint(
                    x: CGFloat(x) / CGFloat(W),
                    y: CGFloat(y) / CGFloat(H)
                )
                results.append(TrackNetWindowObservation(
                    position: position,
                    confidence: maxVal,
                    windowFrameIndex: f
                ))
            } else {
                results.append(TrackNetWindowObservation(
                    position: nil,
                    confidence: maxVal,
                    windowFrameIndex: f
                ))
            }
        }

        return results
    }

    // MARK: - Pixel buffer → MLMultiArray channels

    /// Copy the RGB planes of an already-288x512 `CVPixelBuffer` (BGRA or
    /// 420f) into three consecutive channels of `target`, normalized to
    /// `[0, 1]` as Float32.
    private func writeRGB(
        from pixelBuffer: CVPixelBuffer,
        into target: MLMultiArray,
        channelOffset: Int
    ) throws {
        let H = TrackNetConstants.inputHeight
        let W = TrackNetConstants.inputWidth

        guard
            CVPixelBufferGetWidth(pixelBuffer) == W,
            CVPixelBufferGetHeight(pixelBuffer) == H
        else {
            // Caller is responsible for resizing; failing fast catches
            // pipeline bugs early.
            throw TrackNetDetectorError.unexpectedOutputShape(
                "pixel buffer is \(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer)), expected \(W)x\(H)"
            )
        }

        // Render the pixel buffer into a BGRA byte buffer we can index.
        // Going through CoreImage handles any source format (420f, etc.).
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        var bgra = [UInt8](repeating: 0, count: H * W * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        ciContext.render(
            ciImage,
            toBitmap: &bgra,
            rowBytes: W * 4,
            bounds: CGRect(x: 0, y: 0, width: W, height: H),
            format: .BGRA8,
            colorSpace: colorSpace
        )

        let pointer = target.dataPointer.bindMemory(
            to: Float32.self,
            capacity: target.count
        )
        let stridePerChannel = H * W

        // BGRA → RGB, normalize, store as planar channels.
        for y in 0..<H {
            for x in 0..<W {
                let pixelIndex = y * W + x
                let bgraIndex = pixelIndex * 4
                let b = Float32(bgra[bgraIndex])     / 255.0
                let g = Float32(bgra[bgraIndex + 1]) / 255.0
                let r = Float32(bgra[bgraIndex + 2]) / 255.0
                pointer[(channelOffset + 0) * stridePerChannel + pixelIndex] = r
                pointer[(channelOffset + 1) * stridePerChannel + pixelIndex] = g
                pointer[(channelOffset + 2) * stridePerChannel + pixelIndex] = b
            }
        }
    }
}
