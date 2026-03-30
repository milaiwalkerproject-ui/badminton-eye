// BWFRules.swift — BWF rule computations using parameterized ScoringRules

extension MatchState {
    /// Both scores >= deuceThreshold (Law 7.3 / 3×15 equivalent)
    public var isDeuce: Bool {
        let threshold = scoringRules.deuceThreshold
        return currentGame.scoreA >= threshold && currentGame.scoreB >= threshold
    }

    /// Both scores at one below cap (Law 7.4 / 3×15 equivalent)
    public var isAtCap: Bool {
        let capMinusOne = scoringRules.capScore - 1
        return currentGame.scoreA == capMinusOne && currentGame.scoreB == capMinusOne
    }

    /// Game is won: score >= pointsToWin with 2-point lead, OR score == capScore at cap
    public var isGameWon: Bool {
        let rules = scoringRules
        let a = currentGame.scoreA
        let b = currentGame.scoreB
        let maxScore = max(a, b)
        let minScore = min(a, b)

        if maxScore < rules.pointsToWin { return false }
        if maxScore == rules.capScore { return true }
        return maxScore - minScore >= 2
    }

    /// Which side won the current game (nil if not won)
    public var gameWinner: Side? {
        guard isGameWon else { return nil }
        return currentGame.scoreA > currentGame.scoreB ? .sideA : .sideB
    }

    /// Count of games won by each side from completed games
    public var gamesWon: (sideA: Int, sideB: Int) {
        var a = 0
        var b = 0
        for game in games {
            if game.scoreA > game.scoreB {
                a += 1
            } else {
                b += 1
            }
        }
        return (a, b)
    }

    /// One side has won enough games (best-of-3 or best-of-5)
    public var isMatchComplete: Bool {
        let won = gamesWon
        let target = scoringRules.gamesToWin
        return won.sideA >= target || won.sideB >= target
    }

    /// Which side won the match (nil if not complete)
    public var matchWinner: Side? {
        guard isMatchComplete else { return nil }
        let won = gamesWon
        let target = scoringRules.gamesToWin
        return won.sideA >= target ? .sideA : .sideB
    }

    /// Should switch sides: end of game or at midGameSwitchPoint in final game
    public var shouldSwitchSides: Bool {
        let rules = scoringRules
        let finalGame = rules.maxGames // 3 for standard21, 5 for 3×15

        if currentGame.gameNumber == finalGame
            && !currentGame.hasSwitchedInThirdGame
            && (currentGame.scoreA == rules.midGameSwitchPoint
                || currentGame.scoreB == rules.midGameSwitchPoint)
        {
            return true
        }
        return false
    }
}
