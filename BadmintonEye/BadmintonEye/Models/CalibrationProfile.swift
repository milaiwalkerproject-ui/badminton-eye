import Foundation
import SwiftData
import CoreGraphics

/// Persisted court calibration for a venue.
///
/// `CalibrationProfile` is the SwiftData backing store for a single
/// camera-angle court calibration. It is written from the calibration UI
/// (`CourtCalibrationView`) and consumed by the live in/out call pipeline.
///
/// Storage is layered for backward compatibility:
///   * The original 4-corner tap fields (`cornerTopLeft`/.../`cornerBottomRight`)
///     are still written via `setCorners(...)` so existing v1 CalibrationProfile
///     rows continue to read cleanly.
///   * The Phase S3 fields (`keypointsData`, `homographyData`,
///     `rmsReprojectionErrorPx`, `calibrationNotes`) capture the full
///     :class:`CourtCalibration` — all 12 named keypoints + the world↔image
///     homography pair + the calibration's reprojection error + free-form
///     notes about how it was produced.
///   * `apply(calibration:venueName:)` writes both layers in one shot;
///     `calibration` reconstructs a usable :class:`CourtCalibration` from
///     the v2 fields.
///
/// SwiftData adds the new optional properties via lightweight migration; rows
/// from app builds prior to Phase S3 simply read back nil for the new fields,
/// in which case `calibration` returns nil and callers should fall back to
/// recalibrating (or to the legacy `corners` accessor).
@Model
final class CalibrationProfile {
    var id: UUID = UUID()
    var venueName: String = ""

    // MARK: - v1 storage (4 corner taps)
    var cornerTopLeft: Data?
    var cornerTopRight: Data?
    var cornerBottomLeft: Data?
    var cornerBottomRight: Data?
    var createdAt: Date = Date()
    var imageWidth: Double = 0
    var imageHeight: Double = 0

    // MARK: - v2 storage (Phase S3 — full 12-keypoint calibration)

    /// JSON-encoded `[String: CodablePoint]` mapping
    /// `CourtKeypoint.rawValue` → image-space pixel position.
    var keypointsData: Data?

    /// JSON-encoded `HomographyPayload` containing both the world→image and
    /// image→world 3×3 matrices.
    var homographyData: Data?

    /// RMS reprojection error in pixels for the input correspondences used
    /// to solve the homography.
    var rmsReprojectionErrorPx: Double = 0

    /// Free-form notes about how the calibration was produced (e.g.
    /// "4-pt calibration from 4 taps" or "DLT refinement over 12 correspondences").
    var calibrationNotes: String = ""

    init() {}

    // MARK: - Computed Corners (v1)

    /// Decodes all 4 corner Data fields into CGPoints, returning nil if any
    /// corner is missing.
    var corners: [CGPoint]? {
        guard let tlData = cornerTopLeft,
              let trData = cornerTopRight,
              let blData = cornerBottomLeft,
              let brData = cornerBottomRight else {
            return nil
        }

        let decoder = JSONDecoder()
        guard let tl = try? decoder.decode(CodablePoint.self, from: tlData),
              let tr = try? decoder.decode(CodablePoint.self, from: trData),
              let bl = try? decoder.decode(CodablePoint.self, from: blData),
              let br = try? decoder.decode(CodablePoint.self, from: brData) else {
            return nil
        }

        return [tl.cgPoint, tr.cgPoint, bl.cgPoint, br.cgPoint]
    }

    // MARK: - Set Corners (v1)

    /// Encodes each CGPoint as JSON Data and stores image dimensions.
    /// Preserved for backward compatibility with v1 callers.
    func setCorners(_ corners: [CGPoint], imageSize: CGSize) {
        guard corners.count == 4 else { return }
        let encoder = JSONEncoder()
        cornerTopLeft = try? encoder.encode(CodablePoint(corners[0]))
        cornerTopRight = try? encoder.encode(CodablePoint(corners[1]))
        cornerBottomLeft = try? encoder.encode(CodablePoint(corners[2]))
        cornerBottomRight = try? encoder.encode(CodablePoint(corners[3]))
        imageWidth = Double(imageSize.width)
        imageHeight = Double(imageSize.height)
    }

    // MARK: - Apply / restore CourtCalibration (v2)

