import CoreVideo
import Foundation
import Vision

// MARK: - VisionCourtDetector

/// On-device court detector built on Vision's built-in rectangle detector.
///
/// Finds the strongest court-shaped quadrilateral in a frame and returns its
/// corners in capture-device space (normalized, top-left origin), ordered
/// `[TL, TR, BR, BL]`.
///
/// Needs **no model file and no network** — `VNDetectRectanglesRequest` is a
/// built-in Vision algorithm, so this works on any device (and in the
/// simulator / previews). The badminton court boundary is a high-contrast
/// rectangle, which is exactly what this request is designed to find; we lean
/// on area + confidence (not a tight aspect ratio) to pick it out, because
/// perspective skews the on-image rectangle heavily.
final class VisionCourtDetector: CourtDetecting, @unchecked Sendable {

    // MARK: - Tunables

    /// Minimum Vision confidence for a candidate rectangle.
    private let minimumConfidence: VNConfidence = 0.4
    /// Very permissive aspect ratio — a court seen in perspective can look
    /// anywhere from near-square to very wide.
    private let minimumAspectRatio: VNAspectRatio = 0.2
    /// The court should fill a meaningful fraction of the frame.
    private let minimumSize: Float = 0.2
    /// Allow substantial deviation from 90° corners (perspective).
    private let quadratureTolerance: VNDegrees = 35
    private let maximumObservations = 10

    /// Selection floor on the normalized quad area (rejects slivers / distant
    /// adjacent-court rectangles).
    private let minNormalizedArea: Double = 0.06

    // MARK: - CourtDetecting

    func detectCourt(in pixelBuffer: CVPixelBuffer) async -> DetectedCourt? {
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = minimumConfidence
        request.minimumAspectRatio = minimumAspectRatio
        request.maximumObservations = maximumObservations
        request.minimumSize = minimumSize
        request.quadratureTolerance = quadratureTolerance

        // Match CoreMLShuttleDetector: run on the raw buffer (sensor space)
        // with no explicit orientation. The preview layer's
        // `layerPointConverted(fromCaptureDevicePoint:)` maps the resulting
        // capture-device points into the rotated, gravity-filled view for us.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results as? [VNRectangleObservation] else {
            return nil
        }

        let candidates: [DetectedCourt] = observations.compactMap { obs in
            // Vision corners are normalized with a BOTTOM-left origin. Flip to
            // top-left, then re-derive a canonical [TL, TR, BR, BL] ordering
            // (don't trust Vision's own corner labels under perspective).
            let raw = [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft]
                .map(CourtGeometry.topLeftOrigin)
            guard let ordered = CourtGeometry.orderedClockwise(raw) else { return nil }
            return DetectedCourt(corners: ordered, confidence: Double(obs.confidence))
        }

        return CourtGeometry.bestCandidate(
            candidates,
            minConfidence: Double(minimumConfidence),
            minArea: minNormalizedArea
        )
    }
}
