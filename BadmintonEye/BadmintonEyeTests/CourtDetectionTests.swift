// CourtDetectionTests.swift
// Unit tests for the pure court-detection geometry (CourtGeometry) and the
// detector seam (CourtDetecting / PlaceholderCourtDetector). The Vision-backed
// VisionCourtDetector is not exercised here — it needs real images — but every
// coordinate transform and selection rule it relies on lives in CourtGeometry
// and is verified below.

import XCTest
import CoreGraphics
import CoreVideo
@testable import BadmintonEye

final class CourtDetectionTests: XCTestCase {

    private func assertPointsEqual(_ a: [CGPoint], _ b: [CGPoint],
                                   accuracy: CGFloat = 1e-6,
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.count, b.count, "point count", file: file, line: line)
        for (p, q) in zip(a, b) {
            XCTAssertEqual(p.x, q.x, accuracy: accuracy, file: file, line: line)
            XCTAssertEqual(p.y, q.y, accuracy: accuracy, file: file, line: line)
        }
    }

    // MARK: - topLeftOrigin

    func testTopLeftOriginFlipsYOnly() {
        let p = CourtGeometry.topLeftOrigin(CGPoint(x: 0.3, y: 0.2))
        XCTAssertEqual(p.x, 0.3, accuracy: 1e-9)
        XCTAssertEqual(p.y, 0.8, accuracy: 1e-9)
        // Round trip is an involution.
        let back = CourtGeometry.topLeftOrigin(p)
        XCTAssertEqual(back.x, 0.3, accuracy: 1e-9)
        XCTAssertEqual(back.y, 0.2, accuracy: 1e-9)
    }

    // MARK: - orderedClockwise

    func testOrderedClockwiseRecoversTLTRBRBL_fromAnyInputOrder() {
        let tl = CGPoint(x: 0.10, y: 0.10)
        let tr = CGPoint(x: 0.90, y: 0.12)
        let br = CGPoint(x: 0.92, y: 0.88)
        let bl = CGPoint(x: 0.08, y: 0.90)

        for scrambled in [[br, tl, bl, tr], [tr, br, bl, tl], [bl, tr, tl, br]] {
            let ordered = CourtGeometry.orderedClockwise(scrambled)
            XCTAssertNotNil(ordered)
            assertPointsEqual(ordered!, [tl, tr, br, bl])
        }
    }

    func testOrderedClockwiseHandlesPerspectiveSkew() {
        // A keystoned court (far baseline narrower than near) still orders right.
        let tl = CGPoint(x: 0.35, y: 0.20)
        let tr = CGPoint(x: 0.65, y: 0.20)
        let br = CGPoint(x: 0.95, y: 0.85)
        let bl = CGPoint(x: 0.05, y: 0.85)
        let ordered = CourtGeometry.orderedClockwise([tr, bl, br, tl])
        assertPointsEqual(ordered ?? [], [tl, tr, br, bl])
    }

    func testOrderedClockwiseRejectsWrongCount() {
        XCTAssertNil(CourtGeometry.orderedClockwise([]))
        XCTAssertNil(CourtGeometry.orderedClockwise([CGPoint(x: 0, y: 0)]))
        XCTAssertNil(CourtGeometry.orderedClockwise(Array(repeating: CGPoint(x: 0.5, y: 0.5), count: 5)))
    }

    func testOrderedClockwiseRejectsDegenerateDuplicate() {
        let p = CGPoint(x: 0.5, y: 0.5)
        XCTAssertNil(CourtGeometry.orderedClockwise([p, p, CGPoint(x: 0.9, y: 0.1), CGPoint(x: 0.1, y: 0.9)]))
    }

    func testOrderedClockwiseRecanonicalizesAfterQuarterTurn() {
        // Sensor→screen regression: the portrait preview rotates the buffer 90°,
        // which preserves clockwise order but shifts which physical corner is
        // top-left. Ordering done in sensor space is therefore stale after the
        // conversion — re-running orderedClockwise on the rotated points must
        // restore [TL, TR, BR, BL] in the rotated (screen) space.
        let sensorTL = CGPoint(x: 0.20, y: 0.30)
        let sensorTR = CGPoint(x: 0.80, y: 0.25)
        let sensorBR = CGPoint(x: 0.85, y: 0.70)
        let sensorBL = CGPoint(x: 0.15, y: 0.75)
        // 90° clockwise rotation in a top-left-origin unit square: (x, y) → (1 − y, x).
        let rotate = { (p: CGPoint) in CGPoint(x: 1 - p.y, y: p.x) }
        let rotatedInSensorOrder = [sensorTL, sensorTR, sensorBR, sensorBL].map(rotate)

        // The sensor ordering no longer starts at the rotated-space top-left…
        XCTAssertNotEqual(rotatedInSensorOrder.first, rotate(sensorBL))
        // …but re-canonicalizing recovers it: sensor BL becomes screen TL, etc.
        let reordered = CourtGeometry.orderedClockwise(rotatedInSensorOrder)
        assertPointsEqual(reordered ?? [],
                          [rotate(sensorBL), rotate(sensorTL), rotate(sensorTR), rotate(sensorBR)])
    }

    // MARK: - quadArea

    func testQuadAreaUnitSquare() {
        let square = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                      CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        XCTAssertEqual(CourtGeometry.quadArea(square), 1.0, accuracy: 1e-9)
    }

    func testQuadAreaIsWindingIndependent() {
        let cw  = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                   CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        let ccw = Array(cw.reversed())
        XCTAssertEqual(CourtGeometry.quadArea(cw), CourtGeometry.quadArea(ccw), accuracy: 1e-9)
    }

    // MARK: - bestCandidate

    private func court(_ conf: Double, area side: CGFloat) -> DetectedCourt {
        DetectedCourt(
            corners: [CGPoint(x: 0, y: 0), CGPoint(x: side, y: 0),
                      CGPoint(x: side, y: side), CGPoint(x: 0, y: side)],
            confidence: conf
        )
    }

    func testBestCandidatePicksHighestConfidence() {
        let low = court(0.5, area: 0.9)
        let high = court(0.8, area: 0.9)
        let best = CourtGeometry.bestCandidate([low, high], minConfidence: 0.4, minArea: 0.05)
        XCTAssertEqual(best, high)
    }

    func testBestCandidateTieBreaksByLargerArea() {
        let small = court(0.7, area: 0.3) // area 0.09
        let big = court(0.7, area: 0.8)   // area 0.64
        let best = CourtGeometry.bestCandidate([small, big], minConfidence: 0.4, minArea: 0.05)
        XCTAssertEqual(best, big)
    }

    func testBestCandidateFiltersBelowThresholds() {
        let lowConf = court(0.2, area: 0.9)
        let tiny = court(0.9, area: 0.1) // area 0.01 < minArea
        XCTAssertNil(CourtGeometry.bestCandidate([lowConf, tiny], minConfidence: 0.4, minArea: 0.05))
        XCTAssertNil(CourtGeometry.bestCandidate([], minConfidence: 0.4, minArea: 0.05))
    }

    // MARK: - aspectFillViewPoint

    func testAspectFillCenterMapsToViewCenter() {
        let v = CourtGeometry.aspectFillViewPoint(
            normalized: CGPoint(x: 0.5, y: 0.5),
            imageSize: CGSize(width: 1280, height: 720),
            viewSize: CGSize(width: 390, height: 844)
        )
        XCTAssertEqual(v.x, 195, accuracy: 1e-6)
        XCTAssertEqual(v.y, 422, accuracy: 1e-6)
    }

    func testAspectFillSquareIntoSquareIsIdentity() {
        let v = CourtGeometry.aspectFillViewPoint(
            normalized: CGPoint(x: 0.25, y: 0.75),
            imageSize: CGSize(width: 100, height: 100),
            viewSize: CGSize(width: 300, height: 300)
        )
        XCTAssertEqual(v.x, 75, accuracy: 1e-6)
        XCTAssertEqual(v.y, 225, accuracy: 1e-6)
    }

    func testAspectFillDegenerateSizesDoNotCrash() {
        let v = CourtGeometry.aspectFillViewPoint(
            normalized: CGPoint(x: 0.5, y: 0.5),
            imageSize: .zero,
            viewSize: CGSize(width: 200, height: 100)
        )
        XCTAssertEqual(v.x, 100, accuracy: 1e-6)
        XCTAssertEqual(v.y, 50, accuracy: 1e-6)
    }

    // MARK: - PlaceholderCourtDetector seam

    func testPlaceholderDetectorReturnsConfiguredResult() async {
        let expected = DetectedCourt(
            corners: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.1),
                      CGPoint(x: 0.9, y: 0.9), CGPoint(x: 0.1, y: 0.9)],
            confidence: 0.77
        )
        let detector = PlaceholderCourtDetector(result: expected)
        let result = await detector.detectCourt(in: Self.makePixelBuffer())
        XCTAssertEqual(result, expected)

        let none = PlaceholderCourtDetector(result: nil)
        let nilResult = await none.detectCourt(in: Self.makePixelBuffer())
        XCTAssertNil(nilResult)
    }

    private static func makePixelBuffer() -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 4, 4, kCVPixelFormatType_32BGRA, nil, &pb)
        return pb!
    }
}
