import Testing
@testable import ScoringEngine

@Suite("3×15 Scoring Format Tests")
struct ThreeByFifteenTests {

    // MARK: - Basic Game Win

    @Test("Game won at 15-0 in 3×15 mode")
    func gameWonAtFifteen() {
        var state = MatchState.newSinglesMatch(scoringSystem: .threeByFifteen)
        for _ in 0..<15 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.games.count == 1)
        #expect(state.games[0].scoreA == 15)
        #expect(state.games[0].scoreB == 0)
    }

    // MARK: - Deuce at 14-All

    @Test("Deuce activates at 14-14 in 3×15")
    func deuceAtFourteen() {
        var state = MatchState.newSinglesMatch(scoringSystem: .threeByFifteen)
        for _ in 0..<14 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        #expect(state.isDeuce)
        #expect(state.currentGame.scoreA == 14)
        #expect(state.currentGame.scoreB == 14)
    }

    @Test("15-14 does not win game in deuce")
    func fifteenFourteenNotWon() {
        var state = MatchState.newSinglesMatch(scoringSystem: .threeByFifteen)
        // Get to 14-14
        for _ in 0..<14 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        // 15-14
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(!state.isGameWon)
        #expect(state.matchPhase == .inProgress)
    }

    @Test("16-14 wins game in deuce")
    func sixteenFourteenWins() {
        var state = MatchState.newSinglesMatch(scoringSystem: .threeByFifteen)
        for _ in 0..<14 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.games.count == 1)
        #expect(state.games[0].scoreA == 16)
    }

    // MARK: - Cap at 17

    @Test("Cap score at 17 ends game regardless of lead")
    func capAtSeventeen() {
        var state = MatchState.newSinglesMatch(scoringSystem: .threeByFifteen)
        for _ in 0..<14 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        // 16-15
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        // 16-16
        state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        #expect(state.isAtCap)
        // 17-16 = cap reached, game over
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.games.count == 1)
        #expect(state.games[0].scoreA == 17)
    }

    // MARK: - Best of 5

    @Test("Match requires 3 game wins (best of 5)")
    func bestOfFive() {
        var state = MatchState.newSinglesMatch(scoringSystem: .threeByFifteen)
        // Win 2 games for sideA
        for _ in 0..<2 {
            for _ in 0..<15 {
                state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            }
        }
        #expect(state.matchPhase == .inProgress)
        #expect(state.gamesWon.sideA == 2)

        // Win 3rd game -> match complete
        for _ in 0..<15 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.matchPhase == .complete)
        #expect(state.gamesWon.sideA == 3)
        #expect(state.matchWinner == .sideA)
    }

    @Test("Match goes to 5th game")
    func fullFiveGames() {
        var state = MatchState.newSinglesMatch(scoringSystem: .threeByFifteen)
        // A wins games 1, 2
        for _ in 0..<2 {
            for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        }
        // B wins games 3, 4
        for _ in 0..<2 {
            for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideB), to: state) }
        }
        #expect(state.gamesWon == (sideA: 2, sideB: 2))
        #expect(state.matchPhase == .inProgress)
        #expect(state.currentGame.gameNumber == 5)

        // B wins game 5
        for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideB), to: state) }
        #expect(state.matchPhase == .complete)
        #expect(state.matchWinner == .sideB)
    }

    // MARK: - Mid-Game Switch in 5th Game

    @Test("Side switch at 8 points in 5th game")
    func sideSwitchInFifthGame() {
        var state = MatchState.newSinglesMatch(scoringSystem: .threeByFifteen)
        // Get to game 5: A wins 1,2; B wins 3,4
        for _ in 0..<2 {
            for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        }
        for _ in 0..<2 {
            for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideB), to: state) }
        }
        #expect(state.currentGame.gameNumber == 5)

        // Score to 8-0 in game 5
        for _ in 0..<8 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.shouldSwitchSidesFlag)
    }

    // MARK: - Standard 21 Unchanged

    @Test("Standard 21-point mode still works correctly")
    func standard21Unchanged() {
        var state = MatchState.newSinglesMatch(scoringSystem: .standard21)
        #expect(state.scoringRules.pointsToWin == 21)
        #expect(state.scoringRules.maxGames == 3)

        // Win 2 games = match over
        for _ in 0..<2 {
            for _ in 0..<21 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        }
        #expect(state.matchPhase == .complete)
        #expect(state.gamesWon.sideA == 2)
    }
}
