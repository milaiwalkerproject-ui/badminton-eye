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
    private let detector: ShuttleDetecting

    // MARK: - Init

    /// Creates a pipeline with the given shuttle detector.
    /// Defaults to PlaceholderShuttleDetector for development and UI testing.
    init(detector: ShuttleDetecting = PlaceholderShuttleDetector()) {
        self.detector = detector
    }

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

        // Step 4: Shuttle detection (via injected ShuttleDetecting conformance)
        let detectionCount = Int.random(in: 8...15)
        let observations: [ShuttleObservation]
        do {
            observations = try await detector.detect(imageSize: imageSize, frameCount: detectionCount)
        } catch {
            errorMessage = "Shuttle detection failed: \(error.localizedDescription)"
            isAnalyzing = false
            return
        }
        let simulatedImagePositions = observations.map { $0.position }

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

}
