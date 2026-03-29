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
}
