import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import Vision

// MARK: - Constants

enum CoreMLDetectorConstants {
    static let defaultModelName = "ShuttlecockDetector"
    static let confidenceThreshold: Float = 0.5
}

// MARK: - CoreMLShuttleDetector

/// Runs a trained YOLO model via Vision framework for on-device shuttlecock detection.
/// The model is lazy-loaded on first detection call and cached in memory.
final class CoreMLShuttleDetector: ShuttleDetecting, @unchecked Sendable {

    // MARK: - Properties

    static let defaultModelName = CoreMLDetectorConstants.defaultModelName

    let modelName: String

    /// Lazy-loaded Vision model, cached after first load.
    private var vnModel: VNCoreMLModel?

    /// Thread safety for lazy model initialization.
    private let lock = NSLock()

    // MARK: - Init

    init(modelName: String = CoreMLDetectorConstants.defaultModelName) {
        self.modelName = modelName
    }

    // MARK: - Model Loading

    /// Loads and caches the CoreML model as a VNCoreMLModel. Thread-safe via NSLock.
    private func loadModelIfNeeded() throws -> VNCoreMLModel {
        if let cached = vnModel {
            return cached
        }

        lock.lock()
        defer { lock.unlock() }

        // Double-check after acquiring lock
        if let cached = vnModel {
            return cached
        }

        guard let modelURL = Bundle.main.url(
            forResource: modelName,
            withExtension: "mlmodelc"
        ) else {
            throw CoreMLDetectorError.modelNotFound(modelName)
        }

        do {
            let mlModel = try MLModel(contentsOf: modelURL)
            let visionModel = try VNCoreMLModel(for: mlModel)
            vnModel = visionModel
            return visionModel
        } catch {
            throw CoreMLDetectorError.inferenceFailed(error.localizedDescription)
        }
    }

    // MARK: - ShuttleDetecting

    /// Detect shuttlecock positions in a real video frame using Vision framework.
    func detect(in pixelBuffer: CVPixelBuffer) async throws -> [ShuttleObservation] {
        let model = try loadModelIfNeeded()

        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw CoreMLDetectorError.inferenceFailed(error.localizedDescription)
        }

        guard let results = request.results as? [VNRecognizedObjectObservation] else {
            return []
        }

        return results
            .filter { $0.confidence >= CoreMLDetectorConstants.confidenceThreshold }
            .map { observation in
                ShuttleObservation(
                    position: CGPoint(
                        x: observation.boundingBox.midX,
                        y: 1.0 - observation.boundingBox.midY
                    ),
                    confidence: observation.confidence,
                    frameIndex: 0 // Caller sets the correct frame index
                )
            }
    }

    /// Not supported -- CoreMLShuttleDetector requires real video frames.
    func detect(imageSize: CGSize, frameCount: Int) async throws -> [ShuttleObservation] {
        throw CoreMLDetectorError.simulationNotSupported
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
            return "CoreML model '\(name)' not found in app bundle."
        case .simulationNotSupported:
            return "CoreMLShuttleDetector requires real video frames."
        case .inferenceFailed(let reason):
            return "Vision inference failed: \(reason)"
        }
    }
}
