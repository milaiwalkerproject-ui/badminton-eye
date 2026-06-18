import Foundation
import ScoringEngine

// MARK: - HitDetector (FK keystone — see .planning/REEL-PARITY-ROADMAP.md)
//
// SideAxisTurningPointHitDetector (v1): a deterministic, NO-ML hit/stroke detector
// that reads the EXISTING court-space shuttle trajectory and finds racket contacts
// as turning points (velocity sign-changes) of the player-to-player "side axis"
// (CourtPoint.y, 0 = near baseline, 1 = far baseline, net ≈ 0.5).
//
// Physical invariant: between two contacts the shuttle is a single ballistic body
// whose projection onto the near↔far axis is monotonic (it only travels toward the
// receiving player); only a racket (or net/floor) reverses it. So every hit is a
// turning point of y(t). Spec: workflow wf_53967582-90e.
//
// Robustness levers the unit tests pin:
//  - PROMINENCE gate kills the high-clear APEX false positive (at the apex vy → 0 but
//    never flips sign; the side-axis y keeps drifting toward the same baseline).
//  - SIGNIFICANT-direction tracking: a reversal needs vy to flip between genuine
//    opposite motions, so + → 0 (settling) is NOT a hit.
//  - MIN-SEPARATION refractory collapses frame-noise twins into one event.
//  - Court-units + seconds → framing- and frame-rate-invariant. Orientation (ADR-0001)
//    is neutralised UPSTREAM by the homography (CourtPoint.y is the canonical near↔far
//    axis in both side_on and end_on), so the detector needs no orientation branch.

/// One sampled point of the tracked shuttle: PTS time + (optional) rectified court
/// position. `court == nil` marks a missed-detection / gap frame.
struct TrackSample: Sendable, Equatable {
    let t: Double            // PTS seconds, monotonic
    let court: CourtPoint?   // rectified court-space position; nil == gap
    let imageY: Double?      // optional raw image-y settle cue (unused by v1 core)
    let conf: Double         // detector confidence 0…1

    init(t: Double, court: CourtPoint?, imageY: Double? = nil, conf: Double = 1) {
        self.t = t; self.court = court; self.imageY = imageY; self.conf = conf
    }
}

enum HitEndReason: String, Sendable, Equatable { case settledFlight, trackLost, pastBaseline }

struct HitEvent: Sendable, Equatable {
    let time: Double          // PTS seconds of contact
    let hitter: Side          // who struck (.sideA far / .sideB near)
    let sideAxisPos: Double   // CourtPoint.y at the turn (contact depth)
    let prominence: Double    // reversal magnitude in court-units (quality proxy)
    let approachSpeed: Double // |vy| into the turn, court-units/s
    let isInferred: Bool      // reconstructed across an occluded gap
}

struct RallySegment: Sendable, Equatable {
    let startTime: Double
    let endTime: Double
    let hits: [HitEvent]
    var shotCount: Int { hits.count }
    let lastHitter: Side?     // winner-attribution side (= hits.last?.hitter)
    let endReason: HitEndReason
    let quality: Double       // 0…1 → feeds RallyResult corroboration
}

struct HitDetectorConfig: Sendable, Equatable {
    var minProminence: Double    = 0.08   // court-units (~1 m of 13.4 m)
    var minApproachSpeed: Double = 0.5    // court-units/s along the axis
    var minHitSeparation: Double = 0.12   // seconds (refractory)
    var maxGapFill: Double       = 0.10   // seconds of gap bridged inside a rally
    var settleSpeed: Double      = 0.15   // court-units/s: below this = no real motion
    var endHold: Double          = 0.40   // seconds a settle must persist (T1)
    var endGap: Double           = 0.50   // seconds of track loss → new rally (T2)
    var baselineLow: Double      = 0.02   // T3 near-baseline band
    var baselineHigh: Double     = 0.98   // T3 far-baseline band
    var fpsClampLow: Double      = 24
    var fpsClampHigh: Double     = 240
    var lowFpsQualityThreshold: Double = 60   // below this fps, penalise quality

    static let `default` = HitDetectorConfig()
}

struct HitDetector: Sendable {

    var config: HitDetectorConfig = .default

    /// near player → .sideB, far player → .sideA. The ONLY orientation-tied constant
    /// (reuses TrajectoryRallySuggestor's landing.y < 0.5 → .sideA convention).
    private let nearSide: Side = .sideB
    private let farSide: Side = .sideA

