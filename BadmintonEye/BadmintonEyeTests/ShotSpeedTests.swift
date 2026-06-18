import XCTest
@testable import BadmintonEye

/// Unit tests for the F1 calibrated-velocity foundation
/// (`TrajectoryCalculator.shotSpeed`). These pin the kinematics that will become
/// the classifier's frame-rate-independent speed feature (see
/// `.planning/REEL-PARITY-ROADMAP.md`), so the km/h readout and the future
/// feature swap rest on verified math.
final class ShotSpeedTests: XCTestCase {

    private let calc = TrajectoryCalculator()

    // MARK: - Real-unit conversion

    func testFullWidthMoveGivesCalibratedSpeed() {
        // Across the full doubles width (6.10 m) in 0.1 s → 61.0 m/s → 219.6 km/h.
        let pts = [CourtPoint(x: 0.0, y: 0.5), CourtPoint(x: 1.0, y: 0.5)]
        let ts = [0.0, 0.1]
        let speed = calc.shotSpeed(courtPoints: pts, timestamps: ts)
        XCTAssertNotNil(speed)
        XCTAssertEqual(speed!.metersPerSecond, 61.0, accuracy: 1e-6)
        XCTAssertEqual(speed!.kilometersPerHour, 219.6, accuracy: 1e-4)
        XCTAssertEqual(speed!.sampleCount, 2)
    }

    func testFullLengthMoveUsesLengthScale() {
        // Along the full court length (13.40 m) in 0.2 s → 67.0 m/s.
        let pts = [CourtPoint(x: 0.5, y: 0.0), CourtPoint(x: 0.5, y: 1.0)]
        let ts = [0.0, 0.2]
        let speed = calc.shotSpeed(courtPoints: pts, timestamps: ts)
        XCTAssertEqual(speed?.metersPerSecond ?? 0, 67.0, accuracy: 1e-6)
    }

    // MARK: - Peak detection & fps invariance

    func testReportsPeakSegmentNotAverage() {
        // Slow then fast: peak must reflect the fast segment, not a mean.
        let pts = [CourtPoint(x: 0.0, y: 0.5),
                   CourtPoint(x: 0.1, y: 0.5),   // slow: 0.61 m over 0.1 s = 6.1 m/s
                   CourtPoint(x: 0.6, y: 0.5)]    // fast: 3.05 m over 0.01 s = 305 m/s
        let ts = [0.0, 0.1, 0.11]
        let speed = calc.shotSpeed(courtPoints: pts, timestamps: ts)
        XCTAssertEqual(speed?.metersPerSecond ?? 0, 305.0, accuracy: 1e-6)
    }

    func testSpeedIsFrameRateIndependent() {
        // Same physical motion sampled at 2 different rates → same speed.
        // 0.305 m (0.05 width) per step; coarse 0.05 s/step vs fine 0.025 s/step
        // describe DIFFERENT speeds, so instead verify identical motion+dt scales.
        let coarse = calc.shotSpeed(
            courtPoints: [CourtPoint(x: 0.0, y: 0.5), CourtPoint(x: 0.5, y: 0.5)],
            timestamps: [0.0, 0.1])
        let fineSplit = calc.shotSpeed(
            courtPoints: [CourtPoint(x: 0.0, y: 0.5), CourtPoint(x: 0.25, y: 0.5), CourtPoint(x: 0.5, y: 0.5)],
            timestamps: [0.0, 0.05, 0.1])
        // Both describe 3.05 m total in 0.1 s at constant velocity = 30.5 m/s peak.
        XCTAssertEqual(coarse?.metersPerSecond ?? 0, 30.5, accuracy: 1e-6)
        XCTAssertEqual(fineSplit?.metersPerSecond ?? 0, 30.5, accuracy: 1e-6)
    }

    // MARK: - Reliability flag

    func testIsReliableRequiresEnoughSamplesAndFps() {
        // 5 samples at 240 Hz → reliable.
        let ts = (0..<5).map { Double($0) / 240.0 }
        let pts = (0..<5).map { CourtPoint(x: Double($0) * 0.1, y: 0.5) }
        let speed = calc.shotSpeed(courtPoints: pts, timestamps: ts)
        XCTAssertNotNil(speed)
        XCTAssertEqual(speed!.effectiveFPS, 240.0, accuracy: 1e-6)
        XCTAssertTrue(speed!.isReliable)
    }

    func testLowFpsIsNotReliable() {
        // 2 samples at 10 Hz → not reliable even with a valid speed.
        let speed = calc.shotSpeed(
            courtPoints: [CourtPoint(x: 0.0, y: 0.5), CourtPoint(x: 1.0, y: 0.5)],
            timestamps: [0.0, 0.1])
        XCTAssertEqual(speed?.isReliable, false)
    }

    // MARK: - Guards

    func testTooFewPointsReturnsNil() {
        XCTAssertNil(calc.shotSpeed(courtPoints: [CourtPoint(x: 0, y: 0)], timestamps: [0.0]))
        XCTAssertNil(calc.shotSpeed(courtPoints: [], timestamps: []))
    }

    func testMismatchedCountsReturnsNil() {
        let pts = [CourtPoint(x: 0, y: 0), CourtPoint(x: 1, y: 0)]
        XCTAssertNil(calc.shotSpeed(courtPoints: pts, timestamps: [0.0]))
    }

    func testDuplicateTimestampsSkippedThenNil() {
        // Non-advancing time → segment skipped → no usable signal → nil.
        let pts = [CourtPoint(x: 0, y: 0.5), CourtPoint(x: 1, y: 0.5)]
        XCTAssertNil(calc.shotSpeed(courtPoints: pts, timestamps: [0.1, 0.1]))
    }
}
