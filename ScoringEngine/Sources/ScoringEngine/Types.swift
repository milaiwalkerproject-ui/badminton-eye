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
