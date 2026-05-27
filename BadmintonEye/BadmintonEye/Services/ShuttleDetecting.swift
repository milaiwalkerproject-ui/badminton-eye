import CoreGraphics
import CoreVideo
import Foundation

/// A single shuttle detection observation from one video frame.
public struct ShuttleObservation: Sendable {
    /// Image-space coordinate of the detected shuttlecock.
    public let position: CGPoint
    /// Detection confidence from 0.0 to 1.0.
    public let confidence: Float
    /// The frame index this detection came from.
    public let frameIndex: Int

    public init(position: CGPoint, confidence: Float, frameIndex: Int) {
        self.position = position
        self.confidence = confidence
        self.frameIndex = frameIndex
    }
}

/// `Sendable` snapshot of the court calibration the rally scorers need.
///
/// `CalibrationProfile` is a main-actor-isolated SwiftData `@Model`, so it can't
/// be captured by the `@Sendable` build closures that construct the scorers off
/// the main thread. This carries only the primitives the homography needs,
/// captured once on the main actor.
public struct RallyCalibration: Sendable {
    public let corners: [CGPoint]
    public let imageWidth: Double
    public let imageHeight: Double

    public init(corners: [CGPoint], imageWidth: Double, imageHeight: Double) {
        self.corners = corners
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }
}

/// Contract for shuttle detection implementations.
/// Conform to this protocol to provide real or placeholder shuttle detection
/// that plugs into HawkEyePipeline without pipeline changes.
public protocol ShuttleDetecting: Sendable {
    /// Detect shuttlecock positions in a real video frame.
    func detect(in pixelBuffer: CVPixelBuffer) async throws -> [ShuttleObservation]

    /// Convenience method for placeholder/simulation mode (no real frames).
    func detect(imageSize: CGSize, frameCount: Int) async throws -> [ShuttleObservation]

    /// Human-readable name for logging and diagnostics.
    var modelName: String { get }
}
