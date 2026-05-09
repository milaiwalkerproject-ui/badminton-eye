import Foundation
import SwiftData
import WidgetKit

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

    init() {}
}

// MARK: - App Group / Widget data wiring

/// Helpers that write shared data into the App Group container so that the
/// BadmintonEyeWidget extension can read it without needing SwiftData access.
///
/// Call `PersistedMatch.writeLiveScore(_:)` from `LiveMatchViewModel.persistState()`
/// after every scored point, and `PersistedMatch.writeWinRateSummary(from:)` after
/// every match completes.
extension PersistedMatch {

    // MARK: Live score

    /// Writes a live score snapshot to the shared App Group UserDefaults and
    /// reloads all WidgetKit timelines so the widget reflects the new score.
    ///
    /// - Parameters:
    ///   - scoreA: Current game score for Side A.
    ///   - scoreB: Current game score for Side B.
    ///   - sideAName: Display name for Side A.
    ///   - sideBName: Display name for Side B.
    ///   - serverSide: "sideA" or "sideB" — which side is currently serving.
    ///   - gameNumber: 1-based index of the game currently in progress.
    ///   - gamesWonA: Number of completed games won by Side A.
    ///   - gamesWonB: Number of completed games won by Side B.
    ///   - isComplete: Pass `true` when the match has just ended.
    static func writeLiveScore(
        scoreA: Int,
        scoreB: Int,
        sideAName: String,
        sideBName: String,
        serverSide: String,
        gameNumber: Int,
        gamesWonA: Int,
        gamesWonB: Int,
        isComplete: Bool
    ) {
        let snapshot = LiveScoreData(
            sideAName: sideAName,
            sideBName: sideBName,
            scoreA: scoreA,
            scoreB: scoreB,
            serverSide: serverSide,
            gameNumber: gameNumber,
            gamesWonA: gamesWonA,
            gamesWonB: gamesWonB,
            isComplete: isComplete,
            updatedAt: Date()
        )
        snapshot.save()
        WidgetCenter.shared.reloadTimelines(ofKind: "LiveScoreWidget")
    }

    // MARK: Win-rate summary

    /// Recalculates and writes the win-rate summary from a list of completed matches.
    ///
    /// Call this after every match completion / abandonment so the WinRateSummaryWidget
    /// always reflects the latest history.
    ///
    /// - Parameter matches: All `PersistedMatch` objects that have `isComplete == true`.
    static func writeWinRateSummary(from matches: [PersistedMatch]) {
        let completed = matches.filter { $0.isComplete }
        let wins = completed.filter { $0.winnerSide == "sideA" }.count
        let summary = WinRateSummaryData(
            totalMatches: completed.count,
            wins: wins,
            losses: completed.count - wins,
            updatedAt: Date()
        )
        summary.save()
        WidgetCenter.shared.reloadTimelines(ofKind: "WinRateSummaryWidget")
    }
}
