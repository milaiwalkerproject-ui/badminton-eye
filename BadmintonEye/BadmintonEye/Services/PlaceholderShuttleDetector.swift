import CoreGraphics
import CoreVideo
import Foundation

/// Placeholder shuttle detector that generates simulated positions along
/// a realistic parabolic arc. Used during development and user testing
/// until a real YOLO model is trained (Phase 9).
final class PlaceholderShuttleDetector: ShuttleDetecting, @unchecked Sendable {

    var modelName: String { "Placeholder v1.0" }

    /// Not supported -- placeholder does not analyze real frames.
    func detect(in pixelBuffer: CVPixelBuffer) async throws -> [ShuttleObservation] {
        throw PlaceholderDetectorError.realFrameNotSupported
    }

    /// Generates simulated shuttle positions along a realistic parabolic arc.
    /// Starts from one side of the court, arcs upward, then descends toward the opposite side.
    /// Adds small random noise (+-5 pixels) for realism.
    func detect(imageSize: CGSize, frameCount: Int) async throws -> [ShuttleObservation] {
        let w = imageSize.width
        let h = imageSize.height

        // Shuttle travels from bottom-left area to top-right area of image
        let startX = w * 0.2
        let endX = w * 0.75
        let startY = h * 0.8
        let endY = h * 0.3

        var observations = [ShuttleObservation]()

        for i in 0..<frameCount {
            let t = Double(i) / Double(frameCount - 1)

            // Linear horizontal movement
            let x = startX + (endX - startX) * t

            // Parabolic vertical movement (arcs upward then descends)
            // Peak at t=0.4, creating a natural shuttle arc
            let baseY = startY + (endY - startY) * t
            let arcHeight = -h * 0.15 * (4 * t * (1 - t)) // parabolic arc offset
            let y = baseY + arcHeight

            // Add random noise (+-5 pixels)
            let noiseX = Double.random(in: -5...5)
            let noiseY = Double.random(in: -5...5)

            let position = CGPoint(x: x + noiseX, y: y + noiseY)
            observations.append(
                ShuttleObservation(position: position, confidence: 0.9, frameIndex: i)
            )
        }

        return observations
    }
}

// MARK: - Error

enum PlaceholderDetectorError: LocalizedError {
    case realFrameNotSupported

    var errorDescription: String? {
        switch self {
        case .realFrameNotSupported:
            return "Placeholder detector does not support real frame analysis. Use a trained model instead."
        }
    }
}
