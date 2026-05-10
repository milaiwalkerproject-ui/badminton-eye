// CourtDetector.swift
// Computes world↔image homographies from user-supplied court corner taps.
//
// Phase S3 calibration flow:
//   1. User taps 4 corners in CourtCalibrationView (calibrationTapOrder)
//   2. CourtDetector.calibrateAndRefine() fits a 4-pt homography
//   3. Projects the full CourtModel.worldPositions → 12 image keypoints
//   4. Returns CourtCalibration persisted via CalibrationProfile.apply(...)

import CoreGraphics
import CoreVideo
import Foundation

// MARK: - CourtDetectorError

enum CourtDetectorError: Error, LocalizedError {
    case insufficientCorners(got: Int, need: Int)
    case degenerateGeometry(String)
    case homographySolveFailed

    var errorDescription: String? {
        switch self {
        case .insufficientCorners(let got, let need):
            return "Need \(need) corner taps to calibrate; got \(got)."
        case .degenerateGeometry(let detail):
            return "Degenerate tap geometry: \(detail). Re-tap the corners."
        case .homographySolveFailed:
            return "Homography solver failed. Ensure taps form a proper quadrilateral."
        }
    }
}

// MARK: - CourtDetector

/// Fits a projective homography between world-space (BWF court metres) and
/// image-space (pixel) coordinates using the 4 user-supplied corner taps.
///
/// The `calibrateAndRefine` method is the primary entry point. It:
///   1. Validates the 4 tap corners.
///   2. Solves a 4-point DLT homography (world→image).
///   3. Inverts it to get image→world.
///   4. Projects all 12 `CourtModel.worldPositions` through worldToImage to
///      populate `keypointsImagePx`.
///   5. Computes RMS reprojection error on the 4 tap correspondences.
///
/// The `pixelBuffer` parameter is accepted for API forward-compatibility but
/// contour-snap refinement is not yet wired (deferred to a later heartbeat).
enum CourtDetector {

    // MARK: - Public API

    /// Compute a full `CourtCalibration` from 4 tap corners.
    ///
    /// - Parameters:
    ///   - fromCornerTapsImagePx: 4 pixel-space tap points in `calibrationTapOrder`.
    ///   - imageSize: The image (view) size corresponding to the tap coordinates.
    ///   - pixelBuffer: Optional frame for contour-snap refinement (not yet used).
    ///
    /// - Returns: A `CourtCalibration` with world↔image homographies and all
    ///   12 projected keypoints.
    ///
    /// - Throws: `CourtDetectorError` if taps are insufficient or degenerate.
    static func calibrateAndRefine(
        fromCornerTapsImagePx taps: [CGPoint],
        imageSize: CGSize,
        pixelBuffer: CVPixelBuffer?
    ) throws -> CourtCalibration {

        guard taps.count == 4 else {
            throw CourtDetectorError.insufficientCorners(got: taps.count, need: 4)
        }

        // Corresponding world points for the 4 tap-order keypoints
        let tapOrder = CourtModel.calibrationTapOrder
        let worldPoints = tapOrder.compactMap { CourtModel.worldPositions[$0] }
        guard worldPoints.count == 4 else {
            throw CourtDetectorError.degenerateGeometry("CourtModel.calibrationTapOrder mismatch")
        }

        // Solve world→image homography via 4-point DLT
        let worldToImageMatrix = try solveDLT(srcPoints: worldPoints, dstPoints: taps)
        let worldToImage = Homography(matrix: worldToImageMatrix)

        // Invert for image→world
        let imageToWorldMatrix = try invertHomography(worldToImageMatrix)
        let imageToWorld = Homography(matrix: imageToWorldMatrix)

        // Project all 12 world keypoints through worldToImage
        var keypointsImagePx: [CourtKeypoint: CGPoint] = [:]
        for (kp, worldPt) in CourtModel.worldPositions {
            keypointsImagePx[kp] = worldToImage.project(worldPt)
        }

        // RMS reprojection error on the 4 tap correspondences
        let rmsError = computeRMSError(
            srcPoints: worldPoints,
            dstPoints: taps,
            homography: worldToImage
        )

        return CourtCalibration(
            imageSize: imageSize,
            worldToImage: worldToImage,
            imageToWorld: imageToWorld,
            keypointsImagePx: keypointsImagePx,
            rmsReprojectionErrorPx: rmsError,
            notes: "4-pt DLT calibration from \(taps.count) taps"
        )
    }

    // MARK: - 4-Point DLT Homography Solver

