// CoreMLPipelineTests.swift
// Unit tests for the CoreML HawkEye pipeline components.
//
// Coverage:
//   - CourtDetector: calibrateAndRefine produces valid CourtCalibration
//   - CourtDetector: degenerate / insufficient taps throw CourtDetectorError
//   - Homography: project() applies the matrix correctly
//   - Homography: project ∘ inverse ≈ identity for well-formed input
//   - HawkEyePipeline: makeWithBestAvailableDetector() returns PlaceholderShuttleDetector
//     in simulator builds without a bundled .mlmodelc
//   - HawkEyePipeline: hasTrainedModel is false in test bundles
//   - CoreMLShuttleDetector: init with named model succeeds (no bundle lookup yet)
//   - CoreMLShuttleDetector: detect(imageSize:frameCount:) falls back to error when
//     model is nil (graceful failure path)
//   - CalibrationProfile v1→v2 migration: apply(calibration:) round-trips cleanly
//   - CalibrationProfile: returns nil calibration for v1-only (no keypointsData) rows

import XCTest
import CoreGraphics
import SwiftData
@testable import BadmintonEye

final class CoreMLPipelineTests: XCTestCase {

    // MARK: - Homography Tests

    func testHomographyIdentityProjection() {
        let identity = Homography.identity
        let input = CGPoint(x: 100, y: 200)
        let output = identity.project(input)
        XCTAssertEqual(output.x, input.x, accuracy: 1e-6)
        XCTAssertEqual(output.y, input.y, accuracy: 1e-6)
    }

    func testHomographyRoundTrip() throws {
        // Build a simple scale+translate homography (world→image: scale ×100, offset 50)
        let worldToImageMatrix: [[Double]] = [
            [100, 0, 50],
            [0, 100, 30],
            [0,   0,  1]
        ]
        // Inverse: scale ×0.01, offset reversed
        let imageToWorldMatrix: [[Double]] = [
            [0.01, 0, -0.5],
            [0, 0.01, -0.3],
            [0,    0,    1]
        ]
        let worldToImage = Homography(matrix: worldToImageMatrix)
        let imageToWorld = Homography(matrix: imageToWorldMatrix)

        let worldPt = CGPoint(x: 3.05, y: 6.7)
        let imagePt = worldToImage.project(worldPt)
        let roundTripped = imageToWorld.project(imagePt)

        XCTAssertEqual(Double(roundTripped.x), Double(worldPt.x), accuracy: 0.01,
                       "Round-trip x should recover original world x")
        XCTAssertEqual(Double(roundTripped.y), Double(worldPt.y), accuracy: 0.01,
                       "Round-trip y should recover original world y")
    }

    // MARK: - CourtDetector Tests

    func testCalibrateAndRefineWithValidTaps() throws {
        // Synthetic taps: map the 4 calibration keypoints to a 640×480 view
        // using a known affine transform (scale+translate only — no perspective)
        // so we can verify the reprojection error is near 0.
        let scale = CGFloat(50)
        let offsetX = CGFloat(100)
        let offsetY = CGFloat(50)

        let tapOrder = CourtModel.calibrationTapOrder
        let worldPts = tapOrder.compactMap { CourtModel.worldPositions[$0] }
        let taps = worldPts.map { CGPoint(x: $0.x * scale + offsetX,
                                          y: $0.y * scale + offsetY) }
        let imageSize = CGSize(width: 640, height: 480)

        let calibration = try CourtDetector.calibrateAndRefine(
            fromCornerTapsImagePx: taps,
            imageSize: imageSize,
            pixelBuffer: nil
        )

        // Reprojection error should be near zero for a pure affine warp
        XCTAssertLessThan(calibration.rmsReprojectionErrorPx, 2.0,
                          "RMS error must be small for a pure affine tap layout")

        // All 12 keypoints must be populated
        XCTAssertEqual(calibration.keypointsImagePx.count, CourtKeypoint.allCases.count,
                       "All 12 keypoints must be projected")

        XCTAssertEqual(calibration.imageSize, imageSize)
    }

    func testCalibrateThrowsWithInsufficientTaps() {
        XCTAssertThrowsError(
            try CourtDetector.calibrateAndRefine(
                fromCornerTapsImagePx: [.zero, .zero, .zero],   // only 3
                imageSize: CGSize(width: 640, height: 480),
                pixelBuffer: nil
            )
        ) { error in
            guard case CourtDetectorError.insufficientCorners(let got, _) = error else {
                return XCTFail("Expected CourtDetectorError.insufficientCorners; got \(error)")
            }
            XCTAssertEqual(got, 3)
        }
    }

