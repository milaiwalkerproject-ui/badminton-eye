import XCTest
import ScoringEngine
@testable import BadmintonEye

/// Unit tests for the FK keystone (`HitDetector`) — see
/// `.planning/REEL-PARITY-ROADMAP.md`. They pin the spec's behaviours
/// (workflow wf_53967582-90e): hits as side-axis turning points, apex-not-a-hit,
/// refractory de-dup, occluded-contact inference, rally segmentation, and
/// last-hit attribution.
final class HitDetectorTests: XCTestCase {

    private let det = HitDetector()

    // MARK: builder — piecewise-linear y(t) sampled at fps, optional gap + jitter

    private func ramp(fps: Double, t0: Double = 0,
                      _ legs: [(dur: Double, y0: Double, y1: Double)],
                      drop: ClosedRange<Double>? = nil,
                      jitter: Double = 0) -> [TrackSample] {
        var out: [TrackSample] = []
        let dt = 1.0 / fps
        var t = t0
        var k = 0
        for leg in legs {
            let steps = max(1, Int((leg.dur / dt).rounded()))
            for s in 0..<steps {
                let f = steps > 1 ? Double(s) / Double(steps - 1) : 0   // inclusive of endpoint
                var y = leg.y0 + (leg.y1 - leg.y0) * f
                if jitter > 0 { y += (k % 2 == 0 ? jitter : -jitter) }
                k += 1
                let tt = t + Double(s) * dt
                if let drop, drop.contains(tt) { continue }   // occlusion: no sample
                out.append(TrackSample(t: tt, court: CourtPoint(x: 0.5, y: max(0, min(1, y))), imageY: y, conf: 0.9))
            }
            t += Double(steps) * dt
        }
        return out
    }

    // MARK: serve + one return

    func testSingleClearOneHit() {
        let s = ramp(fps: 120, [(0.6, 0.1, 0.95), (0.7, 0.95, 0.15), (0.5, 0.15, 0.15)])
        let r = det.detectRallies(s)
        XCTAssertEqual(r.count, 1)
        let seg = r[0]
        XCTAssertEqual(seg.shotCount, 2)
        XCTAssertEqual(seg.hits[0].hitter, .sideB)   // serve, near player
        XCTAssertEqual(seg.hits[1].hitter, .sideA)   // far player returns
        XCTAssertEqual(seg.lastHitter, .sideA)
        XCTAssertEqual(seg.endReason, .settledFlight)
    }

    // MARK: four-shot rally, strict alternation, past-baseline end

    func testFourShotRallyAlternates() {
        let s = ramp(fps: 120, [(0.5, 0.1, 0.9), (0.5, 0.9, 0.2), (0.5, 0.2, 0.85), (0.45, 0.85, 0.01)])
        let seg = det.detectRallies(s).first
        XCTAssertEqual(seg?.shotCount, 4)
        XCTAssertEqual(seg?.hits.map(\.hitter), [.sideB, .sideA, .sideB, .sideA])
        XCTAssertEqual(seg?.lastHitter, .sideA)
        XCTAssertEqual(seg?.endReason, .pastBaseline)
    }

    // MARK: the high-clear apex must NOT be a hit

    func testApexNotCountedAsHit() {
        // monotonic side-axis rise (shuttle flies near→far) then settles — never reverses.
        let s = ramp(fps: 120, [(0.6, 0.1, 0.95), (0.4, 0.95, 0.95)])
        let seg = det.detectRallies(s).first
        XCTAssertEqual(seg?.shotCount, 1)            // serve only
    }

    // MARK: frame-noise twin crossings collapse to one hit

    func testNoiseTwinRejectedByRefractory() {
        let s = ramp(fps: 240, [(0.5, 0.1, 0.8), (0.5, 0.8, 0.2)], jitter: 0.004)
        let seg = det.detectRallies(s).first
        XCTAssertEqual(seg?.shotCount, 2)            // serve + exactly one reversal
    }

    // MARK: occluded contact reconstructed across a short gap

    func testOccludedContactInferred() {
        let s = ramp(fps: 120, [(0.4, 0.1, 0.8), (0.4, 0.78, 0.2)], drop: 0.40...0.48)
        let seg = det.detectRallies(s).first
        XCTAssertEqual(seg?.shotCount, 2)
        XCTAssertEqual(seg?.hits.last?.isInferred, true)
    }

    // MARK: a long track-loss gap splits one clip into two rallies

    func testLongGapSplitsRallies() {
        var s = ramp(fps: 120, [(0.5, 0.1, 0.9), (0.5, 0.9, 0.2), (0.4, 0.2, 0.2)])      // rally 1, ends ~1.4
        s += ramp(fps: 120, t0: 2.2, [(0.5, 0.1, 0.9), (0.5, 0.9, 0.2), (0.4, 0.2, 0.2)]) // rally 2
        let r = det.detectRallies(s)
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0].endReason, .trackLost)   // closed by the 0.8 s gap
    }

    // MARK: past-baseline attribution — last clean hitter keeps the point

    func testPastBaselineAttribution() {
        let s = ramp(fps: 120, [(0.5, 0.1, 0.85), (0.5, 0.85, 0.01)])
        let seg = det.detectRallies(s).first
        XCTAssertEqual(seg?.shotCount, 2)
        XCTAssertEqual(seg?.endReason, .pastBaseline)
        XCTAssertEqual(seg?.lastHitter, .sideA)
    }

    // MARK: low fps still counts, but quality is penalised + flagged

    func testLowFpsQualityPenalty() {
        let s = ramp(fps: 30, [(0.5, 0.1, 0.9), (0.5, 0.9, 0.2), (0.5, 0.2, 0.85), (0.45, 0.85, 0.01)])
        let seg = det.detectRallies(s).first
        XCTAssertEqual(seg?.shotCount, 4)
        XCTAssertEqual(seg?.lastHitter, .sideA)
        XCTAssertLessThan(seg?.quality ?? 1, 0.6)
    }

    // MARK: detector depends only on court-space input (no orientation branch) → deterministic

    func testDeterministicPurity() {
        let s = ramp(fps: 120, [(0.6, 0.1, 0.95), (0.7, 0.95, 0.15), (0.5, 0.15, 0.15)])
        XCTAssertEqual(det.detectRallies(s), det.detectRallies(s))
    }

    // MARK: degenerate inputs never crash and never invent hits

    func testDegenerateInputs() {
        XCTAssertTrue(det.detectRallies([]).isEmpty)
        let allNil = (0..<10).map { TrackSample(t: Double($0) / 120, court: nil) }
        XCTAssertTrue(det.detectRallies(allNil).isEmpty)
        XCTAssertTrue(det.detectRallies([TrackSample(t: 0, court: CourtPoint(x: 0.5, y: 0.5))]).isEmpty)
        let dupT = [TrackSample(t: 1, court: CourtPoint(x: 0.5, y: 0.3)),
                    TrackSample(t: 1, court: CourtPoint(x: 0.5, y: 0.4))]
        XCTAssertTrue(det.detectRallies(dupT).isEmpty)   // dedup → too few → empty, no crash
    }
}
