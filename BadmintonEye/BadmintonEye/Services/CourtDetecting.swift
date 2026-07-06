import CoreGraphics
import CoreVideo
import Foundation

// MARK: - DetectedCourt

/// A detected badminton-court outline.
///
/// `corners` are four points in NORMALIZED capture-device space (x,y in
/// `[0,1]`, **top-left origin**), ordered clockwise from the top-left **of the
/// buffer's own (sensor) orientation**: `[topLeft, topRight, bottomRight,
/// bottomLeft]`. When the preview is rotated relative to the sensor (90° in
/// portrait), the buffer-space top-left is NOT the on-screen top-left, so
/// consumers that need the manual 4-tap screen order must re-canonicalize
/// after converting to view space (see `CourtCalibrationView.autoDetectCourt`).
struct DetectedCourt: Equatable, Sendable {
    /// Clockwise from top-left: `[TL, TR, BR, BL]`.
    let corners: [CGPoint]
    /// Detector confidence in `[0, 1]`.
    let confidence: Double

    static let cornerCount = 4
}

// MARK: - CourtDetecting

/// Abstraction over "find the court in a camera frame", mirroring the
/// `ShuttleDetecting` seam so the calibration UI and tests can swap a real
/// Vision detector for a stub without a camera.
protocol CourtDetecting: Sendable {
    /// Detect the most likely court quadrilateral in a camera frame.
    /// Returns `nil` when no sufficiently-confident court rectangle is found.
    func detectCourt(in pixelBuffer: CVPixelBuffer) async -> DetectedCourt?
}

// MARK: - CourtGeometry (pure — unit-tested in CourtDetectionTests)

/// Pure, dependency-free helpers for turning raw detected corner points into
/// the calibration convention. Kept separate from Vision so every coordinate
/// transform and selection rule is testable without a camera.
enum CourtGeometry {

    /// Flip a Vision-normalized point (origin **bottom-left**) into
    /// capture-device space (origin **top-left**). `x` is unchanged; `y` is
    /// mirrored. This is the same flip `CoreMLShuttleDetector` applies.
    static func topLeftOrigin(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: 1.0 - p.y)
    }

    /// Order four arbitrary corner points clockwise starting from the
    /// top-left: `[TL, TR, BR, BL]`.
    ///
    /// Uses the classic `x ± y` extremes (the same approach as OpenCV's
    /// `order_points`), which is robust to perspective skew and to whatever
    /// order the detector emitted. Coordinates are assumed top-left origin
    /// (`y` grows downward). Returns `nil` for a non-quad or a degenerate
    /// detection where one point would fill two roles.
    static func orderedClockwise(_ points: [CGPoint]) -> [CGPoint]? {
        guard points.count == 4 else { return nil }
        // TL has the smallest (x + y); BR the largest (x + y).
        // TR has the largest (x − y); BL the smallest (x − y).
        let tl = points.min { ($0.x + $0.y) < ($1.x + $1.y) }!
        let br = points.max { ($0.x + $0.y) < ($1.x + $1.y) }!
        let tr = points.max { ($0.x - $0.y) < ($1.x - $1.y) }!
        let bl = points.min { ($0.x - $0.y) < ($1.x - $1.y) }!
        let ordered = [tl, tr, br, bl]
        return hasDuplicate(ordered) ? nil : ordered
    }

    private static func hasDuplicate(_ pts: [CGPoint], tol: CGFloat = 1e-6) -> Bool {
        for i in 0..<pts.count {
            for j in (i + 1)..<pts.count where abs(pts[i].x - pts[j].x) < tol && abs(pts[i].y - pts[j].y) < tol {
                return true
            }
        }
        return false
    }

    /// Area of a quad via the shoelace formula (normalized units). Used to
    /// prefer the largest plausible court rectangle and reject slivers.
    static func quadArea(_ pts: [CGPoint]) -> Double {
        guard pts.count == 4 else { return 0 }
        var area = 0.0
        for i in 0..<4 {
            let a = pts[i], b = pts[(i + 1) % 4]
            area += Double(a.x * b.y - b.x * a.y)
        }
        return abs(area) / 2.0
    }

    /// Choose the best court candidate: the highest-confidence quad among those
    /// meeting BOTH a minimum confidence and a minimum normalized area,
    /// tie-broken by larger area. Pure so the selection policy is testable
    /// without Vision.
    static func bestCandidate(_ candidates: [DetectedCourt],
                              minConfidence: Double,
                              minArea: Double) -> DetectedCourt? {
        candidates
            .filter { $0.confidence >= minConfidence && quadArea($0.corners) >= minArea }
            .max { lhs, rhs in
                lhs.confidence == rhs.confidence
                    ? quadArea(lhs.corners) < quadArea(rhs.corners)
                    : lhs.confidence < rhs.confidence
            }
    }

    /// Map a normalized, top-left-origin point onto a view-space point for an
    /// `.resizeAspectFill` preview of `imageSize` shown in `viewSize`.
    ///
    /// This reproduces the math `AVCaptureVideoPreviewLayer` performs and is
    /// used only as a fallback for when no preview layer is available (the live
    /// view uses the layer's own, rotation-aware conversion). Provided here so
    /// the aspect-fill mapping is unit-testable.
    static func aspectFillViewPoint(normalized p: CGPoint,
                                    imageSize: CGSize,
                                    viewSize: CGSize) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else {
            return CGPoint(x: p.x * viewSize.width, y: p.y * viewSize.height)
        }
        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaledW = imageSize.width * scale
        let scaledH = imageSize.height * scale
        let dx = (scaledW - viewSize.width) / 2.0
        let dy = (scaledH - viewSize.height) / 2.0
        return CGPoint(x: p.x * scaledW - dx, y: p.y * scaledH - dy)
    }
}

// MARK: - PlaceholderCourtDetector (previews / tests / no-camera)

/// A no-op court detector that returns a configurable result, so UI code paths
/// and tests can be exercised without Vision or a live camera (mirrors
/// `PlaceholderShuttleDetector`).
struct PlaceholderCourtDetector: CourtDetecting {
    var result: DetectedCourt?
    init(result: DetectedCourt? = nil) { self.result = result }
    func detectCourt(in pixelBuffer: CVPixelBuffer) async -> DetectedCourt? { result }
}
