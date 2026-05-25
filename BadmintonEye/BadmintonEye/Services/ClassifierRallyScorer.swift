@preconcurrency import AVFoundation
import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import ScoringEngine

// MARK: - RallyResultProducing (seam decision B — Overseer 2026-05-25)

/// Produces the rich per-rally `RallyResult` (winner + confidence + provenance +
/// optional close-call landing), NOT a bare `RallySuggestion`. The export /
/// corroboration / label-quality pipeline depends on that provenance, so the
/// System-2 scorer must not collapse to `RallySuggestion`.
protocol RallyResultProducing: Sendable {
    func produceResult(rallyIndex: Int, clipRef: ClipRef?) async -> RallyResult
}

extension RallyResultProducing {
    /// Back-compat shim: any existing `RallySuggesting` call site keeps working,
    /// it just discards the extra provenance it never consumed.
    func suggestion(rallyIndex: Int) async -> RallySuggestion {
        await produceResult(rallyIndex: rallyIndex, clipRef: nil).asSuggestion
    }
}

// MARK: - ClassifierRallyScorer (System 2)

/// System-2 on-device scorer: runs the trained `RallyWinnerClassifier` over a
/// rally's shuttle trajectory and emits a full `RallyResult`.
///
/// Pipeline on `produceResult`:
///   1. Snapshot the recent frame window from the shared `CircularFrameBuffer`.
///   2. Run the injected `ShuttleDetecting` model → NORMALIZED image positions.
///   3. `featurize()` those image-space points → 38-feature vector (this MUST
///      match `agents/Vision/output/FEATURIZE-PORT-SPEC.md` + the golden fixture;
///      the classifier trained on normalized IMAGE coords, NOT court coords).
///   4. Run the CoreML model → `winner_logits[2]` → softmax → winner + confidence.
///   5. (optional) if calibration exists, compute a court-space landing for the
///      replay overlay — FORCED to `.uncertain` for close calls (spike (c):
///      tight line calls are not reliable on 30fps/no-calibration data).
///   6. Assemble `RallyResult` with `source = .cvPipeline`, `cvVote` set,
///      `positionVote = nil` (System 1 deferred), `corroboration = .singleSignal`.
///
/// Fallback: if the model/frames/detector are unavailable or <2 visible points,
/// returns a low-confidence coin-flip result (mirrors `TrajectoryRallySuggestor`)
/// so the UI never stalls.
///
/// ⚠️ TRAIN/SERVE-SKEW CAVEAT: the classifier learned features at the training
/// stride/fps (JSON `f` steps of ~8). On-device the capture stride differs, so
/// the frame-rate-sensitive features (`final_velocity`, `gap_ratio`) may drift
/// from the training distribution. Position features (16 samples, mean_last,
/// apex_y) transfer cleanly. ⇒ confidence here is PROVISIONAL until validated
/// against the ground-truth holdout — keep auto-apply `T_high` conservative.
final class ClassifierRallyScorer: RallyResultProducing, @unchecked Sendable {

    // MARK: - Tunables (mirror TrajectoryRallySuggestor's capture window)
    private let windowSeconds: TimeInterval = 2.0
    private let frameStride: Int = 2
    private let maxFramesPerSuggestion: Int = 16
    private let featureDim = 38

    /// Close-call band: |landing.y - net| or low model confidence ⇒ `.uncertain`.
    private let landingUncertainMargin = 0.02   // matches TrajectoryCalculator.determineLanding
    private let landingConfidenceFloor = 0.65   // below this, do not assert in/out

    // MARK: - Dependencies
    private let frameBuffer: CircularFrameBuffer
    private let detector: ShuttleDetecting
    private let calibration: CalibrationProfile?
    private let calculator = TrajectoryCalculator()
    private let model: MLModel?

    // MARK: - Init
    init(
        frameBuffer: CircularFrameBuffer,
        detector: ShuttleDetecting,
        calibration: CalibrationProfile?,
        model: MLModel?
    ) {
        self.frameBuffer = frameBuffer
        self.detector = detector
        self.calibration = calibration
        self.model = model
    }

    /// Convenience loader for the bundled `RallyWinnerClassifier.mlpackage`.
    /// Returns nil if the model isn't bundled yet (scorer then falls back).
    static func loadBundledModel() -> MLModel? {
        guard let url = Bundle.main.url(forResource: "RallyWinnerClassifier", withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: "RallyWinnerClassifier", withExtension: "mlpackage")
        else { return nil }
        return try? MLModel(contentsOf: url)
    }

