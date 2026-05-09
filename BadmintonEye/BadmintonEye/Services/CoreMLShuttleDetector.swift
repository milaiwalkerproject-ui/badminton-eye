import Accelerate
import CoreGraphics
import CoreImage
import CoreML
import CoreVideo
import Foundation

// MARK: - Constants

/// TrackNetV3 model contract.
///
/// The exported `.mlpackage`:
///   * accepts a single ML feature input named `input_frames` —
///     `MLMultiArray` of shape `(1, 27, 288, 512)` (Float32 or Float16),
///     i.e. nine consecutive RGB frames stacked on the channel axis,
///     pixel values normalized to `[0, 1]`.
///   * returns a single output named `heatmaps` —
///     `MLMultiArray` of shape `(1, 8, 288, 512)` containing
///     per-frame heatmap *logits*. Apply sigmoid for probability.
///
/// The detector takes the most recent frame's heatmap (last output
/// channel) and returns the argmax peak as a normalized `[0, 1]`
/// image-space coordinate, with `confidence = sigmoid(max_logit)`.
enum CoreMLDetectorConstants {
    /// Default `.mlpackage` / `.mlmodelc` filename, without extension.
    static let defaultModelName = "TrackNetV3"

    /// Required input image height (model architecture).
    static let modelInputHeight = 288

    /// Required input image width (model architecture).
    static let modelInputWidth = 512

    /// Number of consecutive frames stacked on the channel axis.
    /// TrackNetV3 uses 9 frames (vs. TrackNetV2's 3).
    static let numInputFrames = 9

    /// Number of channels per frame (RGB).
    static let channelsPerFrame = 3

    /// Number of output heatmap channels produced by the model.
    /// TrackNetV3 outputs 8 channels; we use the last one for the
    /// most recent frame's detection.
    static let numOutputChannels = 8

    /// Probability threshold below which a peak is suppressed.
    /// `sigmoid(0) = 0.5`, so a logit threshold of 0 corresponds to
    /// "model thinks it's more likely shuttle-present than not".
    /// Tune with field data; keep on the conservative side to reduce
    /// false positives in trajectory fitting.
    static let confidenceThreshold: Float = 0.5
}

// MARK: - CoreMLShuttleDetector

/// Runs the trained TrackNetV3 heatmap regression model on-device.
///
/// Maintains an internal sliding window of the nine most recent video
/// frames so that `HawkEyePipeline` can keep calling `detect(in:)`
/// per-frame without knowing the model takes a temporal stack.
///
/// On the first frame (warm-up), the buffer is padded by replicating
/// the incoming frame so the model can still produce a detection — the
/// motion-context benefit is reduced for the first eight frames but the
/// pipeline gets a usable result from frame 1.
///
/// Thread-safety: `detect(in:)` is `async` and may be called from any
/// thread; an `NSLock` guards the model load and frame buffer.
final class CoreMLShuttleDetector: ShuttleDetecting, @unchecked Sendable {

    // MARK: - Properties

    static let defaultModelName = CoreMLDetectorConstants.defaultModelName

    let modelName: String

    /// Lazy-loaded CoreML model. We use `MLModel` directly (not Vision)
    /// because TrackNetV2 takes a stacked-frame `MLMultiArray` rather
    /// than the single-image input that Vision wraps.
    private var mlModel: MLModel?

    /// Cached input feature name discovered from the model spec.
    /// Defaults to `"input_frames"` per the TrackNetV3 export contract;
    /// we re-read from `modelDescription.inputDescriptionsByName` on load
    /// to be tolerant of older exports that used a different name.
    private var inputFeatureName: String = "input_frames"

    /// Cached output feature name (first output port). CoreML names
    /// it whatever the traced graph's last op was named, so we discover
    /// rather than hard-code.
    private var outputFeatureName: String?

    /// Sliding window of the most recent rendered frames as
    /// pre-normalized RGB byte arrays of length `H * W * 3`.
    private var frameBuffer: [[UInt8]] = []

    /// Reusable CIContext for pixelBuffer → RGBA8 resize.
    /// Build once; re-using avoids per-frame Metal allocator churn.
    private let ciContext: CIContext = CIContext(options: [
        .useSoftwareRenderer: false
    ])

    /// Lock guarding `mlModel`, `inputFeatureName`, `outputFeatureName`,
    /// and `frameBuffer`. The detector is `@unchecked Sendable` so we
    /// rely on this lock for safety across `async` calls.
    private let lock = NSLock()

    // MARK: - Init

    init(modelName: String = CoreMLDetectorConstants.defaultModelName) {
        self.modelName = modelName
    }

