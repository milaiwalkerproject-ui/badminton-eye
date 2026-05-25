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
    var game4ScoreA: Int?
    var game4ScoreB: Int?
    var game5ScoreA: Int?
    var game5ScoreB: Int?

    // Scoring system JSON — stores encoded ScoringSystem for custom rules support
    // Defaults to "standard21" string for backward compat with CloudKit
    var scoringSystemRaw: String = "standard21"

    // Custom rules JSON (nil for standard formats, populated for custom)
    var customRulesJSON: Data?

    // Winner side ("sideA" or "sideB"), set on match completion for efficient list rendering
    var winnerSide: String?

    // Court calibration captured at match start. Optional so existing rows
    // (and matches started without calibration) still load.
    var calibration: CalibrationProfile?

    // Per-game recorded video files (Footage feature). Cascade delete so
    // removing a match also removes its footage rows. Optional array keeps
    // the CloudKit migration additive for existing rows.
    @Relationship(deleteRule: .cascade, inverse: \GameVideoRecord.match)
    var gameVideos: [GameVideoRecord]? = []

    init() {}
}
