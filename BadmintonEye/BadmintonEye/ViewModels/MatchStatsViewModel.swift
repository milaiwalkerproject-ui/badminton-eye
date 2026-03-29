import Foundation

@Observable
class MatchStatsViewModel {

    // MARK: - Public State

    private(set) var completedMatches: [PersistedMatch] = []
    private(set) var totalWins: Int = 0
    private(set) var totalLosses: Int = 0
    private(set) var winRate: Double = 0
    private(set) var currentWinStreak: Int = 0
    private(set) var detectedPlayerName: String?

    var selectedPlayerName: String?

    var hasEnoughData: Bool {
        completedMatches.count >= 3
    }

    // MARK: - Active Player

    private var activePlayerName: String? {
        selectedPlayerName ?? detectedPlayerName
    }

    // MARK: - Update

    func update(matches: [PersistedMatch]) {
        detectPlayer(from: matches)

        completedMatches = matches
            .filter { $0.isComplete }
            .sorted { $0.startedAt > $1.startedAt }

        computeStats()
    }

    // MARK: - Trend Data for Plan 02

    /// Rolling win rate for the last `n` matches (0 = all).
    /// Returns array of (match index, cumulative win rate at that point).
    func winRateOverLast(_ n: Int) -> [(index: Int, rate: Double)] {
        guard let player = activePlayerName else { return [] }

        let subset: [PersistedMatch]
        if n > 0 && n < completedMatches.count {
            subset = Array(completedMatches.prefix(n)).reversed()
        } else {
            subset = completedMatches.reversed()
        }

        guard !subset.isEmpty else { return [] }

        var results: [(index: Int, rate: Double)] = []
        var wins = 0
        for (i, match) in subset.enumerated() {
            if isWin(match, for: player) { wins += 1 }
            let rate = Double(wins) / Double(i + 1) * 100
            results.append((index: i, rate: rate))
        }
        return results
    }

    /// Per-game averages: average points scored and conceded by the user.
    func perGameAverages() -> [(game: Int, avgScored: Double, avgConceded: Double)] {
        guard let player = activePlayerName else { return [] }

        var game1Scored: [Int] = []
        var game1Conceded: [Int] = []
        var game2Scored: [Int] = []
        var game2Conceded: [Int] = []
        var game3Scored: [Int] = []
        var game3Conceded: [Int] = []

        for match in completedMatches {
            let isSideA = isOnSideA(match, player: player)

            // Game 1 always exists
            game1Scored.append(isSideA ? match.game1ScoreA : match.game1ScoreB)
            game1Conceded.append(isSideA ? match.game1ScoreB : match.game1ScoreA)

            // Game 2
            if let s2a = match.game2ScoreA, let s2b = match.game2ScoreB {
                game2Scored.append(isSideA ? s2a : s2b)
                game2Conceded.append(isSideA ? s2b : s2a)
            }

            // Game 3
            if let s3a = match.game3ScoreA, let s3b = match.game3ScoreB {
                game3Scored.append(isSideA ? s3a : s3b)
                game3Conceded.append(isSideA ? s3b : s3a)
            }
        }

        var results: [(game: Int, avgScored: Double, avgConceded: Double)] = []

        if !game1Scored.isEmpty {
            results.append((
                game: 1,
                avgScored: average(game1Scored),
                avgConceded: average(game1Conceded)
            ))
        }
        if !game2Scored.isEmpty {
            results.append((
                game: 2,
                avgScored: average(game2Scored),
                avgConceded: average(game2Conceded)
            ))
        }
        if !game3Scored.isEmpty {
            results.append((
                game: 3,
                avgScored: average(game3Scored),
                avgConceded: average(game3Conceded)
            ))
        }

        return results
    }

    // MARK: - Private Helpers

    private func detectPlayer(from matches: [PersistedMatch]) {
        let completed = matches.filter { $0.isComplete }
        var nameCounts: [String: Int] = [:]

        for match in completed {
            if let name = match.playerAName, !name.isEmpty {
                nameCounts[name, default: 0] += 1
            }
        }

        detectedPlayerName = nameCounts.max(by: { $0.value < $1.value })?.key
    }

    private func computeStats() {
        guard let player = activePlayerName else {
            totalWins = 0
            totalLosses = 0
            winRate = 0
            currentWinStreak = 0
            return
        }

        var wins = 0
        var losses = 0

        for match in completedMatches {
            if isWin(match, for: player) { wins += 1 } else { losses += 1 }
        }

        totalWins = wins
        totalLosses = losses

        let total = wins + losses
        winRate = total > 0 ? Double(wins) / Double(total) * 100 : 0

        // Current win streak: count consecutive wins from most recent
        var streak = 0
        for match in completedMatches {
            if isWin(match, for: player) {
                streak += 1
            } else {
                break
            }
        }
        currentWinStreak = streak
    }

    private func isWin(_ match: PersistedMatch, for player: String) -> Bool {
        let isSideA = isOnSideA(match, player: player)
        if isSideA { return match.winnerSide == "sideA" }
        return match.winnerSide == "sideB"
    }

    private func isOnSideA(_ match: PersistedMatch, player: String) -> Bool {
        match.playerAName == player || match.playerA2Name == player
    }

    private func average(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
}