    // MARK: - RallyResultProducing
    func produceResult(rallyIndex: Int, clipRef: ClipRef?) async -> RallyResult {
        let calibrationSnapshot = await snapshotCalibration()
        let sampleBuffers = frameBuffer.recentFrames(seconds: windowSeconds)
        guard let model, !sampleBuffers.isEmpty else {
            return fallback(rallyIndex: rallyIndex, clipRef: clipRef)
        }

        // Decimate to a bounded set, tracking each frame's index in the
        // (decimated) window as the trajectory's `f` (a monotonic frame proxy).
        let stridedIdx = Array(stride(from: 0, to: sampleBuffers.count, by: max(frameStride, 1)))
        let chosen = Array(stridedIdx.suffix(maxFramesPerSuggestion))

        // Collect NORMALIZED image-space points (x,y in [0,1]) + frame index.
        // Detector points are always "visible" (it only emits on localization).
        var pts: [(x: Double, y: Double, f: Int, vis: Bool)] = []
        for originalIdx in chosen {
            guard let pb = CMSampleBufferGetImageBuffer(sampleBuffers[originalIdx]) else { continue }
            do {
                let obs = try await detector.detect(in: pb)
                if let best = obs.max(by: { $0.confidence < $1.confidence }) {
                    pts.append((x: Double(best.position.x), y: Double(best.position.y), f: originalIdx, vis: true))
                }
            } catch { continue }
        }
        guard pts.count >= 2 else { return fallback(rallyIndex: rallyIndex, clipRef: clipRef) }

        // Featurize (image space — matches training) → classify.
        let feats = Self.featurize(pts)
        guard let (winner, confidence) = classify(features: feats, model: model) else {
            return fallback(rallyIndex: rallyIndex, clipRef: clipRef)
        }

        // Optional close-call landing (court space) for the replay overlay.
        let landing = computeLanding(imagePoints: pts, snapshot: calibrationSnapshot, modelConfidence: confidence)

        let vote = SideVote(side: winner, confidence: confidence)
        return RallyResult(
            rallyIndex: rallyIndex,
            winner: winner,
            confidence: confidence,
            source: .cvPipeline,
            corroboration: .singleSignal,   // only System 2 opined; human/oracle may upgrade later
            landing: landing,
            clipRef: clipRef,
            positionVote: nil,              // System 1 deferred to v2
            cvVote: vote,
            nextServeVerified: nil          // oracle unavailable without System 1
        )
    }

    // MARK: - CoreML inference
    private func classify(features: [Float], model: MLModel) -> (Side, Double)? {
        guard let arr = try? MLMultiArray(shape: [1, NSNumber(value: featureDim)], dataType: .float32) else { return nil }
        for (i, v) in features.enumerated() { arr[i] = NSNumber(value: v) }
        guard
            let provider = try? MLDictionaryFeatureProvider(dictionary: ["trajectory_features": arr]),
            let out = try? model.prediction(from: provider),
            let logitsName = out.featureNames.first(where: { $0.contains("logit") }) ?? out.featureNames.first,
            let logits = out.featureValue(for: logitsName)?.multiArrayValue,
            logits.count >= 2
        else { return nil }

        let a = Double(truncating: logits[0]); let b = Double(truncating: logits[1])
        // softmax over the 2 logits → probability of the argmax class.
        let m = max(a, b)
        let ea = exp(a - m); let eb = exp(b - m)
        let pA = ea / (ea + eb)
        let winner: Side = pA >= 0.5 ? .sideA : .sideB   // class 0 = sideA, 1 = sideB
        let confidence = max(pA, 1 - pA)
        return (winner, confidence)
    }