    // MARK: Public API

    /// Pure, deterministic. Whole trajectory in → rally segments out.
    func detectRallies(_ samples: [TrackSample]) -> [RallySegment] {
        let pts = prepared(samples)
        guard pts.count >= 3 else { return [] }
        let fps = estimateFPS(pts)

        // Split into rally windows at track-loss gaps (> endGap). Shorter gaps stay
        // inside a window and are bridged by the neighbouring samples.
        var windows: [[Prepared]] = []
        var current: [Prepared] = [pts[0]]
        for i in 1..<pts.count {
            if pts[i].t - pts[i - 1].t > config.endGap {
                windows.append(current); current = [pts[i]]
            } else {
                current.append(pts[i])
            }
        }
        windows.append(current)

        var out: [RallySegment] = []
        for (wi, w) in windows.enumerated() where w.count >= 3 {
            let endedByGap = wi < windows.count - 1   // a following big gap = track loss
            if let seg = processWindow(w, fps: fps, forcedTrackLost: endedByGap) {
                out.append(seg)
            }
        }
        return out
    }

    /// Convenience for the existing per-rally suggestor call site.
    func detectHits(_ samples: [TrackSample]) -> (hits: [HitEvent], lastHitter: Side?, endReason: HitEndReason?, quality: Double) {
        guard let seg = detectRallies(samples).last else { return ([], nil, nil, 0) }
        return (seg.hits, seg.lastHitter, seg.endReason, seg.quality)
    }

    // MARK: - Internals

    private struct Prepared: Equatable { let t: Double; let y: Double; let imageY: Double?; let conf: Double }

    /// Visible samples only, sorted by time, duplicate-PTS dropped (matches
    /// ShotSpeed's dt > 1e-4 guard).
    private func prepared(_ samples: [TrackSample]) -> [Prepared] {
        let visible = samples.compactMap { s -> Prepared? in
            guard let c = s.court else { return nil }
            return Prepared(t: s.t, y: c.y, imageY: s.imageY, conf: s.conf)
        }.sorted { $0.t < $1.t }
        var dedup: [Prepared] = []
        for p in visible {
            if let last = dedup.last, p.t - last.t <= 1e-4 { continue }
            dedup.append(p)
        }
        return dedup
    }

    private func estimateFPS(_ pts: [Prepared]) -> Double {
        var dts: [Double] = []
        for i in 1..<pts.count {
            let dt = pts[i].t - pts[i - 1].t
            if dt > 1e-4 && dt <= config.maxGapFill { dts.append(dt) }
        }
        guard !dts.isEmpty else { return config.fpsClampLow }
        dts.sort()
        let fps = 1.0 / dts[dts.count / 2]
        return Swift.min(Swift.max(fps, config.fpsClampLow), config.fpsClampHigh)
    }

    private func smoothingWindow(fps: Double) -> Int {
        var w = Int((0.10 * fps).rounded())
        if w % 2 == 0 { w += 1 }
        let hi = Swift.max(5, Int((0.20 * fps).rounded()))
        return Swift.min(Swift.max(w, 5), hi)
    }

    /// Centered moving average; window shrinks at edges.
    private func smooth(_ ys: [Double], window: Int) -> [Double] {
        let half = window / 2
        var out = [Double](repeating: 0, count: ys.count)
        for i in 0..<ys.count {
            let lo = Swift.max(0, i - half), hi = Swift.min(ys.count - 1, i + half)
            var sum = 0.0
            for j in lo...hi { sum += ys[j] }
            out[i] = sum / Double(hi - lo + 1)
        }
        return out
    }

