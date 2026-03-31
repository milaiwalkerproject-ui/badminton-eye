import Testing
@testable import ScoringEngine

struct MixedDoublesScoringTests {

    @Test("New mixed match starts correctly")
    func newMixedMatch() {
        let state = MatchState.newMixedMatch()
        #expect(state.format == .mixed)
        #expect(state.doublesRotation.count == 4)
        #expect(state.teamANames.count == 2)
        #expect(state.teamBNames.count == 2)
    }

    @Test("Mixed doubles 2026 rule: receiving side wins, non-receiver serves next")
    func mixedDoublesNonReceiverServes() {
        var state = MatchState.newMixedMatch()

        // Initial server: sideA player 0 (rotation[0])
        #expect(state.currentServer == PlayerPosition(side: .sideA, playerIndex: 0))

        // Receiving side (B) wins rally
        // Next in rotation[1] = sideB player 1 (NOT the receiver at right court, which is player 0)
        // This inherently satisfies the 2026 mixed rule: non-receiver serves
        state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        #expect(state.currentServer == PlayerPosition(side: .sideB, playerIndex: 1))

        // Verify this is NOT the player who was the receiver
        // The receiver was the player diagonally opposite the server in the right court
        // Server was sideA player 0 serving from right court
        // Receiver was sideB player at right court = player 0
        // New server is sideB player 1 (the NON-receiver) -- correct per 2026 rule
    }

    @Test("Mixed doubles: full game scoring verifies rotation integrity over 20+ rallies")
    func mixedDoublesFullGame() {
        var state = MatchState.newMixedMatch()

        // Play 24 rallies alternating scoring to exercise the rotation
        for i in 0..<24 {
            let side: Side = i % 3 == 0 ? .sideB : .sideA
            state = MatchEngine.apply(event: .scorePoint(side), to: state)

            // Verify invariants hold at each step
            #expect(state.matchPhase == .inProgress)
            #expect(state.doublesRotation.count == 4)

            // Service court must match serving side's score parity
            let serverSide = state.currentServer.side
            let serverScore = serverSide == .sideA
                ? state.currentGame.scoreA
                : state.currentGame.scoreB
            let expectedCourt: Court = serverScore.isMultiple(of: 2) ? .right : .left
            #expect(state.serviceCourt == expectedCourt,
                    "Rally \(i+1): serviceCourt should be \(expectedCourt) for score \(serverScore)")
        }
    }

    @Test("Mixed doubles: side switch preserves rotation correctly")
    func mixedDoublesSideSwitch() {
        var state = MatchState.newMixedMatch()

        // Win game 1 for sideA: 21-0
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }

        #expect(state.games.count == 1)
        #expect(state.currentGame.gameNumber == 2)
        // Loser (sideB) serves in game 2
        #expect(state.currentServer.side == .sideB)
        #expect(state.doublesRotation.count == 4)
    }

    @Test("Mixed doubles: rotation wraps correctly after full cycle")
    func mixedDoublesRotationWraps() {
        var state = MatchState.newMixedMatch()

        // Force 4 service changes by having receiving side always win
        // rotation[0] = sideA.0, [1] = sideB.1, [2] = sideA.1, [3] = sideB.0

        // Service change 1: B scores -> rotation[1]
        state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        #expect(state.currentServer == PlayerPosition(side: .sideB, playerIndex: 1))

        // Service change 2: A scores -> rotation[2]
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.currentServer == PlayerPosition(side: .sideA, playerIndex: 1))

        // Service change 3: B scores -> rotation[3]
        state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        #expect(state.currentServer == PlayerPosition(side: .sideB, playerIndex: 0))

        // Service change 4: A scores -> rotation[0] (wrap)
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.currentServer == PlayerPosition(side: .sideA, playerIndex: 0))
    }

    // MARK: - Cross-Game Service Continuity (MXD-G3-01)

    @Test("Mixed doubles: loser of game 2 serves first in game 3")
    func mixedDoublesGame3Service() {
        var state = MatchState.newMixedMatch()
        // sideA wins game 1 (21-0) -> sideB (loser) serves in game 2
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.currentServer.side == .sideB)
        #expect(state.currentGame.gameNumber == 2)

        // sideB wins game 2 (21-0) -> sideA (loser of game 2) serves in game 3
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        #expect(state.currentGame.gameNumber == 3)
        #expect(state.currentServer.side == .sideA)
        #expect(state.servingPlayerIndex == 0)
        // doublesRotation reset with sideA player 0 as first server
        #expect(state.doublesRotation[0].side == .sideA)
        #expect(state.doublesRotation[0].playerIndex == 0)
    }
}
