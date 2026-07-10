@preconcurrency import ActivityKit
@preconcurrency import AVFoundation
import Foundation
import SwiftData
import ScoringEngine

@Observable
@MainActor
final class LiveMatchViewModel {
    private(set) var state: MatchState
    /// Read-only outside the view model: MatchEndView hands this to
    /// MatchDetailView for the post-match handoff (restructure PR 4).
    /// All mutation still goes through the view model's own save paths.
    private(set) var persistedMatch: PersistedMatch
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

    /// Seam-B producer: System-2 classifier primary, geometric fallback. The
    /// live rally-end sheet runs through this (via `rallySuggestor`); the score
    /// state machine reads `lastRallyResult` after the user resolves the sheet.
    @ObservationIgnored let rallyResultProducer: LazyRallyResultProducer
    @ObservationIgnored let rallyResultBox: RallyResultBox

    /// Live capture session, republished from the recorder so SwiftUI
    /// can observe and re-attach the preview layer when it becomes
    /// available. `nil` until `startContinuousCapture()` finishes.
    private(set) var liveCaptureSession: AVCaptureSession?

    // MARK: - Footage recording (per game)
    // Metadata for the game currently being recorded to disk. A
    // `GameVideoRecord` row is created from these at each game boundary.
    @ObservationIgnored private var recordingGameNumber: Int = 0
    @ObservationIgnored private var recordingStartedAt: Date?
    @ObservationIgnored private var recordingFileName: String?

    var canUndo: Bool { state.previousState != nil }
    var isMatchOver: Bool {
        state.matchPhase == .complete || state.matchPhase == .abandoned
    }
    var showGameEndOverlay: Bool = false
    var justCompletedGame: GameState?

    /// Most recent `RallyResult` produced for the current rally (full
    /// provenance for the score state machine + override surface). Nil until
    /// the first suggestion runs.
    var lastRallyResult: RallyResult? { rallyResultBox.latest }

    /// Conservative auto-apply confidence threshold (§3.1). Most rallies fall
    /// below this → confirm sheet. Only tighten DOWN once Vision's ground-truth
    /// holdout calibration validates the classifier's (currently overconfident,
    /// heuristic-lineage) confidence. See ClassifierRallyScorer train/serve-skew note.
    @ObservationIgnored private let autoApplyConfidenceThreshold = 0.92

    /// §3.1 decision for the most recently produced `RallyResult`: auto-apply
    /// only when confident AND signals don't conflict AND the landing isn't a
    /// close call (`.uncertain`). `.human` results are authoritative; conflict,
    /// uncertain landings, and low confidence all defer to the user.
    func shouldAutoApplyLastResult() -> Bool {
        guard let r = rallyResultBox.latest else { return false }
        if r.source == .human { return true }
        if r.corroboration == .conflict { return false }
        if let landing = r.landing, landing.result == .uncertain { return false }
        return r.confidence >= autoApplyConfidenceThreshold
    }

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
        let (producer, suggestor, box) = Self.makeRallyScoring(
            buffer: buffer, calibration: persistedMatch.calibration
        )
        self.rallyResultProducer = producer
        self.rallySuggestor = suggestor
        self.rallyResultBox = box
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
        let (producer, suggestor, box) = Self.makeRallyScoring(
            buffer: buffer, calibration: calibration
        )
        self.rallyResultProducer = producer
        self.rallySuggestor = suggestor
        self.rallyResultBox = box

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

    // MARK: - Rally scoring wiring

    /// Builds the seam-B scoring stack: the System-2 `ClassifierRallyScorer`
    /// (only when the trained model is bundled) as the primary producer, with
    /// the geometric `TrajectoryRallySuggestor` as the fallback, plus the
    /// `RallySuggesting` adapter the live sheet drives. Both share the same
    /// `CircularFrameBuffer` the capture session is already filling.
    ///
    /// Performance: the actual stack — which loads the `RallyWinnerClassifier`
    /// CoreML model and allocates two `CIContext`s inside the detector adapters
    /// — is built **lazily on a background task** via `LazyRallyResultProducer`.
    /// Doing it synchronously here blocked the main actor during the navigation
    /// transition into the live match (the "extreme lag at match start"). The
    /// stack is warmed up from `startContinuousCapture()` once the view is
    /// on-screen, so the first "Rally Ended" tap is already hot.
    @MainActor
    private static func makeRallyScoring(
        buffer: CircularFrameBuffer,
        calibration: CalibrationProfile?
    ) -> (LazyRallyResultProducer, RallySuggesting, RallyResultBox) {
        // Snapshot the (non-Sendable, main-actor) calibration into a Sendable
        // value up front so the off-main build closure captures only Sendable
        // state.
        let calibrationSnapshot = Self.calibrationSnapshot(calibration)
        // The detector adapters (each allocate a `CIContext`) and the CoreML
        // model are the heavy parts; the whole stack is built lazily on a
        // background task the first time it's needed (warmed from
        // `startContinuousCapture`), so it never blocks the match-start
        // transition.
        let producer = LazyRallyResultProducer {
            let model = ClassifierRallyScorer.loadBundledModel()
            let geometric = TrajectoryRallySuggestor(
                frameBuffer: buffer,
                detector: TrackNetWindowAdapter(),
                calibration: calibrationSnapshot
            )
            let classifier = model.map { model in
                ClassifierRallyScorer(
                    frameBuffer: buffer,
                    detector: TrackNetWindowAdapter(),
                    calibration: calibrationSnapshot,
                    model: model
                )
            }
            return CompositeRallyResultProducer(classifier: classifier, geometric: geometric)
        }
        let box = RallyResultBox()
        let suggestor = ProducerBackedSuggestor(producer: producer, box: box)
        return (producer, suggestor, box)
    }

