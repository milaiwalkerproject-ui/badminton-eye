import ActivityKit
import Foundation

struct MatchActivityAttributes: ActivityAttributes {
    // Static attributes set when Live Activity starts
    var teamAName: String
    var teamBName: String
    var format: String // "singles", "doubles", "mixed"

    struct ContentState: Codable, Hashable {
        var scoreA: Int
        var scoreB: Int
        var gameNumber: Int        // 1-indexed current game
        var gamesWonA: Int
        var gamesWonB: Int
        var serverSide: String     // "sideA" or "sideB"
        var isComplete: Bool
    }
}
