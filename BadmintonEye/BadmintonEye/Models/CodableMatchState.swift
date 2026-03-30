import Foundation
import ScoringEngine

/// A Codable mirror of MatchState that excludes the recursive previousState field.
/// Used solely for JSON serialization to SwiftData for crash recovery.
struct CodableMatchState: Codable {
    let format: MatchFormat
    var scoringSystem: ScoringSystem?  // Optional for backward compat with v1.0/v1.1 JSON
    var games: [GameState]
    var currentGame: GameState
    var matchPhase: MatchPhase
    var servingPlayerIndex: Int
    var doublesRotation: [PlayerPosition]
    var teamAPositions: [Court]
    var teamBPositions: [Court]
    var teamANames: [String]
    var teamBNames: [String]
    var shouldSwitchSidesFlag: Bool

    init(from state: MatchState) {
        self.format = state.format
        self.scoringSystem = state.scoringSystem
        self.games = state.games
        self.currentGame = state.currentGame
        self.matchPhase = state.matchPhase
        self.servingPlayerIndex = state.servingPlayerIndex
        self.doublesRotation = state.doublesRotation
        self.teamAPositions = state.teamAPositions
        self.teamBPositions = state.teamBPositions
        self.teamANames = state.teamANames
        self.teamBNames = state.teamBNames
        self.shouldSwitchSidesFlag = state.shouldSwitchSidesFlag
    }

    func toMatchState() -> MatchState {
        let system = scoringSystem ?? .standard21
        var state: MatchState
        switch format {
        case .singles:
            state = MatchState.newSinglesMatch(
                teamAName: teamANames.first,
                teamBName: teamBNames.first,
                scoringSystem: system
            )
        case .doubles:
            state = MatchState.newDoublesMatch(
                teamANames: teamANames,
                teamBNames: teamBNames,
                scoringSystem: system
            )
        case .mixed:
            state = MatchState.newMixedMatch(
                teamANames: teamANames,
                teamBNames: teamBNames,
                scoringSystem: system
            )
        }
        state.games = games
        state.currentGame = currentGame
        state.matchPhase = matchPhase
        state.servingPlayerIndex = servingPlayerIndex
        state.doublesRotation = doublesRotation
        state.teamAPositions = teamAPositions
        state.teamBPositions = teamBPositions
        state.shouldSwitchSidesFlag = shouldSwitchSidesFlag
        return state
    }
}
