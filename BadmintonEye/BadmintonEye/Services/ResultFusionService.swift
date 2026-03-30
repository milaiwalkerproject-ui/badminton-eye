import Foundation

/// Fuses multiple HawkEyeResult instances from different camera angles
/// into a single higher-confidence landing prediction.
struct ResultFusionService {

    /// Fuse independent Hawk Eye results into a single combined result.
    /// Uses weighted average based on per-angle confidence.
    static func fuse(_ results: [HawkEyeResult]) -> HawkEyeResult {
        guard !results.isEmpty else {
            fatalError("ResultFusionService.fuse requires at least one result")
        }
        guard results.count > 1 else {
            return results[0]
        }

        let totalConfidence = results.reduce(0.0) { $0 + $1.confidence }
        guard totalConfidence > 0 else { return results[0] }

        // Weighted average landing point
        var fusedX: Double = 0
        var fusedY: Double = 0
        for result in results {
            let weight = result.confidence / totalConfidence
            fusedX += result.landingPoint.x * weight
            fusedY += result.landingPoint.y * weight
        }
        let fusedLanding = CourtPoint(x: fusedX, y: fusedY)

        // Fused confidence: higher than any single angle (multi-view bonus)
        let maxConfidence = results.map(\.confidence).max() ?? 0
        let fusedConfidence = min(maxConfidence * 1.15, 0.99) // 15% boost, capped at 99%

        // Use landing result from highest-confidence angle
        let bestResult = results.max(by: { $0.confidence < $1.confidence })!

        // Merge trajectory points from all angles
        let mergedTrajectory = results.flatMap(\.trajectoryPoints)

        return HawkEyeResult(
            trajectoryPoints: mergedTrajectory,
            landingPoint: fusedLanding,
            landingResult: bestResult.landingResult,
            confidence: fusedConfidence,
            marginFromLine: bestResult.marginFromLine
        )
    }
}
