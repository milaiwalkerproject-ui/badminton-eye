// ServiceTracker.swift — Service tracking computed properties on MatchState

extension MatchState {
    /// Who serves: singles uses side that last won service; doubles uses rotation index
    public var currentServer: PlayerPosition {
        switch format {
        case .singles:
            // In singles, at the start sideA serves.
            // The serving side is determined by who won the last rally to gain service.
            // We track this implicitly: at game start sideA serves.
            // After each point, MatchEngine updates servingPlayerIndex:
            //   0 = sideA serves, 1 = sideB serves (for singles)
            let side: Side = servingPlayerIndex == 0 ? .sideA : .sideB
            return PlayerPosition(side: side, playerIndex: 0)

        case .doubles, .mixed:
            guard !doublesRotation.isEmpty else {
                return PlayerPosition(side: .sideA, playerIndex: 0)
            }
            return doublesRotation[servingPlayerIndex % doublesRotation.count]
        }
    }

    /// Service court: right if serving side's score is even, left if odd (Law 10.1-10.2, 11.1-11.2)
    public var serviceCourt: Court {
        let servingScore: Int
        switch currentServer.side {
        case .sideA:
            servingScore = currentGame.scoreA
        case .sideB:
            servingScore = currentGame.scoreB
        }
        return servingScore.isMultiple(of: 2) ? .right : .left
    }
}
