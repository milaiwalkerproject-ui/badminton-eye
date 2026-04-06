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

    // MARK: - Cross-Game Service Continuity

    @Test("3×15: Loser of game 1 serves first in game 2")
    func threeByFifteenLoserServesInGame2() {
        var state = MatchState.newSinglesMatch(scoringSystem: .threeByFifteen)
        // sideA wins game 1 (15-0), so sideB is the loser
        for _ in 0..<15 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.games.count == 1)
        #expect(state.currentGame.gameNumber == 2)
        // Loser (sideB) serves first in game 2
        #expect(state.currentServer.side == .sideB)
        // New game score is 0-0; server starts from right court (0 is even)
        #expect(state.serviceCourt == .right)
    }

    @Test("3×15: Loser of game 2 serves first in game 3")
    func threeByFifteenLoserServesInGame3() {
        var state = MatchState.newSinglesMatch(scoringSystem: .threeByFifteen)
        // sideA wins game 1 (15-0)
        for _ in 0..<15 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        // sideB wins game 2 (15-0), so sideA is the loser of game 2
        for _ in 0..<15 {
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        #expect(state.currentGame.gameNumber == 3)
        // sideA lost game 2, so sideA serves first in game 3
        #expect(state.currentServer.side == .sideA)
        #expect(state.serviceCourt == .right)
    }

    // MARK: - Undo Edge Cases (THX-UND-01, THX-UND-02, THX-UND-03)

    @Test("3×15: Undo at 15-14 (deuce) reverts to 14-14 with isDeuce true")
    func threeByFifteenUndoDuringDeuce() {
        var state = MatchState.newSinglesMatch(scoringSystem: .threeByFifteen)
        // Score to 14-14 (deuce threshold)
        for _ in 0..<14 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        #expect(state.isDeuce)

        // sideA scores to 15-14 (not yet won — need 2-point lead)
        let fifteenFourteen = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(fifteenFourteen.currentGame.scoreA == 15)
        #expect(fifteenFourteen.matchPhase == .inProgress)

        // Undo reverts to 14-14 (still in deuce)
        let undone = MatchEngine.apply(event: .undo, to: fifteenFourteen)
        #expect(undone.currentGame.scoreA == 14)
        #expect(undone.currentGame.scoreB == 14)
        #expect(undone.isDeuce)
        #expect(undone.matchPhase == .inProgress)
    }

    @Test("3×15: Undo mid-game-switch point in 5th game clears hasSwitchedInThirdGame and shouldSwitchSidesFlag")
    func threeByFifteenUndoMidSwitch() {
        var state = MatchState.newSinglesMatch(scoringSystem: .threeByFifteen)
        // Get to game 5: A wins games 1,2; B wins games 3,4
        for _ in 0..<2 {
            for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        }
        for _ in 0..<2 {
            for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideB), to: state) }
        }
        #expect(state.currentGame.gameNumber == 5)

        // Score to 7-0 (one below the 8-point switch threshold in 3×15)
        for _ in 0..<7 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.currentGame.hasSwitchedInThirdGame == false)
        #expect(state.shouldSwitchSidesFlag == false)

        // Score the 8th point — mid-game switch fires
        let switched = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(switched.currentGame.scoreA == 8)
        #expect(switched.shouldSwitchSidesFlag == true)
        #expect(switched.currentGame.hasSwitchedInThirdGame == true)

        // Undo should clear the switch flags and restore score to 7
        let undone = MatchEngine.apply(event: .undo, to: switched)
        #expect(undone.currentGame.scoreA == 7)
        #expect(undone.currentGame.hasSwitchedInThirdGame == false)
        #expect(undone.shouldSwitchSidesFlag == false)
    }

    @Test("3×15: Undo first point of game 3 restores cross-game-boundary state")
    func threeByFifteenUndoFirstPointOfGame3() {
        var state = MatchState.newSinglesMatch(scoringSystem: .threeByFifteen)
        // sideA wins game 1 (15-0) -> sideB serves in game 2
        for _ in 0..<15 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        // sideB wins game 2 (15-0) -> sideA serves in game 3
        for _ in 0..<15 {
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        #expect(state.currentGame.gameNumber == 3)
        #expect(state.currentServer.side == .sideA)
        let game3Start = state

        // Score first point of game 3 (sideA serves and scores)
        let afterFirst = MatchEngine.apply(event: .scorePoint(.sideA), to: game3Start)
        #expect(afterFirst.currentGame.scoreA == 1)

        // Undo should restore to game3Start state
        let undone = MatchEngine.apply(event: .undo, to: afterFirst)
        #expect(undone.currentGame.gameNumber == 3)
        #expect(undone.currentGame.scoreA == 0)
        #expect(undone.currentGame.scoreB == 0)
        #expect(undone.currentServer.side == .sideA)
        #expect(undone.serviceCourt == .right)
        #expect(undone.games.count == 2) // Games 1 and 2 still complete
    }

    // MARK: - Cross-Game Service Continuity Games 3→4 and 4→5 (THX-G4-01, THX-G5-01)

    @Test("3×15: Loser of game 3 serves first in game 4")
    func threeByFifteenLoserServesInGame4() {
        var state = MatchState.newSinglesMatch(scoringSystem: .threeByFifteen)
        // A wins game 1 → B serves in game 2
        for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        // B wins game 2 → A serves in game 3
        for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideB), to: state) }
        // A wins game 3 → B (loser) serves in game 4
        for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        #expect(state.currentGame.gameNumber == 4)
        #expect(state.currentServer.side == .sideB)
        #expect(state.serviceCourt == .right)
        #expect(state.games.count == 3)
    }

    @Test("3×15: Loser of game 4 serves first in game 5")
    func threeByFifteenLoserServesInGame5() {
        var state = MatchState.newSinglesMatch(scoringSystem: .threeByFifteen)
        // A wins games 1 & 3; B wins games 2 & 4 → A (loser of game 4) serves in game 5
        for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideB), to: state) }
        for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideB), to: state) }
        #expect(state.currentGame.gameNumber == 5)
        // Loser of game 4 was sideA (B won game 4)
        #expect(state.currentServer.side == .sideA)
        #expect(state.serviceCourt == .right)
        #expect(state.games.count == 4)
    }

    // MARK: - Game 4 Does NOT Trigger Mid-Game Switch (THX-G4-02)

    @Test("3×15: Game 4 does NOT trigger mid-game switch at 8 points")
    func threeByFifteenGame4NoMidSwitch() {
        var state = MatchState.newSinglesMatch(scoringSystem: .threeByFifteen)
        // Get to game 4: A wins 1, 3; B wins 2
        for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideB), to: state) }
        for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        #expect(state.currentGame.gameNumber == 4)

        // Score 8 points in game 4 — switch should NOT fire (only fires in game 5)
        for _ in 0..<8 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        #expect(state.currentGame.scoreA == 8)
        #expect(state.shouldSwitchSidesFlag == false)
        #expect(state.currentGame.hasSwitchedInThirdGame == false)
    }

    // MARK: - Undo Edge Cases Games 4 and 5 (THX-UND-04, THX-UND-05)

    @Test("3×15: Undo first point of game 4 restores cross-game-boundary state")
    func threeByFifteenUndoFirstPointOfGame4() {
        var state = MatchState.newSinglesMatch(scoringSystem: .threeByFifteen)
        // A wins game 1 → B serves game 2; B wins game 2 → A serves game 3; A wins game 3 → B serves game 4
        for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideB), to: state) }
        for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        #expect(state.currentGame.gameNumber == 4)
        #expect(state.currentServer.side == .sideB)
        let game4Start = state

        // Score first point of game 4
        let afterFirst = MatchEngine.apply(event: .scorePoint(.sideB), to: game4Start)
        #expect(afterFirst.currentGame.scoreB == 1)

        // Undo should restore to game4Start state
        let undone = MatchEngine.apply(event: .undo, to: afterFirst)
        #expect(undone.currentGame.gameNumber == 4)
        #expect(undone.currentGame.scoreA == 0)
        #expect(undone.currentGame.scoreB == 0)
        #expect(undone.currentServer.side == .sideB)
        #expect(undone.serviceCourt == .right)
        #expect(undone.games.count == 3) // Games 1, 2, and 3 still complete
    }

    @Test("3×15: Undo first point of game 5 restores cross-game-boundary state")
    func threeByFifteenUndoFirstPointOfGame5() {
        var state = MatchState.newSinglesMatch(scoringSystem: .threeByFifteen)
        // A wins games 1 & 3; B wins games 2 & 4 → game 5 starts, A serves
        for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideB), to: state) }
        for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        for _ in 0..<15 { state = MatchEngine.apply(event: .scorePoint(.sideB), to: state) }
        #expect(state.currentGame.gameNumber == 5)
        #expect(state.currentServer.side == .sideA)
        let game5Start = state

        // Score first point of game 5 (sideA serves and scores)
        let afterFirst = MatchEngine.apply(event: .scorePoint(.sideA), to: game5Start)
        #expect(afterFirst.currentGame.scoreA == 1)

        // Undo should restore to game5Start state
        let undone = MatchEngine.apply(event: .undo, to: afterFirst)
        #expect(undone.currentGame.gameNumber == 5)
        #expect(undone.currentGame.scoreA == 0)
        #expect(undone.currentGame.scoreB == 0)
        #expect(undone.currentServer.side == .sideA)
        #expect(undone.serviceCourt == .right)
        #expect(undone.games.count == 4) // Games 1–4 still complete
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
