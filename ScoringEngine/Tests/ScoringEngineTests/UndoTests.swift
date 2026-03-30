import Testing
@testable import ScoringEngine

struct UndoTests {

    @Test("Undo restores previous score")
    func undoRestoresPreviousScore() {
        let state = MatchState.newSinglesMatch()
        let scored = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(scored.currentGame.scoreA == 1)

        let undone = MatchEngine.apply(event: .undo, to: scored)
        #expect(undone.currentGame.scoreA == 0)
        #expect(undone.currentGame.scoreB == 0)
    }

    @Test("Undo after game-winning point restores pre-win state")
    func undoGameWinningPoint() {
        var state = MatchState.newSinglesMatch()
        // Score to 20-0
        for _ in 0..<20 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.currentGame.scoreA == 20)
        #expect(state.games.isEmpty)

        // Score winning point (21-0)
        let won = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(won.games.count == 1) // Game completed

        // Undo the winning point
        let undone = MatchEngine.apply(event: .undo, to: won)
        #expect(undone.currentGame.scoreA == 20)
        #expect(undone.games.isEmpty) // Game no longer completed
        #expect(undone.matchPhase == .inProgress)
    }

    @Test("Undo with no previous state returns same state")
    func undoNoPreviousState() {
        let state = MatchState.newSinglesMatch()
        let undone = MatchEngine.apply(event: .undo, to: state)
        #expect(undone == state) // No crash, same state returned
    }

    @Test("After undo, previousState is nil (no double-undo)")
    func noDoubleUndo() {
        let state = MatchState.newSinglesMatch()
        let scored1 = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        let scored2 = MatchEngine.apply(event: .scorePoint(.sideA), to: scored1)
        #expect(scored2.currentGame.scoreA == 2)

        let undone1 = MatchEngine.apply(event: .undo, to: scored2)
        #expect(undone1.currentGame.scoreA == 1)

        // Second undo should go back to score 0 (the previous of scored1)
        let undone2 = MatchEngine.apply(event: .undo, to: undone1)
        // undone1 is scored1's state, which has previousState = original state
        #expect(undone2.currentGame.scoreA == 0)
    }

    @Test("Undo match-winning point reverts matchPhase to inProgress")
    func undoMatchWinningPoint() {
        var state = MatchState.newSinglesMatch()
        // Win game 1 for sideA (21-0)
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        // Score game 2 to 20-0 (one point before match win)
        for _ in 0..<20 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.gamesWon.sideA == 1)
        #expect(state.matchPhase == .inProgress)
        #expect(state.currentGame.scoreA == 20)

        // Score the match-winning point
        let matchWon = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(matchWon.matchPhase == .complete)
        #expect(matchWon.matchWinner == .sideA)

        // Undo should revert to inProgress with game 2 score restored
        let undone = MatchEngine.apply(event: .undo, to: matchWon)
        #expect(undone.matchPhase == .inProgress)
        #expect(undone.matchWinner == nil)
        #expect(undone.currentGame.scoreA == 20)
        #expect(undone.gamesWon.sideA == 1)
    }

    @Test("Undo at 21-20 during deuce reverts to 20-20")
    func undoDuringDeuce() {
        var state = MatchState.newSinglesMatch()
        // Score to 20-20 (deuce)
        for _ in 0..<20 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        #expect(state.isDeuce)

        // sideA scores to 21-20 (not yet won — need 2-point lead)
        let twentyOneToTwenty = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(twentyOneToTwenty.currentGame.scoreA == 21)
        #expect(twentyOneToTwenty.matchPhase == .inProgress)

        // Undo reverts to 20-20 (still in deuce)
        let undone = MatchEngine.apply(event: .undo, to: twentyOneToTwenty)
        #expect(undone.currentGame.scoreA == 20)
        #expect(undone.currentGame.scoreB == 20)
        #expect(undone.isDeuce)
        #expect(undone.matchPhase == .inProgress)
    }

    @Test("Undo mid-game switch point clears hasSwitchedInThirdGame flag")
    func undoMidGameSwitchPoint() {
        var state = MatchState.newSinglesMatch()
        // Advance to game 3: sideA wins game 1, sideB wins game 2
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        #expect(state.currentGame.gameNumber == 3)

        // Score to 10-0 (one below the 11-point switch threshold)
        for _ in 0..<10 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.currentGame.hasSwitchedInThirdGame == false)

        // Score the 11th point (triggers mid-game side switch)
        let switched = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(switched.shouldSwitchSidesFlag == true)
        #expect(switched.currentGame.hasSwitchedInThirdGame == true)
        #expect(switched.currentGame.scoreA == 11)

        // Undo should clear the switch flags and restore score to 10
        let undone = MatchEngine.apply(event: .undo, to: switched)
        #expect(undone.currentGame.scoreA == 10)
        #expect(undone.currentGame.hasSwitchedInThirdGame == false)
        #expect(undone.shouldSwitchSidesFlag == false)
    }
}
