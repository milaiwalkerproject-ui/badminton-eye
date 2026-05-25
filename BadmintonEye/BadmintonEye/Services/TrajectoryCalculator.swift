import Foundation

// MARK: - Types

struct CourtPoint: Codable, Sendable, Equatable {
    let x: Double  // court-space X (0.0 = left sideline, 1.0 = right sideline)
    let y: Double  // court-space Y (0.0 = near baseline, 1.0 = far baseline)
}

enum LandingResult: String, Codable, Sendable, Equatable {
    case inBounds    // green
    case outOfBounds // red
    case uncertain   // yellow
}

struct HawkEyeResult {
    let trajectoryPoints: [CourtPoint]  // shuttle path in court coordinates
    let landingPoint: CourtPoint        // predicted landing spot
    let landingResult: LandingResult    // IN / OUT / UNCERTAIN
    let confidence: Double              // 0.0 to 1.0
    let marginFromLine: Double          // distance from nearest line in court-normalized units
}

// MARK: - TrajectoryCalculator

/// Computes homography transforms, trajectory curve fitting, in/out determination,
/// and confidence scoring for Hawk Eye shuttle analysis.
struct TrajectoryCalculator {

    // MARK: - Homography

    /// Computes a 3x3 perspective transform matrix mapping image coordinates to normalized
    /// court coordinates (0-1 range). Solves the 8-equation system from 4 corner correspondences.
    /// Court corners map to (0,0), (1,0), (1,1), (0,1).
    func computeHomography(imageCorners: [CGPoint], imageSize: CGSize) -> [[Double]] {
        guard imageCorners.count == 4 else {
            return [[1, 0, 0], [0, 1, 0], [0, 0, 1]] // identity fallback
        }

        // Source points (image corners): TL, TR, BL, BR
        let src = imageCorners.map { (Double($0.x), Double($0.y)) }
        // Destination points (court normalized): TL=(0,0), TR=(1,0), BL=(0,1), BR=(1,1)
        let dst: [(Double, Double)] = [(0, 0), (1, 0), (0, 1), (1, 1)]

        // Build 8x8 system: for each correspondence (sx, sy) -> (dx, dy):
        //   dx = (h0*sx + h1*sy + h2) / (h6*sx + h7*sy + 1)
        //   dy = (h3*sx + h4*sy + h5) / (h6*sx + h7*sy + 1)
        // Rearranged:
        //   h0*sx + h1*sy + h2 - h6*sx*dx - h7*sy*dx = dx
        //   h3*sx + h4*sy + h5 - h6*sx*dy - h7*sy*dy = dy

        var a = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 8)
        var b = [Double](repeating: 0, count: 8)

        for i in 0..<4 {
            let (sx, sy) = src[i]
            let (dx, dy) = dst[i]

            a[i * 2]     = [sx, sy, 1, 0, 0, 0, -sx * dx, -sy * dx]
            b[i * 2]     = dx
            a[i * 2 + 1] = [0, 0, 0, sx, sy, 1, -sx * dy, -sy * dy]
            b[i * 2 + 1] = dy
        }

        // Solve via Gaussian elimination
        let h = solveLinearSystem(a, b)

