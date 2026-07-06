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

    // MARK: confident rally-end gate (auto-rally-end brain)

    func testConfidentRallyEndAcceptsCleanRally() {
        let s = ramp(fps: 120, [(0.6, 0.1, 0.95), (0.7, 0.95, 0.15), (0.5, 0.15, 0.15)])
        let end = det.confidentRallyEnd(s)
        XCTAssertEqual(end?.side, .sideA)
        XCTAssertEqual(end?.reason, .settledFlight)
    }

    func testConfidentRallyEndRejectsLowQuality() {
        // 30 fps → quality penalised below the 0.6 default gate → don't auto-end.
        let s = ramp(fps: 30, [(0.5, 0.1, 0.9), (0.5, 0.9, 0.2), (0.5, 0.2, 0.85), (0.45, 0.85, 0.01)])
        XCTAssertNil(det.confidentRallyEnd(s))
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

    // MARK: fabricated-serve fix — static/noise tracks must stay silent

    func testStaticTrackYieldsNoHitsNoWinnerZeroQuality() {
        // 1 s of a perfectly stationary visible shuttle: no significant motion →
        // no fabricated serve, no segment at all.
        let s = (0..<120).map { TrackSample(t: Double($0) / 120, court: CourtPoint(x: 0.5, y: 0.45)) }
        XCTAssertTrue(det.detectRallies(s).isEmpty)
        let hit = det.detectHits(s)
        XCTAssertTrue(hit.hits.isEmpty)
        XCTAssertNil(hit.lastHitter)
        XCTAssertEqual(hit.quality, 0)
        XCTAssertNil(det.confidentRallyEnd(s))
    }

    func testTinyJitterTrackStaysSilent() {
        // Alternating ±0.005 cu detector jitter at 120 fps: smoothed central-diff
        // vy stays ~0.01 cu/s, far below minApproachSpeed (0.5) → no serve seeded.
        let s = (0..<120).map { i in
            TrackSample(t: Double(i) / 120,
                        court: CourtPoint(x: 0.5, y: 0.5 + (i % 2 == 0 ? 0.005 : -0.005)))
        }
        XCTAssertTrue(det.detectRallies(s).isEmpty)
        XCTAssertNil(det.detectHits(s).lastHitter)
        XCTAssertNil(det.confidentRallyEnd(s))
    }

    // MARK: boundary — a slow but real serve must survive the no-motion guard

    func testSlowServeStillDetected() {
        // 0.30 → 0.72 cu over 0.6 s ≈ 0.7 cu/s (> minApproachSpeed 0.5), then settles.
        // Serve-only rally: 1 hit, near player (.sideB); quality NOT killed by the
        // single-hit prominence cap (drift ≈ 0.42 cu > the 0.32 saturation point).
        let s = ramp(fps: 120, [(0.6, 0.30, 0.72), (0.4, 0.72, 0.72)])
        let seg = det.detectRallies(s).first
        XCTAssertEqual(seg?.shotCount, 1)
        XCTAssertEqual(seg?.hits.first?.hitter, .sideB)
        XCTAssertEqual(seg?.lastHitter, .sideB)
        XCTAssertGreaterThanOrEqual(seg?.quality ?? 0, 0.6)
    }

    // MARK: residual channel — a one-frame glitch spike must never be confident

    func testGlitchSpikeInStaticTrackNotConfident() {
        // One-frame +0.08 cu outlier in an otherwise static track: the smoothed
        // spike can clear the motion guard, but total drift ≈ 0 so the single-hit
        // prominence cap holds quality near 0.5 — below confidentRallyEnd's gate.
        let s = (0..<120).map { i in
            TrackSample(t: Double(i) / 120,
                        court: CourtPoint(x: 0.5, y: i == 60 ? 0.53 : 0.45))
        }
        XCTAssertLessThan(det.detectHits(s).quality, 0.6)
        XCTAssertNil(det.confidentRallyEnd(s))
    }
}