    // MARK: - featurize (Swift port — MUST match FEATURIZE-PORT-SPEC.md + golden fixture)
    /// Mirrors hawkeye.train.winner_classifier.featurize EXACTLY, including the
    /// `vis==true` filter (so the golden fixture's `mixed_vis` case passes when
    /// fed the raw trajectory). Verified against featurize_golden.json (≤1e-5).
    static func featurize(_ raw: [(x: Double, y: Double, f: Int, vis: Bool)]) -> [Float] {
        let pts = raw.filter { $0.vis }
        let n = pts.count
        if n < 2 { return [Float](repeating: 0, count: 38) }
        let xs = pts.map { $0.x }, ys = pts.map { $0.y }, fs = pts.map { Double($0.f) }

        // 16 evenly-spaced samples via linear interpolation along the index.
        var samples: [Float] = []
        samples.reserveCapacity(32)
        for k in 0..<16 {
            let idx = Double(k) * Double(n - 1) / 15.0
            let lo = Int(floor(idx)); let hi = min(lo + 1, n - 1); let frac = idx - Double(lo)
            let sx = xs[lo] * (1 - frac) + xs[hi] * frac
            let sy = ys[lo] * (1 - frac) + ys[hi] * frac
            samples.append(Float(sx)); samples.append(Float(sy))
        }

        let last3 = Array(pts.suffix(3))
        let meanLastX = last3.map { $0.x }.reduce(0, +) / Double(last3.count)
        let meanLastY = last3.map { $0.y }.reduce(0, +) / Double(last3.count)

        var finalV = 0.0
        if n >= 4 {
            let dx = xs[n-1] - xs[n-4]; let dy = ys[n-1] - ys[n-4]
            let df = max(1.0, fs[n-1] - fs[n-4])
            finalV = (dx*dx + dy*dy).squareRoot() / df
        }
        let apexY = ys.min() ?? 0
        var length = 0.0
        for i in 1..<n { let dx = xs[i]-xs[i-1]; let dy = ys[i]-ys[i-1]; length += (dx*dx+dy*dy).squareRoot() }
        let span = max(1.0, fs[n-1] - fs[0])
        let gapRatio = 1.0 - (Double(n) / (span + 1.0))

        return samples + [Float(meanLastX), Float(meanLastY), Float(finalV), Float(apexY), Float(length), Float(gapRatio)]
    }

    // MARK: - Landing (close calls → .uncertain)
    private func computeLanding(
        imagePoints pts: [(x: Double, y: Double, f: Int, vis: Bool)],
        snapshot: CalibrationSnapshot?,
        modelConfidence: Double
    ) -> LandingCall? {
        guard let snap = snapshot else { return nil }   // no calibration → no court landing
        let imgPx = pts.map { CGPoint(x: $0.x * CGFloat(snap.imageWidth), y: $0.y * CGFloat(snap.imageHeight)) }
        let homography = calculator.computeHomography(
            imageCorners: snap.corners,
            imageSize: CGSize(width: snap.imageWidth, height: snap.imageHeight)
        )
        let courtPts = imgPx.map { calculator.transformPoint($0, using: homography) }
        let (_, landing) = calculator.fitTrajectory(courtPts)
        let (result0, margin) = calculator.determineLanding(landing)
        // Spike (c): tight line calls aren't reliable here. Force `.uncertain`
        // when near a line OR the model isn't confident — never assert a verdict.
        let result: LandingResult = (margin < landingUncertainMargin || modelConfidence < landingConfidenceFloor)
            ? .uncertain : result0
        return LandingCall(point: landing, result: result, marginFromLine: margin, confidence: modelConfidence)
    }

    // MARK: - Fallback
    private func fallback(rallyIndex: Int, clipRef: ClipRef?) -> RallyResult {
        let side: Side = Bool.random() ? .sideA : .sideB
        let confidence = min(0.50, Double.random(in: 0.30...0.50))
        return RallyResult(
            rallyIndex: rallyIndex, winner: side, confidence: confidence,
            source: .cvPipeline, corroboration: .singleSignal,
            landing: nil, clipRef: clipRef,
            positionVote: nil, cvVote: SideVote(side: side, confidence: confidence),
            nextServeVerified: nil
        )
    }

    // MARK: - Calibration snapshot
    private struct CalibrationSnapshot: Sendable {
        let corners: [CGPoint]; let imageWidth: Double; let imageHeight: Double
    }
    private func snapshotCalibration() async -> CalibrationSnapshot? {
        guard let calibration else { return nil }
        return await MainActor.run {
            guard let corners = calibration.corners,
                  calibration.imageWidth > 0, calibration.imageHeight > 0
            else { return nil as CalibrationSnapshot? }
            return CalibrationSnapshot(corners: corners,
                                       imageWidth: calibration.imageWidth,
                                       imageHeight: calibration.imageHeight)
        }
    }
}
