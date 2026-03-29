import Foundation
import SwiftData

@Model
final class Player {
    var id: UUID = UUID()
    var name: String = ""
    var photoData: Data?
    var createdAt: Date = Date()

    // CloudKit-safe: all properties optional or have defaults
    init() {}
}