    /// Clears the internal frame buffer. Call between independent video
    /// sessions so the first frame of the next video doesn't get
    /// blended with stale data from the previous one.
    nonisolated func reset() {
        lock.withLock {
            frameBuffer.removeAll(keepingCapacity: true)
        }
    }

    // MARK: - Model Loading

    /// Loads the model on demand. Discovers input + output feature names
    /// from the spec so we tolerate small naming drift between exports.
    private func loadModelIfNeeded() throws -> MLModel {
        if let cached = mlModel {
            return cached
        }

        // Try .mlmodelc (compiled) first — Xcode auto-compiles bundled
        // .mlpackage to .mlmodelc at build time. Fall back to a
        // user-pre-compiled .mlmodel, then to a runtime-compiled
        // .mlpackage URL (slower; only happens if Xcode skipped it).
        let url: URL
        if let compiled = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
            url = compiled
        } else if let raw = Bundle.main.url(forResource: modelName, withExtension: "mlmodel") {
            // .mlmodel needs runtime compilation.
            do {
                url = try MLModel.compileModel(at: raw)
            } catch {
                throw CoreMLDetectorError.inferenceFailed(
                    "Failed to compile \(modelName).mlmodel: \(error.localizedDescription)"
                )
            }
        } else if let pkg = Bundle.main.url(forResource: modelName, withExtension: "mlpackage") {
            do {
                url = try MLModel.compileModel(at: pkg)
            } catch {
                throw CoreMLDetectorError.inferenceFailed(
                    "Failed to compile \(modelName).mlpackage: \(error.localizedDescription)"
                )
            }
        } else {
            throw CoreMLDetectorError.modelNotFound(modelName)
        }

        let config = MLModelConfiguration()
        // Use CPU + Neural Engine for low-latency inference on iPhone 12+
        // (matches the export-time `compute_units="cpu_and_ne"` default).
        config.computeUnits = .cpuAndNeuralEngine

        let model: MLModel
        do {
            model = try MLModel(contentsOf: url, configuration: config)
        } catch {
            throw CoreMLDetectorError.inferenceFailed(error.localizedDescription)
        }

        // Discover feature names. TrackNetV3 exports use "input_frames"
        // for input and "heatmaps" for output, but be tolerant of older
        // TrackNetV2 exports that used "frames".
        let inputs = model.modelDescription.inputDescriptionsByName
        if inputs["input_frames"] != nil {
            inputFeatureName = "input_frames"
        } else if inputs["frames"] != nil {
            inputFeatureName = "frames"
        } else if let firstInput = inputs.keys.sorted().first {
            inputFeatureName = firstInput
        } else {
            throw CoreMLDetectorError.inferenceFailed(
                "Model \(modelName) has no input features."
            )
        }

        let outputs = model.modelDescription.outputDescriptionsByName
        // Prefer "heatmaps" (TrackNetV3), then "heatmap" (TrackNetV2),
        // otherwise the first output.
        if outputs["heatmaps"] != nil {
            outputFeatureName = "heatmaps"
        } else if outputs["heatmap"] != nil {
            outputFeatureName = "heatmap"
        } else if let first = outputs.keys.sorted().first {
            outputFeatureName = first
        } else {
            throw CoreMLDetectorError.inferenceFailed(
                "Model \(modelName) has no output features."
            )
        }