    /// Reads the values the rally scorers need off a live `CalibrationProfile`
    /// into a `Sendable` snapshot. Main-actor isolated because `@Model` access
    /// is. Returns `nil` when calibration is absent or incomplete.
    @MainActor
    private static func calibrationSnapshot(_ calibration: CalibrationProfile?) -> RallyCalibration? {
        guard let calibration,
              let corners = calibration.corners,
              calibration.imageWidth > 0, calibration.imageHeight > 0
        else { return nil }
        return RallyCalibration(
            corners: corners,
            imageWidth: calibration.imageWidth,
            imageHeight: calibration.imageHeight
        )
    }

    // MARK: - Rally resolution + training export

    /// Resolve the current rally to `side` — confirmed suggestion, auto-applied,
    /// or human override — then persist the finalized `RallyResult` to the
    /// on-device training export before awarding the point. Driven by the
    /// rally-end sheet; manual score taps bypass this (they aren't
    /// classifier-driven rallies, so they shouldn't pollute the training data).
    func resolveRally(for side: Side) {
        let produced = rallyResultBox.latest
        let clip = currentClipRef()
        let finalResult: RallyResult
        if let produced {
            if side == produced.winner {
                // Confirmed or auto-applied — keep the auto provenance, attach clip.
                finalResult = produced.with(clipRef: clip)
            } else {
                // Human override — preserve the auto votes so the correction
                // becomes a gold "human ≠ cv" training example (§6c).
                finalResult = RallyResult.humanOverride(
                    rallyIndex: produced.rallyIndex,
                    winner: side,
                    clipRef: clip,
                    landing: produced.landing,
                    positionVote: produced.positionVote,
                    cvVote: produced.cvVote
                )
            }
        } else {
            // No produced result (e.g. manual rally-end with no detection) —
            // record an authoritative human call.
            finalResult = RallyResult.humanOverride(
                rallyIndex: rallyResultBox.nextIndex(), winner: side, clipRef: clip
            )
        }
        rallyResultBox.record(finalResult)
        TrainingExportWriter.append(finalResult, matchID: persistedMatch.id)
        enqueueForReviewIfNeeded(finalResult)
        scorePoint(for: side)
    }

    // MARK: - Opportunistic review queue (non-blocking override surface)

    /// A finalized rally flagged for optional later review (low confidence or an
    /// uncertain landing). Surfaced as a non-blocking badge — reviewing one
    /// records the user's verdict to the training export. Never blocks play.
    struct ReviewItem: Identifiable, Equatable {
        let id = UUID()
        let result: RallyResult
    }

    /// Calls awaiting optional review, oldest first. Observed → drives the badge.
    private(set) var reviewQueue: [ReviewItem] = []

    /// At/above this confidence a classifier call is solid enough to skip the
    /// queue. Below it (or an `.uncertain` landing) → queue. Conservative
    /// because confidence is provisional (overconfident) pre-calibration.
    @ObservationIgnored private let reviewConfidenceBar = 0.97
    @ObservationIgnored private let maxReviewQueue = 20

    private func enqueueForReviewIfNeeded(_ result: RallyResult) {
        guard result.source != .human else { return }   // user already decided it
        let uncertainLanding = result.landing?.result == .uncertain
        guard uncertainLanding || result.confidence < reviewConfidenceBar else { return }
        reviewQueue.append(ReviewItem(result: result))
        if reviewQueue.count > maxReviewQueue {
            reviewQueue.removeFirst(reviewQueue.count - maxReviewQueue)
        }
    }

