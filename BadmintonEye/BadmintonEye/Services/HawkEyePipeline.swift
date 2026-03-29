@preconcurrency import AVFoundation
import Foundation

/// Orchestrates video analysis: frame extraction, shuttle detection (placeholder),
/// and trajectory computation for Hawk Eye challenge replays.
@Observable
final class HawkEyePipeline: @unchecked Sendable {

    // MARK: - Published State

    var isAnalyzing: Bool = false
    var progress: Double = 0.0
    var result: HawkEyeResult?
    var errorMessage: String?

    // MARK: - Private

    private let calculator = TrajectoryCalculator()

    // MARK: - Analysis

    /// Runs the full Hawk Eye analysis pipeline on a captured video.
    /// Uses placeholder shuttle detection for v1 with simulated positions.
    @MainActor
    func analyze(videoURL: URL, calibration: CalibrationProfile) async {
        isAnalyzing = true
        progress = 0.0
        result = nil
        errorMessage = nil

        // Validate calibration
        guard let corners = calibration.corners, corners.count == 4 else {
            errorMessage = "Court calibration is missing or incomplete. Please calibrate first."
            isAnalyzing = false
            return
        }

        let imageSize = CGSize(width: calibration.imageWidth, height: calibration.imageHeight)

        // Step 1: Compute homography from calibration corners
        let homography = calculator.computeHomography(imageCorners: corners, imageSize: imageSize)
        progress = 0.1

        // Step 2: Extract video metadata for realistic simulation
        let asset = AVURLAsset(url: videoURL)
        var videoDuration: Double
        var videoFPS: Double

        do {
            let duration = try await asset.load(.duration)
            videoDuration = min(CMTimeGetSeconds(duration), 10.0)

            let tracks = try await asset.loadTracks(withMediaType: .video)
            if let track = tracks.first {
                let rate = try await track.load(.nominalFrameRate)
                videoFPS = Double(rate)
            } else {
                videoFPS = 30.0
            }
        } catch {
            videoDuration = 3.0
            videoFPS = 30.0
        }

        progress = 0.2

        // Artificial delay to match user expectation (3-5 seconds total analysis)
        try? await Task.sleep(for: .seconds(1.0))

        // Step 3: Simulate frame extraction progress
        let frameCount = Int(videoDuration * 10) // 0.1s intervals
        let actualFrames = min(frameCount, 100)

        for i in 0..<actualFrames {
            progress = 0.2 + 0.4 * (Double(i + 1) / Double(actualFrames))
            if i % 10 == 0 {
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        // Step 4: Placeholder shuttle detection
        // TODO: Replace with real Core ML shuttle detection model (YOLO26 nano)
        // Placeholder generates realistic trajectory for UI development and user testing
        let detectionCount = Int.random(in: 8...15)
        let simulatedImagePositions = generatePlaceholderPositions(
            count: detectionCount,
            imageSize: imageSize
        )

        progress = 0.7
        try? await Task.sleep(for: .seconds(1.0))

        // Step 5: Transform image positions to court coordinates
        let courtPositions = simulatedImagePositions.map { point in
            calculator.transformPoint(point, using: homography)
        }

        progress = 0.8

        // Step 6: Fit trajectory and determine landing
        let (trajectory, landing) = calculator.fitTrajectory(courtPositions)
        let (landingResult, margin) = calculator.determineLanding(landing)

        progress = 0.9
        try? await Task.sleep(for: .seconds(0.5))

        // Step 7: Compute confidence
        let confidence = calculator.computeConfidence(
            detectionCount: detectionCount,
            videoFPS: videoFPS,
            margin: margin
        )

        // Build result
        let hawkEyeResult = HawkEyeResult(
            trajectoryPoints: trajectory,
            landingPoint: landing,
            landingResult: landingResult,
            confidence: confidence,
            marginFromLine: margin
        )

        result = hawkEyeResult
        progress = 1.0
        isAnalyzing = false
    }

    // MARK: - Placeholder Detection

    /// Generates simulated shuttle positions along a realistic parabolic arc.
    /// Starts from one side of the court, arcs upward, then descends toward the opposite side.
    /// Adds small random noise (+-5 pixels) for realism.
    private func generatePlaceholderPositions(count: Int, imageSize: CGSize) -> [CGPoint] {
        let w = imageSize.width
        let h = imageSize.height

        // Shuttle travels from bottom-left area to top-right area of image
        let startX = w * 0.2
        let endX = w * 0.75
        let startY = h * 0.8
        let endY = h * 0.3

        var positions = [CGPoint]()

        for i in 0..<count {
            let t = Double(i) / Double(count - 1)

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

            positions.append(CGPoint(x: x + noiseX, y: y + noiseY))
        }

        return positions
    }
}
