@preconcurrency import ActivityKit
@preconcurrency import AVFoundation
import Foundation
import SwiftData
import ScoringEngine

@Observable
@MainActor
final class LiveMatchViewModel {
    private(set) var state: MatchState
    private var persistedMatch: PersistedMatch
    private let modelContext: ModelContext

    private var currentActivityID: String?

    // Phase B: continuous capture during a live match.
    // The buffer keeps the last ~10s of frames for post-rally analysis;
    // the recorder owns the AVCaptureSession that feeds it.
    // Both are non-observed (@ObservationIgnored) — UI doesn't render them.
    @ObservationIgnored let frameBuffer: CircularFrameBuffer
    @ObservationIgnored let recorder: GameRecordingService
    /// Real "Rally Ended" suggester. Built once per view model so it
    /// reuses the same `CircularFrameBuffer` and detector instance the
    /// live capture is already filling.
    @ObservationIgnored let rallySuggestor: RallySuggesting

    /// Live capture session, republished from the recorder so SwiftUI
    /// can observe and re-attach the preview layer when it becomes
    /// available. `nil` until `startContinuousCapture()` finishes.
    private(set) var liveCaptureSession: AVCaptureSession?

    var canUndo: Bool { state.previousState != nil }
    var isMatchOver: Bool {
        state.matchPhase == .complete || state.matchPhase == .abandoned
    }
    var showGameEndOverlay: Bool = false
    var justCompletedGame: GameState?

    // MARK: - Crash Recovery

    static func restoreFromPersistedMatch(
        _ match: PersistedMatch,
        modelContext: ModelContext
    ) -> LiveMatchViewModel? {
        guard let stateJSON = match.stateJSON else { return nil }
        let decoder = JSONDecoder()
        guard let codableState = try? decoder.decode(
            CodableMatchState.self, from: stateJSON
        ) else { return nil }
        let state = codableState.toMatchState()
        return LiveMatchViewModel(
            restoringState: state,
            persistedMatch: match,
            modelContext: modelContext
        )
    }

    init(restoringState state: MatchState, persistedMatch: PersistedMatch, modelContext: ModelContext) {
        self.state = state
        self.persistedMatch = persistedMatch
        self.modelContext = modelContext
        self.showGameEndOverlay = false
        // 2-second rolling window. Combined with the recorder's 6×
        // frame-stride (~5 fps effective), this caps retained
        // CVPixelBuffers at ~10 so the camera pool stays unblocked.
        let buffer = CircularFrameBuffer(capacity: 2.0)
        self.frameBuffer = buffer
        self.recorder = GameRecordingService(frameBuffer: buffer)
        self.rallySuggestor = TrajectoryRallySuggestor(
            frameBuffer: buffer,
            detector: TrackNetWindowAdapter(),
            calibration: persistedMatch.calibration
        )
        WatchSyncManager.shared.onScoringIntentReceived = { [weak self] side in
            self?.scorePoint(for: side)
        }
        startLiveActivity()
        // startContinuousCapture is now driven from LiveMatchView.onAppear
        // so the camera session doesn't race the navigation transition.
    }

    init(
        state: MatchState,
        calibration: CalibrationProfile? = nil,
        modelContext: ModelContext
    ) {
        self.state = state
        self.modelContext = modelContext
        // 2-second rolling window. Combined with the recorder's 6×
        // frame-stride (~5 fps effective), this caps retained
        // CVPixelBuffers at ~10 so the camera pool stays unblocked.
        let buffer = CircularFrameBuffer(capacity: 2.0)
        self.frameBuffer = buffer
        self.recorder = GameRecordingService(frameBuffer: buffer)
        self.rallySuggestor = TrajectoryRallySuggestor(
            frameBuffer: buffer,
            detector: TrackNetWindowAdapter(),
            calibration: calibration
        )

        // Create persisted match
        let match = PersistedMatch()
        match.format = state.format.rawValue
        switch state.scoringSystem {
        case .standard21: match.scoringSystemRaw = "standard21"
        case .threeByFifteen: match.scoringSystemRaw = "threeByFifteen"
        case .custom(let rules):
            match.scoringSystemRaw = "custom"
            match.customRulesJSON = try? JSONEncoder().encode(rules)
        }
        match.playerAName = state.teamANames.first
        match.playerBName = state.teamBNames.first
        if state.format != .singles {
            match.playerA2Name = state.teamANames.count > 1
                ? state.teamANames[1] : nil
            match.playerB2Name = state.teamBNames.count > 1
                ? state.teamBNames[1] : nil
        }
        if let calibration {
            modelContext.insert(calibration)
            match.calibration = calibration
        }
        modelContext.insert(match)
        self.persistedMatch = match
        persistState()
        WatchSyncManager.shared.onScoringIntentReceived = { [weak self] side in
            self?.scorePoint(for: side)
        }
        startLiveActivity()
        // startContinuousCapture is now driven from LiveMatchView.onAppear
        // so the camera session doesn't race the navigation transition.
    }

    // MARK: - Scoring

    /// Apply a point for the given side.
    ///
    /// Performance: state mutation is synchronous for immediate UI response;
    /// persistence and Watch sync are dispatched asynchronously to keep the
    /// scoring tap at sub-frame latency.
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

