import Foundation
import ScoringEngine

/// Wraps CodableMatchState with metadata for WatchConnectivity transport.
/// Encodes to a [String: Any] dictionary suitable for updateApplicationContext / sendMessage.
struct SyncPayload: Codable {
    let matchState: CodableMatchState
    let timestamp: TimeInterval
    let isMatchActive: Bool

    init(from state: MatchState, isActive: Bool) {
        self.matchState = CodableMatchState(from: state)
        self.timestamp = Date().timeIntervalSince1970
        self.isMatchActive = isActive
    }

    /// Encode to dictionary for WatchConnectivity transport.
    func toDictionary() -> [String: Any] {
        let data = try! JSONEncoder().encode(self)
        return ["syncPayload": data]
    }

    /// Decode from WatchConnectivity dictionary.
    static func from(dictionary: [String: Any]) -> SyncPayload? {
        guard let data = dictionary["syncPayload"] as? Data else { return nil }
        return try? JSONDecoder().decode(SyncPayload.self, from: data)
    }
}