    /// Record the user's reviewed verdict for a queued call: writes a
    /// human-sourced `RallyResult` to the training export (preserving the
    /// classifier vote, so a differing verdict is a gold corrected example) and
    /// dequeues it. Does NOT retroactively change the live score — the point was
    /// already played; this captures the ground-truth label for the flywheel.
    func recordReviewVerdict(for item: ReviewItem, winner: Side) {
        let r = item.result
        let humanResult = RallyResult.humanOverride(
            rallyIndex: r.rallyIndex,
            winner: winner,
            clipRef: r.clipRef,
            landing: r.landing,
            positionVote: r.positionVote,
            cvVote: r.cvVote
        )
        TrainingExportWriter.append(humanResult, matchID: persistedMatch.id)
        reviewQueue.removeAll { $0.id == item.id }
    }

    /// Remove a queued call without recording a verdict (user agrees with the
    /// auto call, or doesn't want to review it).
    func dismissReview(_ item: ReviewItem) {
        reviewQueue.removeAll { $0.id == item.id }
    }

    /// Best-effort clip pointer into the current game video: the last
    /// ~2 s rally-suggestion window expressed as offsets from the game
    /// recording start. `nil` until a game recording is in progress.
    private func currentClipRef() -> ClipRef? {
        guard let fileName = recordingFileName, let start = recordingStartedAt else {
            return nil
        }
        let elapsed = Date().timeIntervalSince(start)
        return ClipRef(
            fileName: fileName,
            startTime: max(0, elapsed - 2.0),
            endTime: max(0, elapsed)
        )
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
            if let completed = state.games.last {
                finishGameFootage(
                    completed: completed,
                    isMatchOver: state.matchPhase == .complete
                )
            }
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
        // Capture the partial current game's footage before tearing down.
        let partialGame = state.currentGame
        state = MatchEngine.apply(event: .abandon, to: state)
        if recordingFileName != nil {
            finishGameFootage(completed: partialGame, isMatchOver: true)
        }
        persistState()
        stopContinuousCapture()
    }

    // MARK: - Continuous capture

    // Driven from `LiveMatchView.onAppear` / `onDisappear` so the session
    // is only created once the view is on-screen and previous views have
    // had a chance to tear down their own capture sessions. Starting from
    // `init` raced with the navigation transition and crashed the app.
    func startContinuousCapture() {
        // Warm the rally-scoring stack (CoreML load + CIContext alloc) on a
        // background task now that the view is on-screen, so the first
        // "Rally Ended" tap is hot without blocking the match-start transition.
        rallyResultProducer.warmUp()
        Task { @MainActor [weak self, recorder] in
            await recorder.startMatchRecording()
            guard let self else { return }
            self.liveCaptureSession = recorder.captureSession
            // Begin footage for the in-progress game if we haven't already
            // (guards against a second onAppear re-triggering capture).
            if self.recordingFileName == nil,
               self.state.matchPhase == .inProgress {
                self.beginGameFootage(gameNumber: self.state.games.count + 1)
            }
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

    // MARK: - Footage recording (per game)

    /// Starts recording the given game number to a fresh file and tracks
    /// its metadata for the eventual `GameVideoRecord`.
    private func beginGameFootage(gameNumber: Int) {
        let fileName = "\(persistedMatch.id.uuidString)-game\(gameNumber).mp4"
        recordingGameNumber = gameNumber
        recordingStartedAt = Date()
        recordingFileName = fileName
        recorder.startGameRecording(fileName: fileName)
    }

    /// Finalises the in-flight recording, persists a `GameVideoRecord` for
    /// the completed game, and — unless the match is over — begins the next
    /// game's recording. File finalisation is async, so this runs off the
    /// scoring tap's critical path.
    private func finishGameFootage(completed: GameState, isMatchOver: Bool) {
        let gameNumber = recordingGameNumber
        let startedAt = recordingStartedAt ?? Date()
        let fileName = recordingFileName ?? ""
        let scoreA = completed.scoreA
        let scoreB = completed.scoreB
        // Clear so a re-entrant boundary (or abandon after complete) is a no-op.
        recordingFileName = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            let didWrite = await self.recorder.finishCurrentGameRecording()
            let record = GameVideoRecord(
                gameNumber: gameNumber,
                fileName: didWrite ? fileName : "",
                startedAt: startedAt,
                endedAt: Date(),
                rallyCount: scoreA + scoreB,
                scoreA: scoreA,
                scoreB: scoreB,
                locationName: nil
            )
            self.modelContext.insert(record)
            record.match = self.persistedMatch
            if self.persistedMatch.gameVideos == nil {
                self.persistedMatch.gameVideos = []
            }
            self.persistedMatch.gameVideos?.append(record)
            try? self.modelContext.save()
            if !isMatchOver {
                self.beginGameFootage(gameNumber: gameNumber + 1)
            }
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
