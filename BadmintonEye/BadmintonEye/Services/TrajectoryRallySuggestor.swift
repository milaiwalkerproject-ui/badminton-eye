@preconcurrency import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import ScoringEngine

// MARK: - TrajectoryRallySuggestor

/// Phase D — real `RallySuggesting` implementation backed by the live capture
/// pipeline.
///
/// On `suggest()` it:
///   1. Snapshots the most recent ~2s of frames from the shared
///      `CircularFrameBuffer` fed by `GameRecordingService`.
///   2. Runs the injected `ShuttleDetecting` model across those frames to
///      gather image-space shuttle positions.
///   3. Feeds the positions through `TrajectoryCalculator` to recover a
///      smooth trajectory and a court-space landing point (via the
///      homography defined by `CalibrationProfile`).
///   4. Decides the winning side from the landing's court-space `y`
///      (≥ 0.5 → far side = `.sideA`; < 0.5 → near side = `.sideB`).
///   5. Combines three signals into a confidence in `[0, 1]`:
///        a) detection count (capped at 12 — the per-frame detector returns
///           ≤ 1 point per frame, so ~2s @ 6+ fps is "plenty")
///        b) trajectory tightness — RMS residual of detected points
///           against the fitted parabola in court-space; tight fit raises
///           confidence
///        c) distance of the landing from the net centerline (`y = 0.5`),
///           scaled so landings on the net itself yield ~0 confidence
///      Equal weights, then clamped to `[0, 1]`.
///
/// Fallback: if calibration is missing, the frame buffer has nothing, or
/// the detector returns < 2 usable points, the suggestor returns a
/// coin-flip side with `confidence` capped at 0.50 so the UI never
/// degrades to "nothing happened". This matches `StubRallySuggestor`'s
/// shape so the sheet still progresses on-device while the model warms up.
///
/// All inputs are passed in — the suggestor never creates a capture
/// session, never loads a second copy of the detector, and never mutates
/// the buffer (uses `recentFrames(seconds:)`).
final class TrajectoryRallySuggestor: RallySuggesting, @unchecked Sendable {

    // MARK: - Tunables

    /// Recent-frame window. ~2 s of capture is enough for a parabolic
    /// landing fit while staying small enough to keep inference under
    /// ~1 s on-device.
    private let windowSeconds: TimeInterval = 2.0

    /// Stride across the snapshotted frames so we don't burn cycles on
    /// 30 inferences per rally. Keeps total ML work bounded.
    private let frameStride: Int = 2

    /// Hard cap on frames sent to the detector per suggestion.
    private let maxFramesPerSuggestion: Int = 16

    /// Confidence-formula caps.
    private let countCap: Double = 12.0       // detections needed for full count score
    private let residualScale: Double = 0.08  // court-units; residuals beyond this → 0
    private let nearNetScale: Double = 0.25   // |y - 0.5| where landing is fully "clear of net"

    // MARK: - Dependencies

    private let frameBuffer: CircularFrameBuffer
    private let detector: ShuttleDetecting
    private let calibration: CalibrationProfile?
    private let calculator = TrajectoryCalculator()

    // MARK: - Init

    init(
        frameBuffer: CircularFrameBuffer,
        detector: ShuttleDetecting,
        calibration: CalibrationProfile?
    ) {
        self.frameBuffer = frameBuffer
        self.detector = detector
        self.calibration = calibration
    }

    // MARK: - RallySuggesting