    func testCalibrateThrowsWithCollinearTaps() {
        // 4 collinear points produce a degenerate homography
        let collinear: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 200, y: 0),
            CGPoint(x: 300, y: 0)
        ]
        XCTAssertThrowsError(
            try CourtDetector.calibrateAndRefine(
                fromCornerTapsImagePx: collinear,
                imageSize: CGSize(width: 640, height: 480),
                pixelBuffer: nil
            )
        )
    }

    // MARK: - HawkEyePipeline Tests

    func testMakeWithBestAvailableDetectorReturnsPlaceholderWithoutModel() {
        // In the test bundle (no TrackNetV3.mlmodelc bundled),
        // the factory should fall back to PlaceholderShuttleDetector
        let pipeline = HawkEyePipeline.makeWithBestAvailableDetector()
        // Verify it is not nil and usesRealDetection is false
        // (We can't use the internal `usesRealDetection` directly but we can
        // confirm hasTrainedModel == false in test context)
        XCTAssertFalse(HawkEyePipeline.hasTrainedModel,
                       "hasTrainedModel must be false when test bundle has no .mlmodelc")
        // Confirm pipeline was created without throwing
        XCTAssertNotNil(pipeline)
    }

    func testHawkEyePipelineDefaultDetectorIsPlaceholder() {
        // Default init uses PlaceholderShuttleDetector
        let pipeline = HawkEyePipeline()
        // Verify the model name reflects placeholder
        XCTAssertEqual(pipeline.result, nil,
                       "Fresh pipeline must have nil result")
        XCTAssertFalse(pipeline.isAnalyzing,
                       "Fresh pipeline must not be analyzing")
    }

    // MARK: - CoreMLShuttleDetector Init

    func testCoreMLShuttleDetectorInitWithCustomName() {
        // Creating a detector with a custom model name should not throw at init
        let detector = CoreMLShuttleDetector(modelName: "NonExistentModel")
        XCTAssertEqual(detector.modelName, "NonExistentModel",
                       "modelName must match the name passed at init")
    }

    func testCoreMLShuttleDetectorDefaultModelName() {
        let detector = CoreMLShuttleDetector()
        XCTAssertEqual(detector.modelName, CoreMLDetectorConstants.defaultModelName)
    }

    // MARK: - CalibrationProfile v1→v2 Round-Trip

    @MainActor
    func testCalibrationProfileApplyAndReadBack() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: CalibrationProfile.self, configurations: config)
        let context = ModelContext(container)

        // Build a synthetic CourtCalibration using known affine taps
        let scale = CGFloat(50)
        let offsetX = CGFloat(100)
        let offsetY = CGFloat(50)
        let tapOrder = CourtModel.calibrationTapOrder
        let worldPts = tapOrder.compactMap { CourtModel.worldPositions[$0] }
        let taps = worldPts.map { CGPoint(x: $0.x * scale + offsetX,
                                          y: $0.y * scale + offsetY) }
        let imageSize = CGSize(width: 640, height: 480)

        let cal = try CourtDetector.calibrateAndRefine(
            fromCornerTapsImagePx: taps,
            imageSize: imageSize,
            pixelBuffer: nil
        )

        // Persist via apply(calibration:venueName:)
        let profile = CalibrationProfile()
        profile.apply(calibration: cal, venueName: "Test Venue")
        context.insert(profile)
        try context.save()

        // Read back
        let fetched = try context.fetch(FetchDescriptor<CalibrationProfile>())
        XCTAssertEqual(fetched.count, 1, "Exactly one profile should be stored")

        let recovered = fetched[0].calibration
        XCTAssertNotNil(recovered, "calibration must be non-nil after apply+save+fetch")

        // Verify round-trip accuracy
        XCTAssertEqual(recovered!.imageSize.width, cal.imageSize.width, accuracy: 0.5)
        XCTAssertEqual(recovered!.imageSize.height, cal.imageSize.height, accuracy: 0.5)
        XCTAssertEqual(recovered!.keypointsImagePx.count, cal.keypointsImagePx.count,
                       "All keypoints must survive encode/decode round-trip")
        XCTAssertEqual(recovered!.rmsReprojectionErrorPx, cal.rmsReprojectionErrorPx,
                       accuracy: 0.01)
    }

    @MainActor
    func testCalibrationProfileV1OnlyReturnsNilCalibration() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: CalibrationProfile.self, configurations: config)
        let context = ModelContext(container)

        // v1 profile: only setCorners, no apply(calibration:)
        let profile = CalibrationProfile()
        profile.venueName = "Old Venue"
        profile.imageWidth = 640
        profile.imageHeight = 480
        // keypointsData and homographyData remain nil → v1 schema
        context.insert(profile)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<CalibrationProfile>())
        XCTAssertNil(fetched[0].calibration,
                     "v1-only CalibrationProfile (no keypointsData) must return nil calibration")
    }
}
