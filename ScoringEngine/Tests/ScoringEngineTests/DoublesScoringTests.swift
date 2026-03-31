import Testing
@testable import ScoringEngine

struct DoublesScoringTests {

    @Test("New doubles match starts correctly")
    func newDoublesMatch() {
        let state = MatchState.newDoublesMatch()
        #expect(state.format == .doubles)
        #expect(state.games.isEmpty)
        #expect(state.currentGame.scoreA == 0)
        #expect(state.currentGame.scoreB == 0)
        #expect(state.teamANames.count == 2)
        #expect(state.teamBNames.count == 2)
        #expect(state.doublesRotation.count == 4)
    }

    @Test("Initial server is teamA player 0 at right court")
    func initialServer() {
        let state = MatchState.newDoublesMatch()
        let server = state.currentServer
        #expect(server.side == .sideA)
        #expect(server.playerIndex == 0)
        #expect(state.serviceCourt == .right) // Score 0, even
    }

    @Test("Serving side scores: same server, server swaps court")
    func servingSideScores() {
        let state = MatchState.newDoublesMatch()
        // sideA serves and scores
        let next = MatchEngine.apply(event: .scorePoint(.sideA), to: state)

        // Same server
        #expect(next.currentServer.side == .sideA)
        #expect(next.currentServer.playerIndex == 0)

        // Server's court position should have swapped
        // Initially: [.right, .left] -> after swap: [.left, .right]
        #expect(next.teamAPositions[0] == .left)
        #expect(next.teamAPositions[1] == .right)

        // Service court based on score (1 = odd = left)
        #expect(next.serviceCourt == .left)
    }

    @Test("Receiving side scores: service passes to next in rotation")
    func receivingSideScores() {
        let state = MatchState.newDoublesMatch()
        // sideB scores (receiving side wins rally)
        let next = MatchEngine.apply(event: .scorePoint(.sideB), to: state)

        // Service passes to rotation[1] = sideB player 1
        #expect(next.currentServer.side == .sideB)
        #expect(next.currentServer.playerIndex == 1)
        #expect(next.servingPlayerIndex == 1)
    }

    @Test("Full rotation cycle: 4 service changes through all players")
    func fullRotationCycle() {
        var state = MatchState.newDoublesMatch()

        // Rotation order:
        // [0] sideA player 0
        // [1] sideB player 1
        // [2] sideA player 1
        // [3] sideB player 0

        // Initial: sideA player 0 serves
        #expect(state.currentServer == PlayerPosition(side: .sideA, playerIndex: 0))

        // Receiving side (B) scores -> advance to rotation[1]
        state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        #expect(state.currentServer == PlayerPosition(side: .sideB, playerIndex: 1))

        // Receiving side (A) scores -> advance to rotation[2]
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.currentServer == PlayerPosition(side: .sideA, playerIndex: 1))

        // Receiving side (B) scores -> advance to rotation[3]
        state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        #expect(state.currentServer == PlayerPosition(side: .sideB, playerIndex: 0))