    private func processWindow(_ w: [Prepared], fps: Double, forcedTrackLost: Bool) -> RallySegment? {
        let n = w.count
        let ys = w.map { $0.y }
        let ts = w.map { $0.t }
        let window = smoothingWindow(fps: fps)
        let ySm = smooth(ys, window: window)

        // Central-difference side-axis velocity (court-units / second).
        var vy = [Double](repeating: 0, count: n)
        for i in 1..<(n - 1) {
            let dt = ts[i + 1] - ts[i - 1]
            vy[i] = dt > 1e-4 ? (ySm[i + 1] - ySm[i - 1]) / dt : 0
        }
        if n > 2 { vy[0] = vy[1]; vy[n - 1] = vy[n - 2] }

        // --- Seed the serve (shot 1): direction of the initial significant motion. ---
        let serveIdx = indexOfFirstSignificant(vy)
        let serveDir = vy[serveIdx]
        let serveHitter: Side = serveDir >= 0 ? nearSide : farSide
        var hits: [HitEvent] = [HitEvent(
            time: ts[0], hitter: serveHitter, sideAxisPos: ySm[0],
            prominence: abs((ySm.last ?? ySm[0]) - ySm[0]),
            approachSpeed: abs(serveDir), isInferred: false)]

        // --- Reversals: flips of the SIGNIFICANT side-axis direction. ---
        let eps = config.settleSpeed
        var lastDir = 0              // -1 / 0 / +1, last significant direction
        var lastDirIndex = serveIdx
        var lastExtremumY = ySm[0]
        var arcStart = 0             // index of the previous turn (or rally start)
        var inferredPresent = false
        for i in 0..<n {
            let s = vy[i] > eps ? 1 : (vy[i] < -eps ? -1 : 0)
            guard s != 0 else { continue }
            if lastDir != 0 && s != lastDir {
                // A genuine reversal between lastDirIndex and i.
                let j = lastDirIndex
                let prominence = abs(ySm[i] - lastExtremumY)
                // Approach = PEAK speed of the incoming arc (NOT the speed right at the
                // turn, which is ~0 near a clear's apex). This is what separates a real
                // stroke from end-of-rally settling jitter.
                let approach = (arcStart...i).map { abs(vy[$0]) }.max() ?? 0
                if prominence >= config.minProminence && approach >= config.minApproachSpeed {
                    let av = abs(vy[j]), bv = abs(vy[i])
                    let frac = (av + bv) > 1e-9 ? av / (av + bv) : 0.5
                    let tStar = ts[j] + (ts[i] - ts[j]) * frac
                    let isInferred = (ts[i] - ts[j]) > 1.5 / fps
                    if isInferred { inferredPresent = true }
                    let hitter: Side = lastDir > 0 ? farSide : nearSide
                    let cand = HitEvent(time: tStar, hitter: hitter, sideAxisPos: ySm[i],
                                        prominence: prominence, approachSpeed: approach, isInferred: isInferred)
                    // Refractory: keep the larger-prominence of a twin within minHitSeparation.
                    if let last = hits.last, cand.time - last.time < config.minHitSeparation {
                        if cand.prominence > last.prominence { hits[hits.count - 1] = cand }
                    } else {
                        hits.append(cand)
                    }
                    lastExtremumY = ySm[i]
                    arcStart = i
                }
            }
            lastDir = s
            lastDirIndex = i
        }

        // End reason: track loss (a following gap forced the close), else a raw
        // side-axis sample past a baseline AFTER the last hit, else a settled flight.
        let lastHitTime = hits.last?.time ?? ts[0]
        var pastBaseline = false
        for k in 0..<n where ts[k] > lastHitTime {
            if ys[k] <= config.baselineLow || ys[k] >= config.baselineHigh { pastBaseline = true; break }
        }
        let endReason: HitEndReason = forcedTrackLost ? .trackLost : (pastBaseline ? .pastBaseline : .settledFlight)

        // --- Quality. ---
        let lowFps = fps < config.lowFpsQualityThreshold
        var quality = 1.0
        if inferredPresent { quality -= 0.4 }
        if endReason == .trackLost { quality -= 0.3 }
        if lowFps { quality -= 0.45 }
        if hits.count > 1 {
            let avgProm = hits.dropFirst().map { $0.prominence }.reduce(0, +) / Double(hits.count - 1)
            quality = Swift.min(quality, 0.5 + 0.5 * Swift.min(1, avgProm / Swift.max(1e-6, config.minProminence) * 0.25))
        }
        quality = Swift.max(0, Swift.min(1, quality))

        return RallySegment(
            startTime: ts[0], endTime: ts[n - 1], hits: hits,
            lastHitter: hits.last?.hitter, endReason: endReason, quality: quality)
    }

    // MARK: tiny helpers
    private func indexOfFirstSignificant(_ vy: [Double]) -> Int {
        for (i, v) in vy.enumerated() where abs(v) >= config.minApproachSpeed { return i }
        return 0
    }
}
