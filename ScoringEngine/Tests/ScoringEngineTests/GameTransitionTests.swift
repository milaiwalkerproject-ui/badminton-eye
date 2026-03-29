import Testing
@testable import ScoringEngine

struct GameTransitionTests {

    /// Helper: play a game where sideA wins 21-0
    private func winGameForSideA(_ state: MatchState) -> MatchState {
        var s = state
        for _ in 0..<21 {
            s = MatchEngine.apply(event: .scorePoint(.sideA), to: s)
        }
        return s
    }

    /// Helper: play a game where sideB wins 21-0
    private func winGameForSideB(_ state: MatchState) -> MatchState {
        var s = state
        for _ in 0..<21 {
            s = MatchEngine.apply(event: .scorePoint(.sideB), to: s)
        }
        return s
    }

    @Test("After game 1 ends, shouldSwitchSidesFlag is true")
    func switchSidesAfterGame1() {
        let state = MatchState.newSinglesMatch()
        let next = winGameForSideA(state)
        #expect(next.shouldSwitchSidesFlag == true)
        #expect(next.games.count == 1)
    }

    @Test("After game 2 ends (third game needed), shouldSwitchSidesFlag is true")
    func switchSidesAfterGame2() {
        var state = MatchState.newSinglesMatch()
        state = winGameForSideA(state)
        state = winGameForSideB(state)
        #expect(state.shouldSwitchSidesFlag == true)
        #expect(state.games.count == 2)
        #expect(state.currentGame.gameNumber == 3)
    }

    @Test("In game 3, mid-game switch at 11 points")
    func midThirdGameSwitch() {
        var state = MatchState.newSinglesMatch()
        state = winGameForSideA(state)
        state = winGameForSideB(state)
        #expect(state.currentGame.gameNumber == 3)

        // Score to 11-0 for sideA in game 3
        for i in 0..<11 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            if i < 10 {
                #expect(state.shouldSwitchSidesFlag == false, "Should not switch before 11")
            }
        }
        #expect(state.currentGame.scoreA == 11)
        #expect(state.shouldSwitchSidesFlag == true)
        #expect(state.currentGame.hasSwitchedInThirdGame == true)
    }

    @Test("Third game mid-switch only happens once")
    func midSwitchOnlyOnce() {
        var state = MatchState.newSinglesMatch()
        state = winGameForSideA(state)
        state = winGameForSideB(state)

        // Score to 11-0 (triggers switch)
        for _ in 0..<11 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.currentGame.hasSwitchedInThirdGame == true)

        // Score more points -- should NOT trigger another switch
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.shouldSwitchSidesFlag == false)
    }

    @Test("New game starts at 0-0 with correct game number")
    func newGameStartsCorrectly() {
        let state = MatchState.newSinglesMatch()
        let next = winGameForSideA(state)
        #expect(next.currentGame.scoreA == 0)
        #expect(next.currentGame.scoreB == 0)
        #expect(next.currentGame.gameNumber == 2)
    }

    @Test("Match won after third game")
    func matchWonAfterThirdGame() {
        var state = MatchState.newSinglesMatch()
        state = winGameForSideA(state)
        state = winGameForSideB(state)
        state = winGameForSideA(state)
        #expect(state.matchPhase == .complete)
        #expect(state.matchWinner == .sideA)
        #expect(state.games.count == 3)
    }
}
