// CourtCalibrationModels.swift
// Domain types for court calibration: CourtKeypoint, CourtCalibration,
// Homography, and CourtModel (world-coordinate reference).
//
// These types back CalibrationProfile (SwiftData model), CourtCalibrationView,
// and CourtDetector. They are separated from CalibrationProfile.swift to
// keep that file focused on persistence.

import CoreGraphics
import Foundation

// MARK: - CourtKeypoint

/// Named key points on a standard badminton court.
///
/// The 12 canonical key points describe every visible line intersection and
/// net post. They form the ground truth for the world↔image homography.
///
/// World coordinates follow a metre-based system where the origin is placed
/// at the near-left baseline corner (Top-Left when viewed from the near end):
///
///   x: [0, 6.1] — across the width of the full doubles court
///   y: [0, 13.4] — along the length (near baseline = 0, far baseline = 13.4)
enum CourtKeypoint: String, CaseIterable, Codable, Hashable {
    // Baselines
    case nearLeft               = "nearLeft"
    case nearRight              = "nearRight"
    case farLeft                = "farLeft"
    case farRight               = "farRight"

    // Short service lines (1.98 m from net)
    case shortServiceNearLeft   = "shortServiceNearLeft"
    case shortServiceNearRight  = "shortServiceNearRight"
    case shortServiceFarLeft    = "shortServiceFarLeft"
    case shortServiceFarRight   = "shortServiceFarRight"

    // Net posts
    case netLeft                = "netLeft"
    case netRight               = "netRight"

    // Center-line T intersections
    case centerLineNear         = "centerLineNear"
    case centerLineFar          = "centerLineFar"
}

// MARK: - CourtCalibration

/// Full camera-court calibration: 12 keypoints in image space plus
/// the world↔image homography pair and quality metric.
struct CourtCalibration: Equatable {
    /// Original image resolution used to produce this calibration.
    let imageSize: CGSize

    /// 3×3 homography mapping world (metre) coordinates → image (pixel) coordinates.
    let worldToImage: Homography

    /// 3×3 homography mapping image (pixel) coordinates → world (metre) coordinates.
    let imageToWorld: Homography

    /// Each keypoint's pixel position in the calibration image.
    let keypointsImagePx: [CourtKeypoint: CGPoint]

    /// RMS reprojection error in pixels for the input correspondences.
    /// Lower is better; values < 5 px are considered high quality.
    let rmsReprojectionErrorPx: Double

    /// Free-form notes about how the calibration was produced.
    let notes: String
}

// MARK: - Homography

/// Thin value wrapper around a 3×3 projective transformation matrix.
///
/// Matrices are stored row-major: `matrix[row][col]`.
///
/// Usage:
/// ```swift
/// let h = Homography(matrix: [[a,b,c],[d,e,f],[g,h,i]])
/// let imagePoint = h.project(worldPoint) // CGPoint in image space
/// ```
struct Homography: Equatable {
    /// 3×3 projective transformation stored row-major.
    let matrix: [[Double]]

    /// Creates a Homography from a 3×3 row-major matrix.
    /// - Precondition: `matrix.count == 3` and every row has exactly 3 elements.
    init(matrix: [[Double]]) {
        precondition(matrix.count == 3 && matrix.allSatisfy { $0.count == 3 },
                     "Homography requires a 3×3 matrix; got \(matrix.map(\.count))")
        self.matrix = matrix
    }

    /// Returns the identity homography (no transformation).
    static var identity: Homography {
        Homography(matrix: [[1,0,0],[0,1,0],[0,0,1]])
    }

    /// Applies the homography to a 2-D point using homogeneous coordinates.
    /// Returns a `CGPoint` after perspective-dividing by w.
    func project(_ point: CGPoint) -> CGPoint {
        let x = Double(point.x)
        let y = Double(point.y)
        let (m00,m01,m02) = (matrix[0][0], matrix[0][1], matrix[0][2])
        let (m10,m11,m12) = (matrix[1][0], matrix[1][1], matrix[1][2])
        let (m20,m21,m22) = (matrix[2][0], matrix[2][1], matrix[2][2])
        let xp = m00*x + m01*y + m02
        let yp = m10*x + m11*y + m12
        let  w = m20*x + m21*y + m22
        guard abs(w) > 1e-10 else { return .zero }
        return CGPoint(x: xp/w, y: yp/w)
    }
}

// MARK: - CourtModel

/// World-space (metre) reference layout for a standard BWF badminton court.
///
/// All measurements follow BWF Law 1 (Laws of Badminton). Coordinates use
/// a left-handed system with origin at the near-left corner of the doubles
/// sideline (x = across width, y = along length toward far end).
enum CourtModel {
    // Constant court dimensions (metres)
    static let courtWidth: Double  = 6.10   // doubles width
    static let courtLength: Double = 13.40  // full court length
    static let netY: Double        = courtLength / 2    // 6.70 m from near baseline
    static let shortServiceLineOffset: Double = 1.98    // from net
    static let longServiceLineDoubles: Double = 0.76    // from baseline
    static let singlesSidelineOffset: Double  = 0.46   // inset from doubles sideline

    // MARK: - World-space positions for each key point

    static let worldPositions: [CourtKeypoint: CGPoint] = {
        let w = courtWidth
        let l = courtLength
        let netPY = netY
        let ssl = shortServiceLineOffset
        return [
            .nearLeft:               CGPoint(x: 0, y: 0),
            .nearRight:              CGPoint(x: w, y: 0),
            .farLeft:                CGPoint(x: 0, y: l),
            .farRight:               CGPoint(x: w, y: l),
            .shortServiceNearLeft:   CGPoint(x: 0,   y: netPY - ssl),
            .shortServiceNearRight:  CGPoint(x: w,   y: netPY - ssl),
            .shortServiceFarLeft:    CGPoint(x: 0,   y: netPY + ssl),
            .shortServiceFarRight:   CGPoint(x: w,   y: netPY + ssl),
            .netLeft:                CGPoint(x: 0,   y: netPY),
            .netRight:               CGPoint(x: w,   y: netPY),
            .centerLineNear:         CGPoint(x: w/2, y: netPY - ssl),
            .centerLineFar:          CGPoint(x: w/2, y: netPY + ssl),
        ]
    }()

    /// The 4 keypoints the user taps in order during the calibration wizard.
    ///
    /// Order: near-left, near-right, far-right, far-left (clockwise from
    /// the camera's perspective).  These corners bound the short-service-box
    /// rectangle closest to the camera and are usually the most visible.
    static let calibrationTapOrder: [CourtKeypoint] = [
        .nearLeft,
        .nearRight,
        .shortServiceFarRight,
        .shortServiceFarLeft
    ]
}
