import Foundation
import SwiftData

@Model
final class CalibrationProfile {
    var id: UUID = UUID()
    var venueName: String = ""
    var cornerTopLeft: Data?
    var cornerTopRight: Data?
    var cornerBottomLeft: Data?
    var cornerBottomRight: Data?
    var createdAt: Date = Date()
    var imageWidth: Double = 0
    var imageHeight: Double = 0

    init() {}

    // MARK: - Computed Corners

    /// Decodes all 4 corner Data fields into CGPoints, returning nil if any corner is missing.
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
