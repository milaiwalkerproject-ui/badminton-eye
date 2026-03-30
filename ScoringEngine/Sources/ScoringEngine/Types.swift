// Types.swift — Core enums and value types for the ScoringEngine

public enum MatchFormat: String, Codable, Sendable, Equatable {
    case singles
    case doubles
    case mixed
}

public enum Side: String, Codable, Sendable, Equatable {
    case sideA
    case sideB

    public var opposite: Side {
        self == .sideA ? .sideB : .sideA
    }
}

public enum Court: String, Codable, Sendable, Equatable {
    case right
    case left

    public var opposite: Court {
        self == .right ? .left : .right
    }
}

public enum MatchPhase: String, Codable, Sendable, Equatable {
    case inProgress
    case complete
    case abandoned
}

public struct PlayerPosition: Codable, Sendable, Equatable {
    public var side: Side
    public var playerIndex: Int // 0 or 1 within the side (for doubles)

    public init(side: Side, playerIndex: Int) {
        self.side = side
        self.playerIndex = playerIndex
    }
}

public enum MatchEvent: Codable, Sendable, Equatable {
    case scorePoint(Side)
    case undo
    case abandon
}

/// Scoring format: standard BWF 21-point (best-of-3) or 3×15 (best-of-5).
public enum ScoringSystem: String, Codable, Sendable, Equatable {
    case standard21
    case threeByFifteen
}

/// Parameterized scoring thresholds — eliminates hardcoded magic numbers.
public struct ScoringRules: Sendable, Equatable {
    public let pointsToWin: Int
    public let deuceThreshold: Int
    public let capScore: Int
    public let gamesToWin: Int
    public let maxGames: Int
    public let midGameSwitchPoint: Int

    public static let standard21 = ScoringRules(
        pointsToWin: 21, deuceThreshold: 20, capScore: 30,
        gamesToWin: 2, maxGames: 3, midGameSwitchPoint: 11
    )

    public static let threeByFifteen = ScoringRules(
        pointsToWin: 15, deuceThreshold: 14, capScore: 17,
        gamesToWin: 3, maxGames: 5, midGameSwitchPoint: 8
    )

    public static func rules(for system: ScoringSystem) -> ScoringRules {
        switch system {
        case .standard21: return .standard21
        case .threeByFifteen: return .threeByFifteen
        }
    }
}