        // Haptic feedback — async to avoid blocking the scoring tap
        let matchComplete = state.matchPhase == .complete
        let gamePoint = state.isDeuce || state.isAtCap
        Task { @MainActor in
            let haptics = HapticFeedbackService.shared
            if matchComplete {
                haptics.playMatchComplete()
            } else if gamePoint {
                haptics.playGamePoint()
            } else {
                haptics.playPointScored()
            }
        }

        // Defer persistence and Watch sync — these are not on the critical render path.
        // Running them after the current run loop iteration lets SwiftUI commit the
        // new score to the screen before we spend ~1-2 ms encoding JSON.
        Task { [weak self] in
            self?.persistState()
        }
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
        stopContinuousCapture()
    }

    // MARK: - Continuous capture

    // Driven from `LiveMatchView.onAppear` / `onDisappear` so the session
    // is only created once the view is on-screen and previous views have
    // had a chance to tear down their own capture sessions. Starting from
    // `init` raced with the navigation transition and crashed the app.
    func startContinuousCapture() {
        Task { @MainActor [weak self, recorder] in
            await recorder.startMatchRecording()
            self?.liveCaptureSession = recorder.captureSession
        }
    }

    func stopContinuousCapture() {
        let session = liveCaptureSession
        liveCaptureSession = nil
        Task { @MainActor [recorder] in
            await recorder.stopMatchRecording()
            _ = session
        }
    }

    // MARK: - Private

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
        if state.matchPhase == .complete, let winner = state.matchWinner {
            persistedMatch.winnerSide = winner.rawValue
        }
        updateGameScores()

        // Watch sync: dispatch to avoid blocking SwiftUI rendering.
        // Skipped in free-Apple-ID mode — WCSession isn't activated and the
        // call still blocks under contention. Every score paid for it.
        if !AppMode.freeAppleIDMode {
            let snapState = state
            let snapActive = snapState.matchPhase == .inProgress
            Task.detached(priority: .utility) {
                WatchSyncManager.shared.sendStateUpdate(snapState, isActive: snapActive)
            }
        }

        if state.matchPhase == .inProgress {
            updateLiveActivity()
        } else if state.matchPhase == .complete || state.matchPhase == .abandoned {
            endLiveActivity()
            stopContinuousCapture()
        }
    }

    // MARK: - Live Activity

    private func startLiveActivity() {
        if AppMode.freeAppleIDMode { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = MatchActivityAttributes(
            teamAName: state.teamANames.first ?? "Side A",
            teamBName: state.teamBNames.first ?? "Side B",
            format: state.format.rawValue
        )
        let contentState = buildContentState()
        let content = ActivityContent(state: contentState, staleDate: nil)
        let activity = try? Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
        currentActivityID = activity?.id
    }

    private func updateLiveActivity() {
        guard let activityID = currentActivityID else { return }
        let scoreA = state.currentGame.scoreA
        let scoreB = state.currentGame.scoreB
        let won = state.gamesWon
        let gameNum = state.games.count + (state.matchPhase == .inProgress ? 1 : 0)
        let server = state.currentServer.side.rawValue
        Task {
            let cs = MatchActivityAttributes.ContentState(
                scoreA: scoreA, scoreB: scoreB, gameNumber: gameNum,
                gamesWonA: won.sideA, gamesWonB: won.sideB,
                serverSide: server, isComplete: false
            )
            guard let activity = Activity<MatchActivityAttributes>.activities.first(where: { $0.id == activityID }) else { return }
            await activity.update(ActivityContent(state: cs, staleDate: nil))
        }
    }

    private func endLiveActivity() {
        guard let activityID = currentActivityID else { return }
        let scoreA = state.currentGame.scoreA
        let scoreB = state.currentGame.scoreB
        let won = state.gamesWon
        let gameNum = state.games.count
        let server = state.currentServer.side.rawValue
        currentActivityID = nil
        Task {
            let cs = MatchActivityAttributes.ContentState(
                scoreA: scoreA, scoreB: scoreB, gameNumber: gameNum,
                gamesWonA: won.sideA, gamesWonB: won.sideB,
                serverSide: server, isComplete: true
            )
            guard let activity = Activity<MatchActivityAttributes>.activities.first(where: { $0.id == activityID }) else { return }
            await activity.end(ActivityContent(state: cs, staleDate: nil), dismissalPolicy: .after(.now + 300))
        }
    }

    private func buildContentState(isComplete: Bool = false) -> MatchActivityAttributes.ContentState {
        let won = state.gamesWon
        return MatchActivityAttributes.ContentState(
            scoreA: state.currentGame.scoreA,
            scoreB: state.currentGame.scoreB,
            gameNumber: state.games.count + (state.matchPhase == .inProgress ? 1 : 0),
            gamesWonA: won.sideA,
            gamesWonB: won.sideB,
            serverSide: state.currentServer.side.rawValue,
            isComplete: isComplete || state.matchPhase == .complete || state.matchPhase == .abandoned
        )
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
        if allGames.count >= 4 {
            persistedMatch.game4ScoreA = allGames[3].scoreA
            persistedMatch.game4ScoreB = allGames[3].scoreB
        }
        if allGames.count >= 5 {
            persistedMatch.game5ScoreA = allGames[4].scoreA
            persistedMatch.game5ScoreB = allGames[4].scoreB
        }
    }
}