        mlModel = model
        return model
    }

    // MARK: - ShuttleDetecting

    /// Detect the shuttlecock in a single frame.
    ///
    /// The detector maintains an internal sliding window of the nine
    /// most recent frames; on the first call the buffer is filled by
    /// replicating the incoming frame so we can still produce a
    /// detection without an 8-frame warm-up cost.
    ///
    /// Returns at most one observation per call (TrackNetV3 emits one
    /// heatmap peak per frame). Coordinates are normalized to `[0, 1]`
    /// in image space (origin top-left, x → right, y → down) so the
    /// caller (`HawkEyePipeline`) can scale to original frame
    /// dimensions in the standard way.
    /// Synchronous helper: loads model and updates the frame buffer
    /// under the lock. Returns all state needed for inference so the
    /// caller can proceed without holding the lock. Because this method
    /// is *not* `async`, NSLock usage is safe and won't be flagged by
    /// Swift 6 concurrency checking.
    private func prepareInference(
        pixelBuffer: CVPixelBuffer
    ) throws -> (model: MLModel, frames: [[UInt8]], inputName: String, outputName: String) {
        lock.lock()
        defer { lock.unlock() }

        let model = try loadModelIfNeeded()

        let frameRGB = try Self.renderRGB(
            pixelBuffer: pixelBuffer,
            width: CoreMLDetectorConstants.modelInputWidth,
            height: CoreMLDetectorConstants.modelInputHeight,
            ciContext: ciContext
        )

        let f = CoreMLDetectorConstants.numInputFrames
        if frameBuffer.isEmpty {
            frameBuffer = Array(repeating: frameRGB, count: f)
        } else {
            frameBuffer.append(frameRGB)
            if frameBuffer.count > f {
                frameBuffer.removeFirst(frameBuffer.count - f)
            }
        }
        let bufferedFrames = frameBuffer
        let inputName = inputFeatureName
        let outputName = outputFeatureName ?? ""
        return (model, bufferedFrames, inputName, outputName)
    }

    func detect(in pixelBuffer: CVPixelBuffer) async throws -> [ShuttleObservation] {
        let (model, bufferedFrames, inputName, outputName) = try prepareInference(
            pixelBuffer: pixelBuffer
        )

        // Build input MLMultiArray (1, 27, 288, 512) Float32.
        let multiArray: MLMultiArray
        do {
            multiArray = try Self.buildInputMultiArray(framesRGB: bufferedFrames)
        } catch {
            throw CoreMLDetectorError.inferenceFailed(
                "MLMultiArray allocation failed: \(error.localizedDescription)"
            )
        }

        let provider: MLFeatureProvider
        do {
            provider = try MLDictionaryFeatureProvider(dictionary: [
                inputName: MLFeatureValue(multiArray: multiArray)
            ])
        } catch {
            throw CoreMLDetectorError.inferenceFailed(
                "Feature provider build failed: \(error.localizedDescription)"
            )
        }

        let prediction: MLFeatureProvider
        do {
            prediction = try await model.prediction(from: provider)
        } catch {
            throw CoreMLDetectorError.inferenceFailed(
                "TrackNetV3 inference failed: \(error.localizedDescription)"
            )
        }

        guard let heatmap = prediction.featureValue(for: outputName)?.multiArrayValue
        else {
            throw CoreMLDetectorError.inferenceFailed(
                "Model output '\(outputName)' missing or not an MLMultiArray."
            )
        }

        // Decode the heatmap for the *last* (most recent) frame.
        // Output shape: (1, C, H, W) — C = numOutputChannels.
        guard let peak = Self.decodeLastFramePeak(
            heatmap: heatmap,
            numOutputChannels: CoreMLDetectorConstants.numOutputChannels,
            height: CoreMLDetectorConstants.modelInputHeight,
            width: CoreMLDetectorConstants.modelInputWidth
        ) else {
            return []
        }

        let confidence = Self.sigmoid(peak.value)
        if confidence < CoreMLDetectorConstants.confidenceThreshold {
            return []
        }

        // Normalize to [0, 1] image coordinates (origin top-left).
        let xNorm = (Double(peak.x) + 0.5) / Double(CoreMLDetectorConstants.modelInputWidth)
        let yNorm = (Double(peak.y) + 0.5) / Double(CoreMLDetectorConstants.modelInputHeight)

        return [
            ShuttleObservation(
                position: CGPoint(x: xNorm, y: yNorm),
                confidence: confidence,
                frameIndex: 0  // pipeline overwrites with the real frame index
            )
        ]
    }

    /// Not supported — the CoreML detector requires real video frames.
    func detect(imageSize: CGSize, frameCount: Int) async throws -> [ShuttleObservation] {
        throw CoreMLDetectorError.simulationNotSupported
    }

    // MARK: - Internal helpers (also used by tests)

    /// Decoded peak in the most recent frame's heatmap.
    struct HeatmapPeak: Equatable {
        let x: Int
        let y: Int
        let value: Float  // raw logit (pre-sigmoid)
    }

    /// Render a `CVPixelBuffer` (any pixel format CoreImage understands)
    /// to a flat row-major RGB byte array of the requested dimensions.
    /// Returns `[R0, G0, B0, R1, G1, B1, ...]` with length `width * height * 3`.
    static func renderRGB(
        pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int,
        ciContext: CIContext
    ) throws -> [UInt8] {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Scale to (width × height) absolute size. We use scaleFill
        // semantics (anisotropic stretch); the target aspect is 16:9
        // so 16:9 source video is preserved without distortion. For
        // 4:3 source there will be slight horizontal stretch — same
        // trade-off the previous Vision .scaleFill path made.
        let srcW = ciImage.extent.width
        let srcH = ciImage.extent.height
        guard srcW > 0, srcH > 0 else {
            throw CoreMLDetectorError.inferenceFailed(
                "Source pixel buffer has zero dimension."
            )
        }
        let scaleX = CGFloat(width) / srcW
        let scaleY = CGFloat(height) / srcH
        let scaled = ciImage.transformed(
            by: CGAffineTransform(scaleX: scaleX, y: scaleY)
        )

        // Render to a contiguous BGRA8 buffer (most efficient native
        // format on iOS), then unpack to interleaved RGB.
        let bytesPerRow = width * 4
        var bgra = [UInt8](repeating: 0, count: bytesPerRow * height)
        let renderRect = CGRect(x: 0, y: 0, width: width, height: height)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw CoreMLDetectorError.inferenceFailed(
                "sRGB color space unavailable."
            )
        }
        bgra.withUnsafeMutableBytes { rawPtr in
            guard let base = rawPtr.baseAddress else { return }
            ciContext.render(
                scaled,
                toBitmap: base,
                rowBytes: bytesPerRow,
                bounds: renderRect,
                format: .BGRA8,
                colorSpace: colorSpace
            )
        }

        // Interleaved BGRA → interleaved RGB. (CoreML wants RGB and
        // dropping the alpha is fine for opaque video frames.)
        let pixelCount = width * height
        var rgb = [UInt8](repeating: 0, count: pixelCount * 3)
        for i in 0..<pixelCount {
            let b = bgra[i * 4 + 0]
            let g = bgra[i * 4 + 1]
            let r = bgra[i * 4 + 2]
            // alpha at +3 dropped
            rgb[i * 3 + 0] = r
            rgb[i * 3 + 1] = g
            rgb[i * 3 + 2] = b
        }
        return rgb
    }

    /// Build the input `MLMultiArray` `(1, 27, 288, 512)` Float32 from
    /// the buffered RGB frames. Pixel values are normalized to `[0, 1]`
    /// (matches the training pipeline's per-frame `pixel / 255.0`
    /// preprocessing).
    static func buildInputMultiArray(framesRGB: [[UInt8]]) throws -> MLMultiArray {
        let f = CoreMLDetectorConstants.numInputFrames
        let cpf = CoreMLDetectorConstants.channelsPerFrame
        let h = CoreMLDetectorConstants.modelInputHeight
        let w = CoreMLDetectorConstants.modelInputWidth
        let totalChannels = f * cpf

        precondition(
            framesRGB.count == f,
            "Expected \(f) frames in the buffer; got \(framesRGB.count)."
        )

        let shape: [NSNumber] = [1, NSNumber(value: totalChannels),
                                 NSNumber(value: h), NSNumber(value: w)]
        let mlArray = try MLMultiArray(shape: shape, dataType: .float32)
        // Strides for the freshly-allocated contiguous shape (1, C, H, W):
        // (C*H*W, H*W, W, 1). MLMultiArray(shape:dataType:) guarantees
        // contiguous layout so we can use arithmetic strides directly.
        let strideC = h * w
        let strideH = w
        let pixelsPerFrame = h * w

        let basePtr = mlArray.dataPointer.assumingMemoryBound(to: Float.self)

        // Channel layout (oldest → newest, matches TrackNet paper):
        //   c=0: R_t-2,  c=1: G_t-2,  c=2: B_t-2,
        //   c=3: R_t-1,  c=4: G_t-1,  c=5: B_t-1,
        //   c=6: R_t,    c=7: G_t,    c=8: B_t
        for frameIdx in 0..<f {
            let frame = framesRGB[frameIdx]
            precondition(
                frame.count == pixelsPerFrame * cpf,
                "Frame \(frameIdx) has wrong byte count."
            )
            for ch in 0..<cpf {
                let multiArrayChannel = frameIdx * cpf + ch
                let chOffset = multiArrayChannel * strideC
                for y in 0..<h {
                    let rowOffset = chOffset + y * strideH
                    let rgbRowOffset = (y * w) * cpf + ch
                    for x in 0..<w {
                        let pixel = frame[rgbRowOffset + x * cpf]
                        basePtr[rowOffset + x] = Float(pixel) / 255.0
                    }
                }
            }
        }

        return mlArray
    }

    /// Decode the spatial argmax of the heatmap channel for the most
    /// recent frame. Returns `nil` only if the array shape is not
    /// recognized (defensive — should never happen for valid TrackNetV3
    /// output).
    static func decodeLastFramePeak(
        heatmap: MLMultiArray,
        numOutputChannels: Int,
        height: Int,
        width: Int
    ) -> HeatmapPeak? {
        // Expected shape: (1, C, H, W) or (C, H, W). Be tolerant.
        let dims = heatmap.shape.map(\.intValue)
        let lastFrameChannel: Int
        if dims.count == 4 {
            // (N, C, H, W)
            guard dims[0] == 1,
                  dims[1] >= numOutputChannels,
                  dims[2] == height,
                  dims[3] == width else {
                return nil
            }
            lastFrameChannel = numOutputChannels - 1
        } else if dims.count == 3 {
            // (C, H, W)
            guard dims[0] >= numOutputChannels,
                  dims[1] == height,
                  dims[2] == width else {
                return nil
            }
            lastFrameChannel = numOutputChannels - 1
        } else {
            return nil
        }

        // Compute the byte offset to the last frame's HxW slice using
        // the multiarray's actual strides (CoreML may pad rows for
        // alignment, so don't assume contiguous layout).
        let strides = heatmap.strides.map(\.intValue)
        precondition(strides.count == dims.count)

        // Channel offset in element units.
        let channelOffsetElements: Int
        if dims.count == 4 {
            channelOffsetElements = lastFrameChannel * strides[1]
        } else {
            channelOffsetElements = lastFrameChannel * strides[0]
        }

        let strideH = dims.count == 4 ? strides[2] : strides[1]
        let strideW = dims.count == 4 ? strides[3] : strides[2]

        switch heatmap.dataType {
        case .float32:
            let base = heatmap.dataPointer.assumingMemoryBound(to: Float.self)
            return scanPeak(
                base: base, channelOffset: channelOffsetElements,
                height: height, width: width,
                strideH: strideH, strideW: strideW
            )
        case .float16:
            #if canImport(Foundation) && swift(>=5.3)
            // Float16 is iOS 14.5+ / Swift 5.3+.
            let base = heatmap.dataPointer.assumingMemoryBound(to: Float16.self)
            return scanPeakF16(
                base: base, channelOffset: channelOffsetElements,
                height: height, width: width,
                strideH: strideH, strideW: strideW
            )
            #else
            return nil
            #endif
        case .double:
            let base = heatmap.dataPointer.assumingMemoryBound(to: Double.self)
            var bestX = 0, bestY = 0
            var bestVal = -Double.infinity
            for y in 0..<height {
                let rowBase = channelOffsetElements + y * strideH
                for x in 0..<width {
                    let v = base[rowBase + x * strideW]
                    if v > bestVal {
                        bestVal = v
                        bestX = x
                        bestY = y
                    }
                }
            }
            return HeatmapPeak(x: bestX, y: bestY, value: Float(bestVal))
        @unknown default:
            return nil
        }
    }

    private static func scanPeak(
        base: UnsafePointer<Float>,
        channelOffset: Int,
        height: Int,
        width: Int,
        strideH: Int,
        strideW: Int
    ) -> HeatmapPeak {
        var bestX = 0, bestY = 0
        var bestVal: Float = -.infinity
        for y in 0..<height {
            let rowBase = channelOffset + y * strideH
            for x in 0..<width {
                let v = base[rowBase + x * strideW]
                if v > bestVal {
                    bestVal = v
                    bestX = x
                    bestY = y
                }
            }
        }
        return HeatmapPeak(x: bestX, y: bestY, value: bestVal)
    }

    private static func scanPeakF16(
        base: UnsafePointer<Float16>,
        channelOffset: Int,
        height: Int,
        width: Int,
        strideH: Int,
        strideW: Int
    ) -> HeatmapPeak {
        var bestX = 0, bestY = 0
        var bestVal: Float = -.infinity
        for y in 0..<height {
            let rowBase = channelOffset + y * strideH
            for x in 0..<width {
                let v = Float(base[rowBase + x * strideW])
                if v > bestVal {
                    bestVal = v
                    bestX = x
                    bestY = y
                }
            }
        }
        return HeatmapPeak(x: bestX, y: bestY, value: bestVal)
    }

    /// Numerically stable sigmoid. Used for heatmap-peak → confidence.
    static func sigmoid(_ x: Float) -> Float {
        if x >= 0 {
            let z = expf(-x)
            return 1.0 / (1.0 + z)
        } else {
            let z = expf(x)
            return z / (1.0 + z)
        }
    }
}

// MARK: - Errors

enum CoreMLDetectorError: LocalizedError {
    case modelNotFound(String)
    case simulationNotSupported
    case inferenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "CoreML model '\(name)' not found in app bundle. " +
                   "Did you run `make export-coreml` and add the .mlpackage to the Xcode target?"
        case .simulationNotSupported:
            return "CoreMLShuttleDetector requires real video frames."
        case .inferenceFailed(let reason):
            return "TrackNetV3 inference failed: \(reason)"
        }
    }
}