    /// Persist a full :class:`CourtCalibration` (12 keypoints + homography
    /// pair + RMS error + notes), set the venue name, and also write the
    /// 4 tap corners so v1 readers continue to work.
    ///
    /// - Parameter calibration: The Phase S3 calibration produced by
    ///   `CourtDetector.calibrate(...)` or `CourtDetector.calibrateAndRefine(...)`.
    /// - Parameter venueName: Trimmed venue label.
    ///
    /// Encoding errors are silently absorbed — keypointsData / homographyData
    /// will be nil and `calibration` will return nil for the read-back. In
    /// practice JSONEncoder will not fail for this fixed shape, so this only
    /// matters as defensive defaulting.
    func apply(calibration: CourtCalibration, venueName: String) {
        self.venueName = venueName
        self.imageWidth = Double(calibration.imageSize.width)
        self.imageHeight = Double(calibration.imageSize.height)
        self.rmsReprojectionErrorPx = calibration.rmsReprojectionErrorPx
        self.calibrationNotes = calibration.notes

        // Write the 4 tap corners for backward compatibility.
        let tapOrder = CourtModel.calibrationTapOrder
        let tapCorners = tapOrder.compactMap { calibration.keypointsImagePx[$0] }
        if tapCorners.count == 4 {
            setCorners(tapCorners, imageSize: calibration.imageSize)
        }

        let encoder = JSONEncoder()

        // Encode all 12 keypoints, keyed by rawValue for forward-compat
        // (new keypoints can be added to CourtKeypoint without breaking
        // older stored rows).
        var rawDict: [String: CodablePoint] = [:]
        for (kp, pt) in calibration.keypointsImagePx {
            rawDict[kp.rawValue] = CodablePoint(pt)
        }
        keypointsData = try? encoder.encode(rawDict)

        let homoPayload = HomographyPayload(
            worldToImage: calibration.worldToImage.matrix,
            imageToWorld: calibration.imageToWorld.matrix
        )
        homographyData = try? encoder.encode(homoPayload)
    }

    /// Reconstruct a :class:`CourtCalibration` from the v2 storage fields.
    ///
    /// Returns nil when:
    ///   * The profile predates Phase S3 (keypointsData / homographyData are nil).
    ///   * Image dimensions weren't recorded (cannot project a meaningful overlay).
    ///   * The stored JSON is corrupted or has the wrong shape.
    ///
    /// Note: profiles with v1-only data (4 corners but no v2 keypoints) return
    /// nil here. Callers needing those should re-run `CourtDetector.calibrate(
    /// fromCornerTapsImagePx:)` against the v1 `corners` and then `apply(...)`
    /// the result back.
    var calibration: CourtCalibration? {
        guard let kpData = keypointsData,
              let homoData = homographyData,
              imageWidth > 0,
              imageHeight > 0 else {
            return nil
        }

        let decoder = JSONDecoder()
        guard
            let rawDict = try? decoder.decode(
                [String: CodablePoint].self,
                from: kpData
            ),
            let homoPayload = try? decoder.decode(
                HomographyPayload.self,
                from: homoData
            ),
            HomographyPayload.isWellFormed(homoPayload.worldToImage),
            HomographyPayload.isWellFormed(homoPayload.imageToWorld)
        else {
            return nil
        }

        var keypoints: [CourtKeypoint: CGPoint] = [:]
        for (raw, codable) in rawDict {
            guard let kp = CourtKeypoint(rawValue: raw) else { continue }
            keypoints[kp] = codable.cgPoint
        }

        return CourtCalibration(
            imageSize: CGSize(width: imageWidth, height: imageHeight),
            worldToImage: Homography(matrix: homoPayload.worldToImage),
            imageToWorld: Homography(matrix: homoPayload.imageToWorld),
            keypointsImagePx: keypoints,
            rmsReprojectionErrorPx: rmsReprojectionErrorPx,
            notes: calibrationNotes
        )
    }
}

// MARK: - CodablePoint Helper

/// Codable wrapper for CGPoint to enable JSON serialization into Data.
fileprivate struct CodablePoint: Codable {
    let x: Double
    let y: Double

    init(_ point: CGPoint) {
        self.x = Double(point.x)
        self.y = Double(point.y)
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

// MARK: - HomographyPayload

/// Codable wire format for a pair of 3×3 homography matrices.
fileprivate struct HomographyPayload: Codable {
    let worldToImage: [[Double]]
    let imageToWorld: [[Double]]

    /// Validate that a decoded matrix has the 3×3 shape `Homography(matrix:)`
    /// expects so `Homography.init` doesn't trip its preconditions and
    /// crash the app on a corrupt SwiftData row.
    static func isWellFormed(_ matrix: [[Double]]) -> Bool {
        guard matrix.count == 3 else { return false }
        return matrix.allSatisfy { $0.count == 3 }
    }
}
