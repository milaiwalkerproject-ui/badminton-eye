import Foundation
import SwiftData

@Model
final class CalibrationProfile {
    var id: UUID = UUID()
    var venueName: String = ""
    // HISTORICAL FIELD CROSSING — do not "tidy". The bottom two field names are
    // crossed relative to their contents: `cornerBottomLeft` persists the 3rd
    // calibration tap (the image bottom-RIGHT corner) and `cornerBottomRight`
    // persists the 4th tap (bottom-LEFT). The `corners` accessor below reads the
    // fields in declaration order, which re-inverts the crossing and yields the
    // clockwise tap order [TL, TR, BR, BL]. DO NOT rename these fields: they are
    // SwiftData store columns / CloudKit record fields for profiles already saved
    // on user devices (CloudKit cannot rename fields, and cross-swapping two
    // attribute names is unsafe for lightweight migration).
    var cornerTopLeft: Data?
    var cornerTopRight: Data?
    var cornerBottomLeft: Data?
    var cornerBottomRight: Data?
    var createdAt: Date = Date()
    var imageWidth: Double = 0
    var imageHeight: Double = 0

    @Relationship(inverse: \PersistedMatch.calibration)
    var match: PersistedMatch?

    init() {}

    // MARK: - Computed Corners

    /// Decodes all 4 corner Data fields into CGPoints, returning nil if any corner
    /// is missing. Returns the corners in CLOCKWISE tap order [top-left, top-right,
    /// bottom-right, bottom-left] — exactly what `TrajectoryCalculator.computeHomography`
    /// requires. Reading the fields in declaration order re-inverts the historical
    /// field crossing documented above — the body must not be reordered to match
    /// the field names.
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

    // MARK: - Set Corners

    /// Encodes each CGPoint as JSON Data and stores image dimensions.
    /// `corners` must be in CLOCKWISE order [TL, TR, BR, BL] — the
    /// `CourtCalibrationView` tap order / `CourtGeometry.orderedClockwise` order.
    /// The positional field assignment below is intentional (corners[2] → the
    /// crossed `cornerBottomLeft` field) to keep on-disk semantics identical to
    /// every profile saved since v1.
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
}

// MARK: - CodablePoint Helper

/// Codable wrapper for CGPoint to enable JSON serialization into Data.
private struct CodablePoint: Codable {
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
