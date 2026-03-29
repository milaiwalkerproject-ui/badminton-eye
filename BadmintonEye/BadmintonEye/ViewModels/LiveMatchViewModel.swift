import Foundation
import SwiftData
import ScoringEngine

@Observable
final class LiveMatchViewModel {
    private(set) var state: MatchState
    private var persistedMatch: PersistedMatch
    private let modelContext: ModelContext

    var canUndo: Bool { state.previousState != nil }
    var isMatchOver: Bool {
        state.matchPhase == .complete || state.matchPhase == .abandoned
    }
    var showGameEndOverlay: Bool = false
    var justCompletedGame: GameState?

    init(state: MatchState, modelContext: ModelContext) {
        self.state = state
        self.modelContext = modelContext

        // Create persisted match
        let match = PersistedMatch()
        match.format = state.format.rawValue
        match.playerAName = state.teamANames.first
        match.playerBName = state.teamBNames.first
        if state.format != .singles {
            match.playerA2Name = state.teamANames.count > 1
                ? state.teamANames[1] : nil
            match.playerB2Name = state.teamBNames.count > 1
                ? state.teamBNames[1] : nil
        }
        modelContext.insert(match)
        self.persistedMatch = match
        persistState()
    }

    func scorePoint(for side: Side) {
        guard state.matchPhase == .inProgress else { return }
        let previousGameCount = state.games.count
        state = MatchEngine.apply(event: .scorePoint(side), to: state)
        if state.games.count > previousGameCount {
            // A game just ended
            justCompletedGame = state.games.last
            if state.matchPhase != .complete {
                showGameEndOverlay = true
            }
        }
        persistState()
    }

    func undo() {
        state = MatchEngine.apply(event: .undo, to: state)
        showGameEndOverlay = false
        justCompletedGame = nil
        persistState()
    }

    func abandonMatch() {
        state = MatchEngine.apply(event: .abandon, to: state)
        persistState()
    }

    private func persistState() {
        let encoder = JSONEncoder()
        persistedMatch.stateJSON = try? encoder.encode(
            CodableMatchState(from: state)
        )
        persistedMatch.isComplete = state.matchPhase == .complete
        persistedMatch.isAbandoned = state.matchPhase == .abandoned
        if state.matchPhase == .complete || state.matchPhase == .abandoned {
            persistedMatch.endedAt = Date()
        }
        updateGameScores()
    }

    private func updateGameScores() {
        let allGames = state.games
            + (state.matchPhase == .inProgress ? [state.currentGame] : [])
        if allGames.count >= 1 {
            persistedMatch.game1ScoreA = allGames[0].scoreA
            persistedMatch.game1ScoreB = allGames[0].scoreB
        }
        if allGames.count >= 2 {
            persistedMatch.game2ScoreA = allGames[1].scoreA
            persistedMatch.game2ScoreB = allGames[1].scoreB
        }
        if allGames.count >= 3 {
            persistedMatch.game3ScoreA = allGames[2].scoreA
            persistedMatch.game3ScoreB = allGames[2].scoreB
        }
    }
}
