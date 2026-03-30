@preconcurrency import AVFoundation
import CoreMedia
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

    // MARK: - Constants

    /// Process every 4th frame at 240fps = 60 detections/sec.
    static let frameSkipInterval = 4

    /// Cap total frames analyzed to prevent runaway analysis.
    static let maxAnalysisFrames = 150

    // MARK: - Private

    private let calculator = TrajectoryCalculator()
    private let detector: ShuttleDetecting

    /// Whether the injected detector supports real frame analysis.
    private var usesRealDetection: Bool {
        !(detector is PlaceholderShuttleDetector)
    }

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

        // Branch: real frame extraction or placeholder simulation
        let imagePositions: [CGPoint]
        let detectionCount: Int

        if usesRealDetection {
            // Real-frame analysis path (no artificial delays)
            let observations: [ShuttleObservation]
            do {
                observations = try await analyzeWithRealFrames(
                    videoURL: videoURL,
                    homography: homography,
                    imageSize: imageSize
                )
            } catch {
                errorMessage = "Shuttle detection failed: \(error.localizedDescription)"
                isAnalyzing = false
                return
            }

            // Vision returns normalized 0-1 coords; scale to image-space for homography
            imagePositions = observations.map { obs in
                CGPoint(
                    x: obs.position.x * imageSize.width,
                    y: obs.position.y * imageSize.height
                )
            }
            detectionCount = observations.count
            progress = 0.7
        } else {
            // Placeholder path (preserved exactly as original)

            // Artificial delay to match user expectation (3-5 seconds total analysis)
            try? await Task.sleep(for: .seconds(1.0))

            // Simulate frame extraction progress
            let frameCount = Int(videoDuration * 10) // 0.1s intervals
            let actualFrames = min(frameCount, 100)

            for i in 0..<actualFrames {
                progress = 0.2 + 0.4 * (Double(i + 1) / Double(actualFrames))
                if i % 10 == 0 {
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }

            // Shuttle detection (via injected ShuttleDetecting conformance)
            let placeholderDetectionCount = Int.random(in: 8...15)
            let observations: [ShuttleObservation]
            do {
                observations = try await detector.detect(
                    imageSize: imageSize,
                    frameCount: placeholderDetectionCount
                )
            } catch {
                errorMessage = "Shuttle detection failed: \(error.localizedDescription)"
                isAnalyzing = false
                return
            }
            imagePositions = observations.map { $0.position }
            detectionCount = placeholderDetectionCount

            progress = 0.7
            try? await Task.sleep(for: .seconds(1.0))
        }

        // Step 5: Transform image positions to court coordinates
        let courtPositions = imagePositions.map { point in
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

    // MARK: - Real Frame Analysis

    /// Extracts video frames via AVAssetReader and runs the detector on every Nth frame.
    /// At 240fps with frameSkipInterval=4, this yields ~60 detections/sec.
    private func analyzeWithRealFrames(
        videoURL: URL,
        homography: [[Double]],
        imageSize: CGSize
    ) async throws -> [ShuttleObservation] {
        let asset = AVURLAsset(url: videoURL)

        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(
                domain: "HawkEyePipeline",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No video track found"]
            )
        }

        let nominalFPS = try await Double(track.load(.nominalFrameRate))

        // Use frame skip for high-FPS video; process every frame for low FPS
        let effectiveSkipInterval = nominalFPS >= 120 ? Self.frameSkipInterval : 1

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()

        var allObservations = [ShuttleObservation]()
        var frameIndex = 0
        var processedCount = 0

        while let sampleBuffer = output.copyNextSampleBuffer(),
              processedCount < Self.maxAnalysisFrames {

            frameIndex += 1

            // Skip frames according to interval
            if frameIndex % effectiveSkipInterval != 0 {
                continue
            }

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                continue
            }

            do {
                let detections = try await detector.detect(in: pixelBuffer)
                // Update each observation with the correct frame index
                let indexed = detections.map { obs in
                    ShuttleObservation(
                        position: obs.position,
                        confidence: obs.confidence,
                        frameIndex: frameIndex
                    )
                }
                allObservations.append(contentsOf: indexed)
            } catch {
                // Skip frames that fail detection; continue processing
                continue
            }

            processedCount += 1
            await MainActor.run {
                self.progress = 0.2 + 0.5 * (Double(processedCount) / Double(Self.maxAnalysisFrames))
            }
        }

        return allObservations
    }

}
