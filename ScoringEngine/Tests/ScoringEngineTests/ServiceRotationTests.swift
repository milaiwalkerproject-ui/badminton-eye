import Testing
@testable import ScoringEngine

struct ServiceRotationTests {

    @Test("Singles: score 0 (even) serves from right court")
    func singlesEvenScoreRightCourt() {
        let state = MatchState.newSinglesMatch()
        #expect(state.serviceCourt == .right)
    }

    @Test("Singles: score 1 (odd) serves from left court")
    func singlesOddScoreLeftCourt() {
        let state = MatchState.newSinglesMatch()
        // sideA scores (server wins rally, stays server)
        let next = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(next.serviceCourt == .left) // sideA score is 1 (odd)
    }

    @Test("Singles: server wins rally, same server alternates court")
    func singlesServerWinsStaysSameServer() {
        var state = MatchState.newSinglesMatch()
        // sideA is initial server
        #expect(state.currentServer.side == .sideA)
        #expect(state.serviceCourt == .right) // Score 0, even

        // sideA scores
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.currentServer.side == .sideA) // Still serving
        #expect(state.serviceCourt == .left) // Score 1, odd

        // sideA scores again
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.currentServer.side == .sideA) // Still serving
        #expect(state.serviceCourt == .right) // Score 2, even
    }

    @Test("Singles: receiver wins rally, receiver becomes server")
    func singlesReceiverWinsBecomesServer() {
        var state = MatchState.newSinglesMatch()
        #expect(state.currentServer.side == .sideA)

        // sideB wins rally (receiver wins)
        state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        #expect(state.currentServer.side == .sideB) // Receiver became server
    }

    @Test("Singles: service court based on serving side's score, not total score")
    func singlesServiceCourtBasedOnServerScore() {
        var state = MatchState.newSinglesMatch()

        // sideA scores 3 points (server stays sideA)
        for _ in 0..<3 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.currentServer.side == .sideA)
        #expect(state.currentGame.scoreA == 3)
        #expect(state.serviceCourt == .left) // 3 is odd

        // sideB wins rally (service changes)
        state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        #expect(state.currentServer.side == .sideB)
        #expect(state.currentGame.scoreB == 1)
        #expect(state.serviceCourt == .left) // sideB score is 1 (odd)
    }

    @Test("Singles: full service exchange sequence")
    func singlesFullServiceExchange() {
        var state = MatchState.newSinglesMatch()

        // A serves and scores (0->1), court: right->left
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.currentServer.side == .sideA)

        // A serves and B scores (B:0->1), B now serves from left (B score = 1)
        state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        #expect(state.currentServer.side == .sideB)
        #expect(state.serviceCourt == .left) // B score is 1

        // B serves and scores (B:1->2), court: left->right
        state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        #expect(state.currentServer.side == .sideB)
        #expect(state.serviceCourt == .right) // B score is 2

        // B serves and A scores (A:1->2), A now serves from right (A score = 2)
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.currentServer.side == .sideA)
        #expect(state.serviceCourt == .right) // A score is 2
    }

    // MARK: - Cross-Game Service Continuity

    @Test("Loser of game 1 serves first in game 2")
    func loserServesFirstInGame2() {
        var state = MatchState.newSinglesMatch()
        // sideA wins game 1 (21-0), so sideB is the loser
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.games.count == 1)
        #expect(state.currentGame.gameNumber == 2)
        // Loser (sideB) serves first in game 2
        #expect(state.currentServer.side == .sideB)
        // New game score is 0-0; server starts from right court (0 is even)
        #expect(state.serviceCourt == .right)
    }

    @Test("Loser of game 2 serves first in game 3")
    func loserServesFirstInGame3() {
        var state = MatchState.newSinglesMatch()
        // sideA wins game 1
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        // sideB wins game 2 (sideA is the loser of game 2)
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        #expect(state.currentGame.gameNumber == 3)
        // sideA lost game 2, so sideA serves first in game 3
        #expect(state.currentServer.side == .sideA)
        #expect(state.serviceCourt == .right)
    }
}
