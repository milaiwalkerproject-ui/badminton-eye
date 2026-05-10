// MatchState.swift — Core state structs for the ScoringEngine

import Foundation

public struct GameState: Codable, Equatable, Sendable {
    public var scoreA: Int = 0
    public var scoreB: Int = 0
    public var gameNumber: Int
    public var hasSwitchedInThirdGame: Bool = false
    public var pointTimestamps: [Date] = []

    public init(gameNumber: Int) {
        self.gameNumber = gameNumber
    }
}

/// Indirect box to allow recursive MatchState storage as a value type
public final class StateSnapshot: @unchecked Sendable {
    public let state: MatchState

    public init(_ state: MatchState) {
        self.state = state
    }
}

public struct MatchState: Sendable {
    public let format: MatchFormat
    public var scoringSystem: ScoringSystem = .standard21
    public var games: [GameState]
    public var currentGame: GameState
    public var matchPhase: MatchPhase = .inProgress
    public var previousSnapshot: StateSnapshot?

    public var previousState: MatchState? {
        get { previousSnapshot?.state }
        set { previousSnapshot = newValue.map { StateSnapshot($0) } }
    }

    // Doubles-specific
    public var servingPlayerIndex: Int = 0
    public var doublesRotation: [PlayerPosition] = []
    public var teamAPositions: [Court] = [.right, .left]
    public var teamBPositions: [Court] = [.right, .left]

    // Player names
    public var teamANames: [String] = ["Player 1"]
    public var teamBNames: [String] = ["Player 2"]

    // Side switch tracking
    public var shouldSwitchSidesFlag: Bool = false

    // MARK: - Factory Methods

    /// Convenience accessor for the current scoring rules.
    public var scoringRules: ScoringRules {
        ScoringRules.rules(for: scoringSystem)
    }

    public static func newSinglesMatch(
        teamAName: String? = nil,
        teamBName: String? = nil,
        scoringSystem: ScoringSystem = .standard21
    ) -> MatchState {
        MatchState(
            format: .singles,
            scoringSystem: scoringSystem,
            games: [],
            currentGame: GameState(gameNumber: 1),
            teamANames: [teamAName ?? "Player 1"],
            teamBNames: [teamBName ?? "Player 2"]
        )
    }

    public static func newDoublesMatch(
        teamANames: [String]? = nil,
        teamBNames: [String]? = nil,
        scoringSystem: ScoringSystem = .standard21
    ) -> MatchState {
        let aNames = teamANames ?? ["Player A1", "Player A2"]
        let bNames = teamBNames ?? ["Player B1", "Player B2"]
        var state = MatchState(
            format: .doubles,
            scoringSystem: scoringSystem,
            games: [],
            currentGame: GameState(gameNumber: 1),
            teamANames: aNames,
            teamBNames: bNames
        )
        state.doublesRotation = MatchState.initialDoublesRotation()
        return state
    }

    public static func newMixedMatch(
        teamANames: [String]? = nil,
        teamBNames: [String]? = nil,
        scoringSystem: ScoringSystem = .standard21
    ) -> MatchState {
        let aNames = teamANames ?? ["Player A1", "Player A2"]
        let bNames = teamBNames ?? ["Player B1", "Player B2"]
        var state = MatchState(
            format: .mixed,
            scoringSystem: scoringSystem,
            games: [],
            currentGame: GameState(gameNumber: 1),
            teamANames: aNames,
            teamBNames: bNames
        )
        state.doublesRotation = MatchState.initialDoublesRotation()
        return state
    }

    // MARK: - Doubles Rotation Setup

    /// Fixed rotation order for doubles:
    /// [0] = initial server (teamA player at right court, index 0)
    /// [1] = player diag opposite initial receiver (teamB player NOT at right court, index 1)
    /// [2] = initial server's partner (teamA other player, index 1)
    /// [3] = initial receiver (teamB player at right court, index 0)
    static func initialDoublesRotation() -> [PlayerPosition] {
        [
            PlayerPosition(side: .sideA, playerIndex: 0),
            PlayerPosition(side: .sideB, playerIndex: 1),
            PlayerPosition(side: .sideA, playerIndex: 1),
            PlayerPosition(side: .sideB, playerIndex: 0),
        ]
    }
}

// MARK: - Rally Analytics

/// Aggregated timing metrics across all games in a match.
public struct RallyAnalytics: Equatable, Sendable {
    /// Total match duration from the first point to the last point across all games.
    public let matchDuration: TimeInterval
    /// Average time between consecutive points (proxy for rally length).
    public let averageRallyLength: TimeInterval
    /// Longest gap between two consecutive points.
    public let longestRally: TimeInterval

    public init(matchDuration: TimeInterval, averageRallyLength: TimeInterval, longestRally: TimeInterval) {
        self.matchDuration = matchDuration
        self.averageRallyLength = averageRallyLength
        self.longestRally = longestRally
    }
}

extension MatchState {
    /// All point timestamps across every game (completed + current), in chronological order.
    public var allPointTimestamps: [Date] {
        (games + [currentGame]).flatMap { $0.pointTimestamps }
    }

    /// Computed rally analytics. Returns `nil` when fewer than two timestamps exist.
    public var rallyAnalytics: RallyAnalytics? {
        let timestamps = allPointTimestamps.sorted()
        guard timestamps.count >= 2 else { return nil }

        let matchDuration = timestamps.last!.timeIntervalSince(timestamps.first!)

        var intervals: [TimeInterval] = []
        for i in 1..<timestamps.count {
            intervals.append(timestamps[i].timeIntervalSince(timestamps[i - 1]))
        }

        let average = intervals.reduce(0, +) / Double(intervals.count)
        let longest = intervals.max() ?? 0

        return RallyAnalytics(
            matchDuration: matchDuration,
            averageRallyLength: average,
            longestRally: longest
        )
    }
}

// MARK: - Equatable (exclude previousState to avoid infinite recursion)

extension MatchState: Equatable {
    public static func == (lhs: MatchState, rhs: MatchState) -> Bool {
        lhs.format == rhs.format
            && lhs.scoringSystem == rhs.scoringSystem
            && lhs.games == rhs.games
            && lhs.currentGame == rhs.currentGame
            && lhs.matchPhase == rhs.matchPhase
            && lhs.servingPlayerIndex == rhs.servingPlayerIndex
            && lhs.doublesRotation == rhs.doublesRotation
            && lhs.teamAPositions == rhs.teamAPositions
            && lhs.teamBPositions == rhs.teamBPositions
            && lhs.teamANames == rhs.teamANames
            && lhs.teamBNames == rhs.teamBNames
            && lhs.shouldSwitchSidesFlag == rhs.shouldSwitchSidesFlag
    }
}
