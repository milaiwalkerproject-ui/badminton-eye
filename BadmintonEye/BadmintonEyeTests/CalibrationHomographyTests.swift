// CalibrationHomographyTests.swift
// End-to-end regression pins for the calibration → homography chain.
//
// History: computeHomography's destination array was non-cyclic
// ([(0,0),(1,0),(0,1),(1,1)] against a CLOCKWISE source quad), which produced a
// fold-over ("bowtie") homography for every saved profile — the court center
// mapped to y≈2.25 and in-bounds near-left landings mirrored to the right
// sideline. These tests pin the corrected clockwise correspondence
// (TL→(0,0), TR→(1,0), BR→(1,1), BL→(0,1)) all the way from the tap order,
// through CalibrationProfile's historically-crossed stored fields, to court
// coordinates — so neither the dst order nor the field crossing can silently
// regress again.

import XCTest
import CoreGraphics
@testable import BadmintonEye

@MainActor
final class CalibrationHomographyTests: XCTestCase {

    // Trapezoid court as filmed from behind a baseline (clockwise tap order).
    private let tapTL = CGPoint(x: 100, y: 200)
    private let tapTR = CGPoint(x: 300, y: 200)
    private let tapBR = CGPoint(x: 380, y: 700)
    private let tapBL = CGPoint(x: 20, y: 700)
    private var taps: [CGPoint] { [tapTL, tapTR, tapBR, tapBL] }
    private let imageSize = CGSize(width: 400, height: 800)

    private let calculator = TrajectoryCalculator()

    private func assertCourt(_ point: CGPoint, _ homography: [[Double]],
                             x: Double, y: Double, accuracy: Double = 1e-6,
                             file: StaticString = #filePath, line: UInt = #line) {
        let court = calculator.transformPoint(point, using: homography)
        XCTAssertEqual(court.x, x, accuracy: accuracy, "court x", file: file, line: line)
        XCTAssertEqual(court.y, y, accuracy: accuracy, "court y", file: file, line: line)
    }

    // MARK: - Corner order round-trips through the (crossed) stored fields

    func testCornersRoundTripInTapOrder() {
        let profile = CalibrationProfile()
        profile.setCorners(taps, imageSize: imageSize)
        XCTAssertEqual(profile.corners, taps,
                       "corners accessor must return the clockwise tap order [TL, TR, BR, BL]")
    }

    // MARK: - Tap → stored field → array → court, the definitive pin

    func testTapToCourtCornerMapping() {
        let profile = CalibrationProfile()
        profile.setCorners(taps, imageSize: imageSize)
        guard let corners = profile.corners else { return XCTFail("corners nil") }
        let h = calculator.computeHomography(imageCorners: corners, imageSize: imageSize)

        assertCourt(tapTL, h, x: 0, y: 0)
        assertCourt(tapTR, h, x: 1, y: 0)
        assertCourt(tapBR, h, x: 1, y: 1)
        assertCourt(tapBL, h, x: 0, y: 1)
    }

    // MARK: - Interior points stay inside the unit square (no fold-over)

    func testInteriorPointsDoNotFold() {
        let h = calculator.computeHomography(imageCorners: taps, imageSize: imageSize)

        // Court center: the folded homography sent this to (0.5, 2.25).
        let center = calculator.transformPoint(CGPoint(x: 200, y: 450), using: h)
        XCTAssertEqual(center.x, 0.5, accuracy: 0.05)
        XCTAssertTrue((0...1).contains(center.y), "center y \(center.y) outside court")

        // Near-left in-bounds: the folded homography mirrored this to x≈0.96.
        let nearLeft = calculator.transformPoint(CGPoint(x: 60, y: 650), using: h)
        XCTAssertLessThan(nearLeft.x, 0.5)
        XCTAssertGreaterThan(nearLeft.y, 0.5)

        let nearRight = calculator.transformPoint(CGPoint(x: 340, y: 650), using: h)
        XCTAssertGreaterThan(nearRight.x, 0.5)
        XCTAssertGreaterThan(nearRight.y, 0.5)

        // Far interior: the folded homography sent this to negative coordinates.
        let farLeft = calculator.transformPoint(CGPoint(x: 120, y: 300), using: h)
        XCTAssertLessThan(farLeft.x, 0.5)
        XCTAssertLessThan(farLeft.y, 0.5)
        XCTAssertTrue((0...1).contains(farLeft.y))
    }

    // MARK: - On-disk byte compatibility for profiles saved by older builds

    func testLegacyStoredBytesDecodeUnchanged() throws {
        // Simulate a profile persisted by any prior build by writing the four Data
        // fields directly with the HISTORICAL crossed meaning: cornerBottomLeft
        // holds the bottom-RIGHT screen point and cornerBottomRight the bottom-LEFT.
        struct P: Codable { let x: Double; let y: Double }
        let enc = JSONEncoder()
        let profile = CalibrationProfile()
        profile.cornerTopLeft = try enc.encode(P(x: 100, y: 200))
        profile.cornerTopRight = try enc.encode(P(x: 300, y: 200))
        profile.cornerBottomLeft = try enc.encode(P(x: 380, y: 700))   // BR tap
        profile.cornerBottomRight = try enc.encode(P(x: 20, y: 700))   // BL tap
        profile.imageWidth = 400
        profile.imageHeight = 800

        XCTAssertEqual(profile.corners, taps,
                       "legacy bytes must decode to the clockwise tap order")

        guard let corners = profile.corners else { return XCTFail("corners nil") }
        let h = calculator.computeHomography(imageCorners: corners, imageSize: imageSize)
        // The physical bottom-right corner of the court still maps to court (1,1).
        assertCourt(tapBR, h, x: 1, y: 1)
        assertCourt(tapBL, h, x: 0, y: 1)
    }
}
