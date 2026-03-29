import Foundation
import SwiftData

@Model
final class PersistedMatch {
    var id: UUID = UUID()
    var format: String = "singles"
    var startedAt: Date = Date()
    var endedAt: Date?
    var stateJSON: Data?
    var isComplete: Bool = false
    var isAbandoned: Bool = false

    // Player names (all optional for CloudKit)
    var playerAName: String?
    var playerBName: String?
    var playerA2Name: String?
    var playerB2Name: String?

    // Final game scores (optional -- populated as games complete)
    var game1ScoreA: Int = 0
    var game1ScoreB: Int = 0
    var game2ScoreA: Int?
    var game2ScoreB: Int?
    var game3ScoreA: Int?
    var game3ScoreB: Int?

    init() {}
}
