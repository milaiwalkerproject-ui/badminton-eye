import Foundation

// MARK: - App Group identifier

/// The shared App Group container used to pass live match data between the main app and widget extension.
/// Both the app target and the BadmintonEyeWidget target must have this App Group capability enabled in Xcode.
let sharedAppGroupID = "group.com.badmintoneye.shared"

// MARK: - UserDefaults key constants

enum SharedMatchKeys {
    static let liveScore = "liveMatchScore"
    static let winRateSummary = "winRateSummary"
}

// MARK: - Live score data

/// Snapshot of the current live game score written by the main app on every point.
struct LiveScoreData: Codable {
    /// Display name for Side A (first player / team).
    var sideAName: String
    /// Display name for Side B (second player / team).
    var sideBName: String
    /// Current game score for Side A.
    var scoreA: Int
    /// Current game score for Side B.
    var scoreB: Int
    /// Side that is currently serving: "sideA" or "sideB".
    var serverSide: String
    /// 1-based game number that is currently in progress.
    var gameNumber: Int
    /// Games won by Side A across all completed games.
    var gamesWonA: Int
    /// Games won by Side B across all completed games.
    var gamesWonB: Int
    /// Whether the match has finished.
    var isComplete: Bool
    /// UTC timestamp of the last update — used by the widget timeline to know how stale the data is.
    var updatedAt: Date

    // MARK: Convenience

    var serverLabel: String {
        serverSide == "sideA" ? sideAName : sideBName
    }

    // MARK: Persistence helpers

    /// Reads a `LiveScoreData` value from the shared App Group UserDefaults.
    static func load() -> LiveScoreData? {
        guard
            let defaults = UserDefaults(suiteName: sharedAppGroupID),
            let data = defaults.data(forKey: SharedMatchKeys.liveScore)
        else { return nil }
        return try? JSONDecoder().decode(LiveScoreData.self, from: data)
    }

    /// Writes this value to the shared App Group UserDefaults and reloads all widget timelines.
    func save() {
        guard
            let defaults = UserDefaults(suiteName: sharedAppGroupID),
            let data = try? JSONEncoder().encode(self)
        else { return }
        defaults.set(data, forKey: SharedMatchKeys.liveScore)
    }

    /// A stable placeholder used when no live match is in progress.
    static var placeholder: LiveScoreData {
        LiveScoreData(
            sideAName: "Side A",
            sideBName: "Side B",
            scoreA: 15,
            scoreB: 12,
            serverSide: "sideA",
            gameNumber: 1,
            gamesWonA: 0,
            gamesWonB: 0,
            isComplete: false,
            updatedAt: Date()
        )
    }
}

// MARK: - Win-rate summary data

/// Aggregate win/loss record stored in the shared App Group container.
/// The main app writes this after every completed match.
struct WinRateSummaryData: Codable {
    var totalMatches: Int
    var wins: Int
    var losses: Int
    var updatedAt: Date

    var winRate: Double {
        guard totalMatches > 0 else { return 0 }
        return Double(wins) / Double(totalMatches)
    }

    var winRatePercent: Int {
        Int((winRate * 100).rounded())
    }

    // MARK: Persistence helpers

    /// Reads a `WinRateSummaryData` value from the shared App Group UserDefaults.
    static func load() -> WinRateSummaryData? {
        guard
            let defaults = UserDefaults(suiteName: sharedAppGroupID),
            let data = defaults.data(forKey: SharedMatchKeys.winRateSummary)
        else { return nil }
        return try? JSONDecoder().decode(WinRateSummaryData.self, from: data)
    }

    /// Writes this value to the shared App Group UserDefaults.
    func save() {
        guard
            let defaults = UserDefaults(suiteName: sharedAppGroupID),
            let data = try? JSONEncoder().encode(self)
        else { return }
        defaults.set(data, forKey: SharedMatchKeys.winRateSummary)
    }

    /// A stable placeholder shown before any match data is available.
    static var placeholder: WinRateSummaryData {
        WinRateSummaryData(
            totalMatches: 10,
            wins: 7,
            losses: 3,
            updatedAt: Date()
        )
    }
}
