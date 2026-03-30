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

/// Scoring format: standard BWF 21-point, 3×15, or user-defined custom rules.
public enum ScoringSystem: Sendable, Equatable, Hashable {
    case standard21
    case threeByFifteen
    case custom(ScoringRules)
}

// MARK: - ScoringSystem Codable (backward-compatible with v1.2 raw strings)

extension ScoringSystem: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, rules
    }

    public init(from decoder: Decoder) throws {
        // Try v1.2 format first: plain string
        if let container = try? decoder.singleValueContainer(),
           let raw = try? container.decode(String.self) {
            switch raw {
            case "standard21": self = .standard21
            case "threeByFifteen": self = .threeByFifteen
            default: self = .standard21 // Unknown format fallback
            }
            return
        }
        // v1.3+ format: keyed container with type + optional rules
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "standard21": self = .standard21
        case "threeByFifteen": self = .threeByFifteen
        case "custom":
            let rules = try container.decode(ScoringRules.self, forKey: .rules)
            self = .custom(rules)
        default: self = .standard21
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .standard21:
            var container = encoder.singleValueContainer()
            try container.encode("standard21")
        case .threeByFifteen:
            var container = encoder.singleValueContainer()
            try container.encode("threeByFifteen")
        case .custom(let rules):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("custom", forKey: .type)
            try container.encode(rules, forKey: .rules)
        }
    }
}

/// Parameterized scoring thresholds — eliminates hardcoded magic numbers.
public struct ScoringRules: Codable, Sendable, Equatable, Hashable {
    public let pointsToWin: Int
    public let deuceThreshold: Int
    public let capScore: Int
    public let gamesToWin: Int
    public let maxGames: Int
    public let midGameSwitchPoint: Int

    public init(
        pointsToWin: Int, deuceThreshold: Int, capScore: Int,
        gamesToWin: Int, maxGames: Int, midGameSwitchPoint: Int
    ) {
        self.pointsToWin = pointsToWin
        self.deuceThreshold = deuceThreshold
        self.capScore = capScore
        self.gamesToWin = gamesToWin
        self.maxGames = maxGames
        self.midGameSwitchPoint = midGameSwitchPoint
    }

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
        case .custom(let rules): return rules
        }
    }

    /// Validate that the rules are internally consistent.
    public var isValid: Bool {
        pointsToWin > 0
            && deuceThreshold > 0
            && deuceThreshold < capScore
            && capScore > pointsToWin
            && gamesToWin > 0
            && maxGames >= gamesToWin * 2 - 1
            && maxGames <= 5
            && midGameSwitchPoint > 0
            && midGameSwitchPoint < pointsToWin
    }
}
