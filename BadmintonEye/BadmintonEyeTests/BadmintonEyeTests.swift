// BadmintonEyeTests.swift
// Unit tests for the BadmintonEye iOS app.
// Runs via TEST_HOST injection so @testable import BadmintonEye exposes internals.
//
// Coverage targets:
//   - ResultFusionService.fuse()  — verifies PR #6 guard path + weighted fusion logic
//   - SyncPayload.from(dictionary:) — verifies defensive decoding (PR #5 safe encoder guard)

import XCTest
@testable import BadmintonEye

// MARK: - ResultFusionService

final class ResultFusionServiceTests: XCTestCase {

    // MARK: Guard paths (PR #6 regression coverage)

    func testFuseEmptyArrayReturnsNil() {
        // Before PR #6, fuse([]) triggered fatalError. Now it returns nil.
        XCTAssertNil(ResultFusionService.fuse([]),
                     "fuse([]) must return nil — guard replaced fatalError in PR #6")
    }

    func testFuseSingleResultReturnsThatResult() throws {
        let r = makeResult(confidence: 0.75, x: 0.3, y: 0.6)
        let fused = try XCTUnwrap(ResultFusionService.fuse([r]),
                                   "fuse of a single result must return that result")
        XCTAssertEqual(fused.confidence, 0.75, accuracy: 0.001)
        XCTAssertEqual(fused.landingPoint.x, 0.3, accuracy: 0.001)
        XCTAssertEqual(fused.landingPoint.y, 0.6, accuracy: 0.001)
    }

    // MARK: Weighted-average landing point

    func testFuseTwoResultsProducesWeightedLandingPoint() throws {
        // confidence 0.6 and 0.4 → total 1.0
        let r1 = makeResult(confidence: 0.6, x: 0.4, y: 0.3)
        let r2 = makeResult(confidence: 0.4, x: 0.6, y: 0.5)
        let fused = try XCTUnwrap(ResultFusionService.fuse([r1, r2]))
        // Weighted X: 0.4*(0.6/1.0) + 0.6*(0.4/1.0) = 0.48
        XCTAssertEqual(fused.landingPoint.x, 0.48, accuracy: 0.001)
        // Weighted Y: 0.3*(0.6/1.0) + 0.5*(0.4/1.0) = 0.38
        XCTAssertEqual(fused.landingPoint.y, 0.38, accuracy: 0.001)
    }

    // MARK: Confidence boost and cap

    func testFusedConfidenceIsCapAt99Percent() throws {
        let r1 = makeResult(confidence: 0.95)
        let r2 = makeResult(confidence: 0.90)
        let fused = try XCTUnwrap(ResultFusionService.fuse([r1, r2]))
        XCTAssertLessThanOrEqual(fused.confidence, 0.99,
                                  "fused confidence must be capped at 0.99")
    }

    func testFusedConfidenceExceedsMaxInput() throws {
        let r1 = makeResult(confidence: 0.60)
        let r2 = makeResult(confidence: 0.55)
        let fused = try XCTUnwrap(ResultFusionService.fuse([r1, r2]))
        // 15% boost: max(0.60) * 1.15 = 0.69
        XCTAssertGreaterThan(fused.confidence, 0.60,
                              "multi-angle fusion should boost confidence above the max input")
    }

    // MARK: Trajectory merge

    func testFusedTrajectoryMergesAllAngles() throws {
        let pt1 = CourtPoint(x: 0.1, y: 0.2)
        let pt2 = CourtPoint(x: 0.5, y: 0.6)
        let r1 = HawkEyeResult(
            trajectoryPoints: [pt1],
            landingPoint: CourtPoint(x: 0.5, y: 0.5),
            landingResult: .inBounds, confidence: 0.8, marginFromLine: 0.1)
        let r2 = HawkEyeResult(
            trajectoryPoints: [pt2],
            landingPoint: CourtPoint(x: 0.5, y: 0.5),
            landingResult: .inBounds, confidence: 0.7, marginFromLine: 0.1)
        let fused = try XCTUnwrap(ResultFusionService.fuse([r1, r2]))
        XCTAssertEqual(fused.trajectoryPoints.count, 2,
                        "trajectory points from all angles should be merged")
    }

    // MARK: - Helpers

    private func makeResult(
        confidence: Double,
        x: Double = 0.5,
        y: Double = 0.5,
        landing: LandingResult = .inBounds
    ) -> HawkEyeResult {
        HawkEyeResult(
            trajectoryPoints: [],
            landingPoint: CourtPoint(x: x, y: y),
            landingResult: landing,
            confidence: confidence,
            marginFromLine: 0.05
        )
    }
}

// MARK: - SyncPayload

final class SyncPayloadTests: XCTestCase {

    func testFromEmptyDictionaryReturnsNil() {
        XCTAssertNil(SyncPayload.from(dictionary: [:]),
                      "SyncPayload.from must return nil for an empty dictionary")
    }

    func testFromDictionaryWithWrongTypeReturnsNil() {
        // "syncPayload" key exists but value is a String, not Data
        XCTAssertNil(SyncPayload.from(dictionary: ["syncPayload": "not-data"]),
                      "SyncPayload.from must return nil when syncPayload value is not Data")
    }

    func testFromDictionaryWithCorruptDataReturnsNil() {
        let garbage = Data([0xFF, 0xFE, 0x00])
        XCTAssertNil(SyncPayload.from(dictionary: ["syncPayload": garbage]),
                      "SyncPayload.from must return nil for corrupt JSON data")
    }
}
