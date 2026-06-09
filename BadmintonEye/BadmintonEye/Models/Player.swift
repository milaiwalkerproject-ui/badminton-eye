import Foundation
import SwiftData

@Model
final class Player {
    var id: UUID = UUID()
    var name: String = ""
    // `.externalStorage` keeps photo bytes out of the row so player list
    // queries stay cheap. Lightweight-migration-safe (verified on a populated
    // old-schema store). Legacy NULL photos surface as EMPTY Data after
    // migration; consumers already treat that as "no photo" because
    // `UIImage(data:)` returns nil for empty data.
    @Attribute(.externalStorage) var photoData: Data?
    var createdAt: Date = Date()

    // CloudKit-safe: all properties optional or have defaults
    init() {}
}
