// BWFRules.swift — BWF rule computations as computed properties on MatchState

extension MatchState {
    /// Both scores >= 20 (Law 7.3)
    public var isDeuce: Bool {
        currentGame.scoreA >= 20 && currentGame.scoreB >= 20
    }

    /// Both scores == 29 (Law 7.4)
    public var isAtCap: Bool {
        currentGame.scoreA == 29 && currentGame.scoreB == 29
    }

    /// Game is won: score >= 21 with 2-point lead, OR score == 30 at cap (Law 7.1, 7.3, 7.4)
    public var isGameWon: Bool {
        let a = currentGame.scoreA
        let b = currentGame.scoreB
        let maxScore = max(a, b)
        let minScore = min(a, b)

        if maxScore < 21 { return false }
        if maxScore == 30 { return true }
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

    /// One side has won 2 games (best-of-3)
    public var isMatchComplete: Bool {
        let won = gamesWon
        return won.sideA >= 2 || won.sideB >= 2
    }

    /// Which side won the match (nil if not complete)
    public var matchWinner: Side? {
        guard isMatchComplete else { return nil }
        let won = gamesWon
        return won.sideA >= 2 ? .sideA : .sideB
    }

    /// Should switch sides: end of game (Law 8.1.1, 8.1.2) or at 11 in third game (Law 8.1.3)
    public var shouldSwitchSides: Bool {
        // End of game triggers side switch (handled during game transition)
        // Mid-third-game switch at 11
        if currentGame.gameNumber == 3
            && !currentGame.hasSwitchedInThirdGame
            && max(currentGame.scoreA, currentGame.scoreB) == 11
            && min(currentGame.scoreA, currentGame.scoreB) < 11
        {
            return true
        }
        // Also trigger when the leading score first reaches 11 (could be 11-11 scenario)
        if currentGame.gameNumber == 3
            && !currentGame.hasSwitchedInThirdGame
            && (currentGame.scoreA == 11 || currentGame.scoreB == 11)
        {
            return true
        }
        return false
    }
}