    func suggest() async -> RallySuggestion {
        // Pull a snapshot of calibration state up front. `CalibrationProfile`
        // is a SwiftData model (@MainActor by convention); snapshot the
        // values we need into Sendable primitives so the rest of the work
        // can run off the main actor safely.
        let calibrationSnapshot = await snapshotCalibration()
        let sampleBuffers = frameBuffer.recentFrames(seconds: windowSeconds)

        guard
            let snapshot = calibrationSnapshot,
            !sampleBuffers.isEmpty
        else {
            return coinFlipFallback()
        }

        // Decimate to bounded set
        let strided = stride(
            from: 0,
            to: sampleBuffers.count,
            by: max(frameStride, 1)
        ).map { sampleBuffers[$0] }
        let frames = Array(strided.suffix(maxFramesPerSuggestion))

        // Detect shuttle positions across the window
        var imagePoints: [CGPoint] = []
        for (idx, sb) in frames.enumerated() {
            guard let pb = CMSampleBufferGetImageBuffer(sb) else { continue }
            do {
                let obs = try await detector.detect(in: pb)
                if let best = obs.max(by: { $0.confidence < $1.confidence }) {
                    // Normalize detector output into image-pixel space using
                    // the calibration capture dimensions. Vision/CoreML give
                    // points in normalized [0,1]; the homography expects
                    // pixel coordinates from the same frame the calibration
                    // corners were tapped in.
                    let px = CGPoint(
                        x: best.position.x * CGFloat(snapshot.imageWidth),
                        y: best.position.y * CGFloat(snapshot.imageHeight)
                    )
                    imagePoints.append(px)
                }
                _ = idx
            } catch {
                continue
            }
        }

        guard imagePoints.count >= 2 else {
            return coinFlipFallback()
        }

        // Image → court space via the calibrated homography
        let homography = calculator.computeHomography(
            imageCorners: snapshot.corners,
            imageSize: CGSize(width: snapshot.imageWidth, height: snapshot.imageHeight)
        )
        let courtPoints = imagePoints.map { calculator.transformPoint($0, using: homography) }

        // Fit + extrapolate landing
        let (trajectory, landing) = calculator.fitTrajectory(courtPoints)
        _ = trajectory  // not needed for the suggestion, but the calculator returns it

        // Side mapping: calibration corners are TL, TR, BL, BR.
        // TrajectoryCalculator maps TL→(0,0), TR→(1,0), BL→(0,1), BR→(1,1).
        // In a typical user setup the top of the image is the far baseline
        // (opposite court half) and the bottom is the near baseline. We
        // therefore map court-y < 0.5 → far side → `.sideA`,
        // court-y >= 0.5 → near side → `.sideB`. If the orientation is
        // ever flipped, only this mapping needs to change.
        let side: Side = landing.y < 0.5 ? .sideA : .sideB

        // Confidence
        let confidence = confidence(
            detectionCount: imagePoints.count,
            courtPoints: courtPoints,
            landing: landing
        )

        return RallySuggestion(side: side, confidence: confidence)
    }

    // MARK: - Confidence

    /// Equal-weight combination of three signals — see file-level docstring.
    private func confidence(
        detectionCount: Int,
        courtPoints: [CourtPoint],
        landing: CourtPoint
    ) -> Double {
        let countScore = min(1.0, Double(detectionCount) / countCap)

        let residual = rmsResidual(points: courtPoints)
        // tight fit (small residual) → high score
        let residualScore = max(0.0, 1.0 - residual / residualScale)

        // Distance from net centerline (y = 0.5). Landings sitting right
        // on the net are ambiguous; far from the net they are unambiguous.
        let netDistance = abs(landing.y - 0.5)
        let netScore = min(1.0, netDistance / nearNetScale)

        let combined = (countScore + residualScore + netScore) / 3.0
        return max(0.0, min(1.0, combined))
    }

    /// `TrajectoryCalculator` doesn't currently expose its quadratic fit
    /// residual, so we recompute a simple RMS distance between each input
    /// point and its closest neighbor on the generated trajectory. Cheap
    /// and good enough as a "how parabolic was this really?" proxy.
    private func rmsResidual(points: [CourtPoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        let (trajectory, _) = calculator.fitTrajectory(points)
        guard !trajectory.isEmpty else { return 0 }

        var sumSq = 0.0
        for p in points {
            var best = Double.greatestFiniteMagnitude
            for t in trajectory {
                let dx = p.x - t.x
                let dy = p.y - t.y
                let d2 = dx * dx + dy * dy
                if d2 < best { best = d2 }
            }
            sumSq += best
        }
        return (sumSq / Double(points.count)).squareRoot()
    }

    // MARK: - Fallback

    /// Returned when calibration is missing, no frames are buffered, or
    /// the detector failed to localize the shuttle. Mirrors the UX of
    /// `StubRallySuggestor` but caps confidence so the badge tells the
    /// user we weren't sure.
    private func coinFlipFallback() -> RallySuggestion {
        let side: Side = Bool.random() ? .sideA : .sideB
        let confidence = min(0.50, Double.random(in: 0.30...0.50))
        return RallySuggestion(side: side, confidence: confidence)
    }

    // MARK: - Calibration snapshot

    /// Sendable snapshot of the calibration profile so the suggestor's
    /// async work can leave the main actor safely.
    private struct CalibrationSnapshot: Sendable {
        let corners: [CGPoint]
        let imageWidth: Double
        let imageHeight: Double
    }

    private func snapshotCalibration() async -> CalibrationSnapshot? {
        guard let calibration else { return nil }
        return await MainActor.run {
            guard
                let corners = calibration.corners,
                calibration.imageWidth > 0,
                calibration.imageHeight > 0
            else { return nil as CalibrationSnapshot? }
            return CalibrationSnapshot(
                corners: corners,
                imageWidth: calibration.imageWidth,
                imageHeight: calibration.imageHeight
            )
        }
    }
}