        // Receiving side (A) scores -> advance to rotation[0] (wraps around)
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.currentServer == PlayerPosition(side: .sideA, playerIndex: 0))
    }

    @Test("Service court follows serving side's score in doubles")
    func serviceCourtFollowsScore() {
        var state = MatchState.newDoublesMatch()

        // Score 0 (even) -> right
        #expect(state.serviceCourt == .right)

        // sideA scores (server wins), sideA score = 1 -> left
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.serviceCourt == .left)

        // sideA scores again, sideA score = 2 -> right
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.serviceCourt == .right)

        // sideB scores (receiving wins), service to sideB. sideB score = 1 -> left
        state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        #expect(state.currentServer.side == .sideB)
        #expect(state.serviceCourt == .left) // B score = 1

        // sideB scores again (serving side wins), sideB score = 2 -> right
        state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        #expect(state.serviceCourt == .right) // B score = 2
    }

    @Test("After game end, rotation resets for new game (loser serves)")
    func gameTransitionResetsRotation() {
        var state = MatchState.newDoublesMatch()
        // Win game 1 for sideA: 21-0
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.games.count == 1)
        #expect(state.currentGame.gameNumber == 2)

        // Loser (sideB) serves first in new game
        #expect(state.currentServer.side == .sideB)
        #expect(state.servingPlayerIndex == 0)
    }

    @Test("Doubles undo restores correct server and court positions")
    func doublesUndo() {
        var state = MatchState.newDoublesMatch()
        let beforeScore = state

        // sideA scores (serving side wins)
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.currentServer.side == .sideA)
        #expect(state.teamAPositions[0] == .left) // Court swapped

        // Undo
        let undone = MatchEngine.apply(event: .undo, to: state)
        #expect(undone.currentServer.side == beforeScore.currentServer.side)
        #expect(undone.teamAPositions == beforeScore.teamAPositions)
        #expect(undone.servingPlayerIndex == beforeScore.servingPlayerIndex)
        #expect(undone.currentGame.scoreA == 0)
    }

    @Test("Doubles: loser of game 2 serves first in game 3")
    func doublesGameThreeService() {
        var state = MatchState.newDoublesMatch()
        // sideA wins game 1 (21-0) -> sideB (loser) serves in game 2
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.currentServer.side == .sideB)

        // sideB wins game 2 (21-0) -> sideA (loser) serves in game 3
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        #expect(state.currentGame.gameNumber == 3)
        #expect(state.currentServer.side == .sideA)
        #expect(state.servingPlayerIndex == 0)
        // doublesRotation should be reset with sideA player 0 as first server
        #expect(state.doublesRotation[0].side == .sideA)
        #expect(state.doublesRotation[0].playerIndex == 0)
    }

    @Test("Doubles: undo first point of game 2 restores cross-game-boundary state")
    func doublesUndoFirstPointOfGame2() {
        var state = MatchState.newDoublesMatch()
        // sideA wins game 1 (21-0) -> sideB serves in game 2
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.currentServer.side == .sideB)
        #expect(state.currentGame.gameNumber == 2)
        let game2Start = state

        // Score first point of game 2 (sideB serves and scores)
        let afterFirst = MatchEngine.apply(event: .scorePoint(.sideB), to: game2Start)
        #expect(afterFirst.currentGame.scoreB == 1)

        // Undo should restore to game2Start state
        let undone = MatchEngine.apply(event: .undo, to: afterFirst)
        #expect(undone.currentServer.side == .sideB)
        #expect(undone.currentGame.scoreA == 0)
        #expect(undone.currentGame.scoreB == 0)
        #expect(undone.currentGame.gameNumber == 2)
        #expect(undone.games.count == 1) // game 1 still complete
        #expect(undone.servingPlayerIndex == game2Start.servingPlayerIndex)
    }

    @Test("Doubles: serving side scores multiple times, court swaps each time")
    func multipleServingSideScores() {
        var state = MatchState.newDoublesMatch()

        // Initial positions: [.right, .left]
        #expect(state.teamAPositions == [.right, .left])

        // sideA scores (server wins rally) -> swap
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.teamAPositions == [.left, .right])

        // sideA scores again -> swap back
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.teamAPositions == [.right, .left])

        // sideA scores again -> swap
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.teamAPositions == [.left, .right])
    }

    // MARK: - Deuce & Cap (DUB-DCE-01, DUB-DCE-02, DUB-DCE-03)

    @Test("Doubles deuce activates at 20-20")
    func doublesDeuceAtTwentyAll() {
        var state = MatchState.newDoublesMatch()
        for _ in 0..<20 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        #expect(state.isDeuce)
        #expect(state.currentGame.scoreA == 20)
        #expect(state.currentGame.scoreB == 20)
    }

    @Test("Doubles 21-20 does NOT win the game in deuce")
    func doublesTwentyOneTwentyNotWon() {
        var state = MatchState.newDoublesMatch()
        for _ in 0..<20 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.currentGame.scoreA == 21)
        #expect(state.currentGame.scoreB == 20)
        #expect(state.matchPhase == .inProgress)
        #expect(state.games.isEmpty) // Game not completed
    }

    @Test("Doubles cap at 30-29 ends game")
    func doublesCapAtThirtyTwentyNine() {
        var state = MatchState.newDoublesMatch()
        for _ in 0..<29 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        #expect(state.isAtCap)
        // 30-29 reaches cap — game over regardless of lead
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.games.count == 1)
        #expect(state.games[0].scoreA == 30)
        #expect(state.games[0].scoreB == 29)
    }

    // MARK: - Mid-Game Switch (DUB-MID-01)

    @Test("Doubles game-3 mid-switch triggers shouldSwitchSidesFlag at 11 points")
    func doublesGame3MidSwitch() {
        var state = MatchState.newDoublesMatch()
        // sideA wins game 1, sideB wins game 2 -> game 3 starts
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        #expect(state.currentGame.gameNumber == 3)

        // Score to 10-0 — switch should NOT have fired yet
        for _ in 0..<10 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.currentGame.hasSwitchedInThirdGame == false)
        #expect(state.shouldSwitchSidesFlag == false)

        // Score the 11th point — switch fires
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.currentGame.scoreA == 11)
        #expect(state.shouldSwitchSidesFlag == true)
        #expect(state.currentGame.hasSwitchedInThirdGame == true)

        // Additional points do NOT fire a second switch
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.shouldSwitchSidesFlag == false)
    }

    // MARK: - Undo During Deuce (DUB-UND-01)

    @Test("Doubles undo at 21-20 in deuce reverts to 20-20 with correct server")
    func doublesUndoDuringDeuce() {
        var state = MatchState.newDoublesMatch()
        for _ in 0..<20 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        #expect(state.isDeuce)
        let serverAtDeuce = state.currentServer

        // sideA scores to 21-20
        let twentyOneTwenty = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(twentyOneTwenty.currentGame.scoreA == 21)
        #expect(twentyOneTwenty.matchPhase == .inProgress)

        // Undo reverts to 20-20 with the same server as before
        let undone = MatchEngine.apply(event: .undo, to: twentyOneTwenty)
        #expect(undone.currentGame.scoreA == 20)
        #expect(undone.currentGame.scoreB == 20)
        #expect(undone.isDeuce)
        #expect(undone.currentServer == serverAtDeuce)
        #expect(undone.matchPhase == .inProgress)
    }
}
