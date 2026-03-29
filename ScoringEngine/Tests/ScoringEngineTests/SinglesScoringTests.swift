import Testing
@testable import ScoringEngine

struct SinglesScoringTests {

    @Test("New singles match starts correctly")
    func newSinglesMatch() {
        let state = MatchState.newSinglesMatch()
        #expect(state.format == .singles)
        #expect(state.games.isEmpty)
        #expect(state.currentGame.scoreA == 0)
        #expect(state.currentGame.scoreB == 0)
        #expect(state.currentGame.gameNumber == 1)
        #expect(state.matchPhase == .inProgress)
    }

    @Test("Score point for side A increments scoreA")
    func scorePointSideA() {
        let state = MatchState.newSinglesMatch()
        let next = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(next.currentGame.scoreA == 1)
        #expect(next.currentGame.scoreB == 0)
    }

    @Test("Score point for side B increments scoreB")
    func scorePointSideB() {
        let state = MatchState.newSinglesMatch()
        let next = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        #expect(next.currentGame.scoreA == 0)
        #expect(next.currentGame.scoreB == 1)
    }

    @Test("Regular game win at 21 points", arguments: [
        (scoresA: 21, scoresB: 15),
        (scoresA: 21, scoresB: 0),
        (scoresA: 21, scoresB: 19),
    ])
    func regularGameWin(scoresA: Int, scoresB: Int) {
        var state = MatchState.newSinglesMatch()
        // Score B first, then remaining A
        for _ in 0..<scoresB {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        for _ in scoresB..<scoresA {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        // Game should be completed
        #expect(state.games.count == 1)
        #expect(state.currentGame.gameNumber == 2) // New game started
    }

    @Test("Match complete after 2 games won by same side")
    func matchCompleteAfterTwoGames() {
        var state = MatchState.newSinglesMatch()
        // Win game 1 for sideA: 21-0
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.games.count == 1)
        #expect(state.matchPhase == .inProgress)

        // Win game 2 for sideA: 21-0
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.games.count == 2)
        #expect(state.matchPhase == .complete)
    }

    @Test("Third game starts when sides split games")
    func thirdGameStarts() {
        var state = MatchState.newSinglesMatch()
        // Win game 1 for sideA: 21-0
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        // Win game 2 for sideB: 21-0
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        #expect(state.games.count == 2)
        #expect(state.currentGame.gameNumber == 3)
        #expect(state.matchPhase == .inProgress)
    }

    @Test("Abandon sets matchPhase to abandoned")
    func abandonMatch() {
        let state = MatchState.newSinglesMatch()
        let next = MatchEngine.apply(event: .abandon, to: state)
        #expect(next.matchPhase == .abandoned)
    }

    @Test("Scoring on completed match does nothing")
    func scoringOnCompleteMatch() {
        var state = MatchState.newSinglesMatch()
        // Win 2 games
        for _ in 0..<21 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        for _ in 0..<21 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        #expect(state.matchPhase == .complete)

        let next = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(next == state) // No change
    }
}