    /// Solves for a 3×3 homography H such that dst[i] ≈ H * src[i] for 4 pairs.
    ///
    /// Uses the Direct Linear Transform (DLT) formulation with 4 point pairs
    /// (exactly determined). Returns the matrix in row-major [[Double]] form.
    private static func solveDLT(
        srcPoints: [CGPoint],
        dstPoints: [CGPoint]
    ) throws -> [[Double]] {
        precondition(srcPoints.count == 4 && dstPoints.count == 4)

        // Build 8×9 DLT matrix A
        // Each correspondence (xS,yS) → (xD,yD) yields 2 rows of A
        var A = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)
        for i in 0..<4 {
            let xS = Double(srcPoints[i].x)
            let yS = Double(srcPoints[i].y)
            let xD = Double(dstPoints[i].x)
            let yD = Double(dstPoints[i].y)

            // Row 2i:   [-xS, -yS, -1, 0, 0, 0, xD*xS, xD*yS, xD]
            A[2*i]   = [-xS, -yS, -1,   0,   0,  0, xD*xS, xD*yS, xD]
            // Row 2i+1: [0, 0, 0, -xS, -yS, -1, yD*xS, yD*yS, yD]
            A[2*i+1] = [  0,   0,  0, -xS, -yS, -1, yD*xS, yD*yS, yD]
        }

        // Solve via SVD-free Gaussian elimination (exact for 4 pairs, no noise)
        // Augment A with identity to solve A·h = 0 via least-squares back-sub
        guard let h = solveHomogeneous8x9(A) else {
            throw CourtDetectorError.homographySolveFailed
        }

        return [[h[0], h[1], h[2]],
                [h[3], h[4], h[5]],
                [h[6], h[7], h[8]]]
    }

    /// Solves the 8×9 homogeneous system using Gaussian elimination with
    /// partial pivoting. Returns the 9-element null-space vector (normalised
    /// so h[8] = 1) or nil if the system is degenerate.
    private static func solveHomogeneous8x9(_ A: [[Double]]) -> [Double]? {
        var mat = A.map { row in row + [0.0] }   // 8×9 (no augmentation needed)

        // We solve A·h = 0 with the constraint h[8]=1 by substituting h[8]=1:
        // Move last column to RHS → 8 unknowns, 8 equations
        var rhs = [Double](repeating: 0, count: 8)
        for i in 0..<8 {
            rhs[i] = -mat[i][8]
        }
        var sub = mat.map { Array($0[0..<8]) }   // 8×8 submatrix

        // Gaussian elimination with partial pivoting
        for col in 0..<8 {
            // Find pivot
            var maxRow = col
            for row in (col+1)..<8 {
                if abs(sub[row][col]) > abs(sub[maxRow][col]) { maxRow = row }
            }
            sub.swapAt(col, maxRow)
            rhs.swapAt(col, maxRow)

            guard abs(sub[col][col]) > 1e-12 else { return nil }

            for row in (col+1)..<8 {
                let factor = sub[row][col] / sub[col][col]
                for c in col..<8 { sub[row][c] -= factor * sub[col][c] }
                rhs[row] -= factor * rhs[col]
            }
        }

        // Back substitution
        var h = [Double](repeating: 0, count: 9)
        h[8] = 1.0
        for i in stride(from: 7, through: 0, by: -1) {
            var sum = rhs[i]
            for j in (i+1)..<8 { sum -= sub[i][j] * h[j] }
            guard abs(sub[i][i]) > 1e-12 else { return nil }
            h[i] = sum / sub[i][i]
        }
        return h
    }

    // MARK: - Homography Inversion

    /// Analytically inverts a 3×3 matrix via cofactors.
    /// Throws `homographySolveFailed` if the matrix is singular.
    private static func invertHomography(_ m: [[Double]]) throws -> [[Double]] {
        let a = m[0][0]; let b = m[0][1]; let c = m[0][2]
        let d = m[1][0]; let e = m[1][1]; let f = m[1][2]
        let g = m[2][0]; let h = m[2][1]; let i = m[2][2]

        let det = a*(e*i - f*h) - b*(d*i - f*g) + c*(d*h - e*g)
        guard abs(det) > 1e-15 else { throw CourtDetectorError.homographySolveFailed }

        let inv_det = 1.0 / det
        return [
            [(e*i - f*h)*inv_det, (c*h - b*i)*inv_det, (b*f - c*e)*inv_det],
            [(f*g - d*i)*inv_det, (a*i - c*g)*inv_det, (c*d - a*f)*inv_det],
            [(d*h - e*g)*inv_det, (b*g - a*h)*inv_det, (a*e - b*d)*inv_det]
        ]
    }

    // MARK: - Error Metric

    private static func computeRMSError(
        srcPoints: [CGPoint],
        dstPoints: [CGPoint],
        homography: Homography
    ) -> Double {
        var sumSq = 0.0
        for (src, dst) in zip(srcPoints, dstPoints) {
            let projected = homography.project(src)
            let dx = Double(projected.x - dst.x)
            let dy = Double(projected.y - dst.y)
            sumSq += dx*dx + dy*dy
        }
        return sqrt(sumSq / Double(srcPoints.count))
    }
}
