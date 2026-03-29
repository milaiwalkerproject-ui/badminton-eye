// MatchEngine.swift — Pure state transition function

public enum MatchEngine {
    /// Pure function: (MatchState, MatchEvent) -> MatchState
    public static func apply(event: MatchEvent, to state: MatchState) -> MatchState {
        switch event {
        case .scorePoint(let side):
            return applyScorePoint(side: side, to: state)
        case .undo:
            return state.previousState ?? state
        case .abandon:
            var next = state
            next.previousState = state
            next.matchPhase = .abandoned
            return next
        }
    }

    // MARK: - Private

    private static func applyScorePoint(side: Side, to state: MatchState) -> MatchState {
        guard state.matchPhase == .inProgress else { return state }

        var next = state
        next.previousState = state
        next.shouldSwitchSidesFlag = false

        // Increment score
        switch side {
        case .sideA:
            next.currentGame.scoreA += 1
        case .sideB:
            next.currentGame.scoreB += 1
        }

        // Update service for singles
        if next.format == .singles {
            updateSinglesService(side: side, state: &next)
        } else {
            updateDoublesService(side: side, state: &next)
        }

        // Check mid-third-game side switch (at 11 points)
        if next.shouldSwitchSides {
            next.currentGame.hasSwitchedInThirdGame = true
            next.shouldSwitchSidesFlag = true
        }

        // Check if game is won
        if next.isGameWon {
            let completedGame = next.currentGame
            next.games.append(completedGame)

            if next.isMatchComplete {
                next.matchPhase = .complete
                // Keep currentGame as the final completed game state for display
                next.currentGame = completedGame
            } else {
                // Start new game
                let newGameNumber = next.games.count + 1
                next.currentGame = GameState(gameNumber: newGameNumber)
                next.shouldSwitchSidesFlag = true // Switch sides between games

                // Reset service: losing side of previous game serves first
                let winner = completedGame.scoreA > completedGame.scoreB ? Side.sideA : Side.sideB
                resetServiceForNewGame(loser: winner.opposite, state: &next)
            }
        }

        return next
    }

    // MARK: - Singles Service

    private static func updateSinglesService(side: Side, state: inout MatchState) {
        let serverSide: Side = state.servingPlayerIndex == 0 ? .sideA : .sideB
        if side == serverSide {
            // Server won rally -- server stays the same
        } else {
            // Receiver won rally -- receiver becomes server
            state.servingPlayerIndex = side == .sideA ? 0 : 1
        }
    }

    // MARK: - Doubles Service

    private static func updateDoublesService(side: Side, state: inout MatchState) {
        guard !state.doublesRotation.isEmpty else { return }

        let server = state.doublesRotation[state.servingPlayerIndex % state.doublesRotation.count]

        if side == server.side {
            // Serving side won: server stays, swap server's court position
            swapCourtPosition(for: server, state: &state)
        } else {
            // Receiving side won: advance rotation
            state.servingPlayerIndex = (state.servingPlayerIndex + 1) % state.doublesRotation.count
        }
    }

    private static func swapCourtPosition(for player: PlayerPosition, state: inout MatchState) {
        switch player.side {
        case .sideA:
            let idx = player.playerIndex
            if idx < state.teamAPositions.count {
                state.teamAPositions[idx] = state.teamAPositions[idx].opposite
                // Also swap partner
                let partnerIdx = 1 - idx
                if partnerIdx < state.teamAPositions.count {
                    state.teamAPositions[partnerIdx] = state.teamAPositions[partnerIdx].opposite
                }
            }
        case .sideB:
            let idx = player.playerIndex
            if idx < state.teamBPositions.count {
                state.teamBPositions[idx] = state.teamBPositions[idx].opposite
                let partnerIdx = 1 - idx
                if partnerIdx < state.teamBPositions.count {
                    state.teamBPositions[partnerIdx] = state.teamBPositions[partnerIdx].opposite
                }
            }
        }
    }

    // MARK: - New Game Service Reset

    private static func resetServiceForNewGame(loser: Side, state: inout MatchState) {
        if state.format == .singles {
            state.servingPlayerIndex = loser == .sideA ? 0 : 1
        } else {
            // Doubles: loser of previous game serves first in new game
            // Reset rotation with loser's player 0 as first server
            state.servingPlayerIndex = 0
            if loser == .sideA {
                state.doublesRotation = [
                    PlayerPosition(side: .sideA, playerIndex: 0),
                    PlayerPosition(side: .sideB, playerIndex: 1),
                    PlayerPosition(side: .sideA, playerIndex: 1),
                    PlayerPosition(side: .sideB, playerIndex: 0),
                ]
            } else {
                state.doublesRotation = [
                    PlayerPosition(side: .sideB, playerIndex: 0),
                    PlayerPosition(side: .sideA, playerIndex: 1),
                    PlayerPosition(side: .sideB, playerIndex: 1),
                    PlayerPosition(side: .sideA, playerIndex: 0),
                ]
            }
            // Reset court positions
            state.teamAPositions = [.right, .left]
            state.teamBPositions = [.right, .left]
        }
    }
}
