import Foundation

// MARK: - App Group constants
// Both the main app and the WidgetKit extension read/write data via
// UserDefaults(suiteName: WidgetSharedKeys.appGroupID).
// The App Group must be enabled in both targets' entitlements.

enum WidgetSharedKeys {
    static let appGroupID = "group.com.badmintoneye.app"
    static let liveMatch  = "widget.liveMatch"
    static let winRate    = "widget.winRate"
}

// MARK: - Live match data

/// Snapshot of the current live match pushed by LiveMatchViewModel.
/// Small widget: shows scoreA / scoreB + game indicator.
/// Medium widget: adds gamesWon, serverSide, teamNames.
struct LiveMatchWidgetData: Codable, Equatable {
    var teamAName:   String
    var teamBName:   String
    var scoreA:      Int
    var scoreB:      Int
    var gamesWonA:   Int
    var gamesWonB:   Int
    var gameNumber:  Int       // 1-indexed
    var serverSide:  String    // "sideA" | "sideB"
    var isActive:    Bool
    var updatedAt:   Date
}

// MARK: - Win-rate data

/// Aggregated win-rate stats pushed by MatchStatsViewModel.
/// Medium widget: playerName, winRate, streak, match count.
struct WinRateWidgetData: Codable, Equatable {
    var playerName:    String
    var totalMatches:  Int
    var wins:          Int
    var losses:        Int
    var winRate:       Double    // 0 – 100
    var currentStreak: Int
    var updatedAt:     Date
}