        return [
            [h[0], h[1], h[2]],
            [h[3], h[4], h[5]],
            [h[6], h[7], 1.0]
        ]
    }

    /// Applies homography matrix to map an image-space point to court-space.
    func transformPoint(_ point: CGPoint, using homography: [[Double]]) -> CourtPoint {
        let px = Double(point.x)
        let py = Double(point.y)

        let w = homography[2][0] * px + homography[2][1] * py + homography[2][2]
        guard abs(w) > 1e-10 else { return CourtPoint(x: 0.5, y: 0.5) }

        let cx = (homography[0][0] * px + homography[0][1] * py + homography[0][2]) / w
        let cy = (homography[1][0] * px + homography[1][1] * py + homography[1][2]) / w

        return CourtPoint(x: cx, y: cy)
    }

    // MARK: - Trajectory Fitting

    /// Fits a smooth parabolic curve through detected points and extrapolates to the
    /// landing position. Uses quadratic interpolation for the y-component (gravity-like
    /// descent) and linear for x.
    func fitTrajectory(_ points: [CourtPoint]) -> (trajectory: [CourtPoint], landing: CourtPoint) {
        guard points.count >= 2 else {
            let fallback = CourtPoint(x: 0.5, y: 0.5)
            return (points, fallback)
        }

        let n = Double(points.count)
        let ts = points.indices.map { Double($0) / max(n - 1, 1) } // normalized 0...1

        // Linear fit for X: x = ax * t + bx
        let sumT = ts.reduce(0, +)
        let sumT2 = ts.map { $0 * $0 }.reduce(0, +)
        let sumX = points.map(\.x).reduce(0, +)
        let sumTX = zip(ts, points.map(\.x)).map(*).reduce(0, +)
        let detX = n * sumT2 - sumT * sumT
        let ax: Double
        let bx: Double
        if abs(detX) > 1e-10 {
            ax = (n * sumTX - sumT * sumX) / detX
            bx = (sumX * sumT2 - sumT * sumTX) / detX
        } else {
            ax = 0
            bx = points[0].x
        }

        // Quadratic fit for Y: y = ay*t^2 + by*t + cy
        let sumT3 = ts.map { $0 * $0 * $0 }.reduce(0, +)
        let sumT4 = ts.map { $0 * $0 * $0 * $0 }.reduce(0, +)
        let sumY = points.map(\.y).reduce(0, +)
        let sumTY = zip(ts, points.map(\.y)).map(*).reduce(0, +)
        let sumT2Y = zip(ts.map { $0 * $0 }, points.map(\.y)).map(*).reduce(0, +)

        // Solve 3x3 system for quadratic coefficients
        let mA: [[Double]] = [
            [sumT4, sumT3, sumT2],
            [sumT3, sumT2, sumT],
            [sumT2, sumT, n]
        ]
        let mB = [sumT2Y, sumTY, sumY]
        let yCoeffs = solveLinearSystem3x3(mA, mB)
        let ay = yCoeffs[0]
        let by = yCoeffs[1]
        let cy = yCoeffs[2]

        // Generate smooth trajectory with 30 points
        var trajectory = [CourtPoint]()
        for i in 0..<30 {
            let t = Double(i) / 29.0
            let x = ax * t + bx
            let y = ay * t * t + by * t + cy
            trajectory.append(CourtPoint(x: x, y: y))
        }

        // Extrapolate landing at t = 1.1 (slightly beyond last detected point)
        let tLand = 1.1
        let landX = ax * tLand + bx
        let landY = ay * tLand * tLand + by * tLand + cy
        let landing = CourtPoint(x: landX, y: landY)

        return (trajectory, landing)
    }

    // MARK: - In/Out Determination

    /// Checks if landing point is within court boundaries.
    /// Singles: x in 0.155...0.845, y in 0.0...1.0
    /// Doubles: x in 0.0...1.0
    /// Margin < 0.02 normalized units = uncertain.
    func determineLanding(_ point: CourtPoint) -> (result: LandingResult, margin: Double) {
        // Singles court boundaries (normalized)
        let singlesXMin = 0.155
        let singlesXMax = 0.845
        let yMin = 0.0
        let yMax = 1.0

        // Calculate distance from nearest boundary line
        let distances = [
            point.x - singlesXMin,   // distance from left singles line
            singlesXMax - point.x,   // distance from right singles line
            point.y - yMin,          // distance from near baseline
            yMax - point.y           // distance from far baseline
        ]

        let minDistance = distances.min() ?? 0
        let margin = abs(minDistance)

        if margin < 0.02 {
            return (.uncertain, margin)
        } else if minDistance < 0 {
            return (.outOfBounds, margin)
        } else {
            return (.inBounds, margin)
        }
    }

    // MARK: - Confidence Scoring

    /// Confidence based on detection count, video FPS, and margin from line.
    /// Formula: base = min(1.0, count/15) * 0.4 + min(1.0, fps/60) * 0.2 + min(1.0, margin/0.1) * 0.4
    func computeConfidence(detectionCount: Int, videoFPS: Double, margin: Double) -> Double {
        let countScore = min(1.0, Double(detectionCount) / 15.0) * 0.4
        let fpsScore = min(1.0, videoFPS / 60.0) * 0.2
        let marginScore = min(1.0, margin / 0.1) * 0.4
        return max(0.0, min(1.0, countScore + fpsScore + marginScore))
    }

    // MARK: - Linear Algebra Helpers

    /// Solves an NxN linear system via Gaussian elimination with partial pivoting.
    private func solveLinearSystem(_ a: [[Double]], _ b: [Double]) -> [Double] {
        let n = b.count
        var aug = a
        var rhs = b

        for col in 0..<n {
            // Partial pivoting
            var maxRow = col
            var maxVal = abs(aug[col][col])
            for row in (col + 1)..<n {
                if abs(aug[row][col]) > maxVal {
                    maxVal = abs(aug[row][col])
                    maxRow = row
                }
            }
            if maxRow != col {
                aug.swapAt(col, maxRow)
                rhs.swapAt(col, maxRow)
            }

            let pivot = aug[col][col]
            guard abs(pivot) > 1e-12 else { continue }

            // Eliminate below
            for row in (col + 1)..<n {
                let factor = aug[row][col] / pivot
                for k in col..<n {
                    aug[row][k] -= factor * aug[col][k]
                }
                rhs[row] -= factor * rhs[col]
            }
        }

        // Back substitution
        var x = [Double](repeating: 0, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            var sum = rhs[i]
            for j in (i + 1)..<n {
                sum -= aug[i][j] * x[j]
            }
            x[i] = abs(aug[i][i]) > 1e-12 ? sum / aug[i][i] : 0
        }
        return x
    }

    /// Solves a 3x3 linear system (for quadratic fitting).
    private func solveLinearSystem3x3(_ a: [[Double]], _ b: [Double]) -> [Double] {
        solveLinearSystem(a, b)
    }
}
