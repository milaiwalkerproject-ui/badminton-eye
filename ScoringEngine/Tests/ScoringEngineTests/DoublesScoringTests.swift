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
}
