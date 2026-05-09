import Testing
import Foundation
@testable import ScoringEngine

struct PointTimestampsTests {

    // MARK: - GameState default

    @Test("GameState initialises with empty pointTimestamps")
    func gameStateDefaultTimestamps() {
        let game = GameState(gameNumber: 1)
        #expect(game.pointTimestamps.isEmpty)
    }

    // MARK: - Timestamp recording

    @Test("scorePoint appends one timestamp per point")
    func scorePointAppendsTimestamp() {
        let state = MatchState.newSinglesMatch()
        let before = Date()
        let next = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        let after = Date()

        #expect(next.currentGame.pointTimestamps.count == 1)
        let ts = next.currentGame.pointTimestamps[0]
        #expect(ts >= before)
        #expect(ts <= after)
    }

    @Test("Multiple scorePoint calls accumulate timestamps")
    func multiplePointsAccumulateTimestamps() {
        var state = MatchState.newSinglesMatch()
        for _ in 0..<5 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.currentGame.pointTimestamps.count == 5)
    }

    @Test("Timestamps for sideB are also recorded")
    func sideBTimestampsRecorded() {
        var state = MatchState.newSinglesMatch()
        state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        #expect(state.currentGame.pointTimestamps.count == 2)
    }

    @Test("Mixed sideA and sideB both add timestamps")
    func mixedSidesTimestamps() {
        var state = MatchState.newSinglesMatch()
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.currentGame.pointTimestamps.count == 3)
    }

    @Test("No timestamp appended when match is complete")
    func noTimestampWhenMatchComplete() {
        var state = MatchState.newSinglesMatch()
        // Win 2 games 21-0 each
        for _ in 0..<21 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        for _ in 0..<21 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        #expect(state.matchPhase == .complete)

        let countBefore = state.currentGame.pointTimestamps.count
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.currentGame.pointTimestamps.count == countBefore)
    }

    // MARK: - Timestamps survive game transition

    @Test("Completed game retains its timestamps in games array")
    func completedGameRetainsTimestamps() {
        var state = MatchState.newSinglesMatch()
        // Score 21 points for sideA to end game 1
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.games.count == 1)
        #expect(state.games[0].pointTimestamps.count == 21)
        // New game starts fresh
        #expect(state.currentGame.pointTimestamps.isEmpty)
    }

    @Test("New game starts with empty pointTimestamps")
    func newGameHasEmptyTimestamps() {
        var state = MatchState.newSinglesMatch()
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        // After game ends, currentGame is game 2
        #expect(state.currentGame.gameNumber == 2)
        #expect(state.currentGame.pointTimestamps.isEmpty)
    }

    // MARK: - allPointTimestamps

    @Test("allPointTimestamps returns timestamps from all games plus currentGame")
    func allPointTimestampsSpansGames() {
        var state = MatchState.newSinglesMatch()
        // Finish game 1 (21 points)
        for _ in 0..<21 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        // Score 3 in game 2
        for _ in 0..<3 {
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        // 21 from game1 + 3 from game2 current
        #expect(state.allPointTimestamps.count == 24)
    }

    @Test("allPointTimestamps empty when no points scored")
    func allPointTimestampsEmptyOnStart() {
        let state = MatchState.newSinglesMatch()
        #expect(state.allPointTimestamps.isEmpty)
    }

    // MARK: - rallyAnalytics nil guard

    @Test("rallyAnalytics returns nil with zero timestamps")
    func analyticsNilWithNoTimestamps() {
        let state = MatchState.newSinglesMatch()
        #expect(state.rallyAnalytics == nil)
    }

    @Test("rallyAnalytics returns nil with only one timestamp")
    func analyticsNilWithOneTimestamp() {
        var state = MatchState.newSinglesMatch()
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.rallyAnalytics == nil)
    }

    // MARK: - matchDuration

    @Test("matchDuration equals last minus first timestamp")
    func matchDurationComputation() {
        var state = MatchState.newSinglesMatch()
        // Inject two controlled timestamps via direct manipulation
        var game = GameState(gameNumber: 1)
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let t1 = Date(timeIntervalSinceReferenceDate: 60)  // 60s later
        let t2 = Date(timeIntervalSinceReferenceDate: 90)  // 90s from t0
        game.scoreA = 3
        game.pointTimestamps = [t0, t1, t2]
        state.currentGame = game

        let analytics = state.rallyAnalytics
        #expect(analytics != nil)
        #expect(analytics!.matchDuration == 90)
    }

    // MARK: - averageRallyLength

    @Test("averageRallyLength is mean of consecutive intervals")
    func averageRallyLengthComputation() {
        var state = MatchState.newSinglesMatch()
        var game = GameState(gameNumber: 1)
        // Gaps: 10s, 20s, 30s -> average = 20s
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let t1 = Date(timeIntervalSinceReferenceDate: 10)
        let t2 = Date(timeIntervalSinceReferenceDate: 30)
        let t3 = Date(timeIntervalSinceReferenceDate: 60)
        game.scoreA = 4
        game.pointTimestamps = [t0, t1, t2, t3]
        state.currentGame = game

        let analytics = state.rallyAnalytics!
        #expect(analytics.averageRallyLength == 20)
    }

    // MARK: - longestRally

    @Test("longestRally is the maximum consecutive timestamp gap")
    func longestRallyComputation() {
        var state = MatchState.newSinglesMatch()
        var game = GameState(gameNumber: 1)
        // Gaps: 5s, 50s, 10s -> longest = 50s
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        let t1 = Date(timeIntervalSinceReferenceDate: 5)
        let t2 = Date(timeIntervalSinceReferenceDate: 55)
        let t3 = Date(timeIntervalSinceReferenceDate: 65)
        game.scoreA = 4
        game.pointTimestamps = [t0, t1, t2, t3]
        state.currentGame = game

        let analytics = state.rallyAnalytics!
        #expect(analytics.longestRally == 50)
    }

    // MARK: - Cross-game analytics

    @Test("rallyAnalytics spans timestamps across multiple completed games")
    func analyticsSpansMultipleGames() {
        var state = MatchState.newSinglesMatch()

        // Manually build a match with two completed games that have known timestamps
        var game1 = GameState(gameNumber: 1)
        game1.scoreA = 21
        game1.scoreB = 0
        let base = Date(timeIntervalSinceReferenceDate: 0)
        // 21 points, each 10s apart: 0, 10, 20 ... 200
        game1.pointTimestamps = (0..<21).map { Date(timeIntervalSinceReferenceDate: Double($0) * 10) }

        var game2 = GameState(gameNumber: 2)
        game2.scoreA = 21
        game2.scoreB = 0
        // Starts at 210s, each 5s apart: 210, 215 ... 310
        game2.pointTimestamps = (0..<21).map { Date(timeIntervalSinceReferenceDate: 210 + Double($0) * 5) }

        state.games = [game1]
        state.currentGame = game2

        let analytics = state.rallyAnalytics!

        // Duration: last timestamp 210+20*5=310, first 0 -> 310
        #expect(analytics.matchDuration == 310)

        // Intervals: 20 gaps of 10s in game1, gap from game1 last (200) to game2 first (210) = 10s,
        // then 20 gaps of 5s in game2. Total 41 intervals.
        // Sum = 20*10 + 10 + 20*5 = 200+10+100 = 310. Average = 310/41
        let expectedAvg = 310.0 / 41.0
        #expect(abs(analytics.averageRallyLength - expectedAvg) < 0.001)

        // Longest: max(10s * 20, 10s cross-game gap, 5s * 20) = 10s
        #expect(analytics.longestRally == 10)
    }

    // MARK: - Codable round-trip

    @Test("GameState pointTimestamps survive JSON round-trip")
    func pointTimestampsCodeable() throws {
        var game = GameState(gameNumber: 1)
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let t1 = Date(timeIntervalSinceReferenceDate: 1_000_010)
        game.pointTimestamps = [t0, t1]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let data = try encoder.encode(game)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(GameState.self, from: data)

        #expect(decoded.pointTimestamps.count == 2)
        #expect(abs(decoded.pointTimestamps[0].timeIntervalSinceReferenceDate - t0.timeIntervalSinceReferenceDate) < 0.001)
        #expect(abs(decoded.pointTimestamps[1].timeIntervalSinceReferenceDate - t1.timeIntervalSinceReferenceDate) < 0.001)
    }

    // MARK: - Equatable

    @Test("GameState with different pointTimestamps are not equal")
    func gameStateEquatable() {
        var g1 = GameState(gameNumber: 1)
        g1.pointTimestamps = [Date(timeIntervalSinceReferenceDate: 0)]

        var g2 = GameState(gameNumber: 1)
        g2.pointTimestamps = [Date(timeIntervalSinceReferenceDate: 1)]

        #expect(g1 != g2)
    }

    @Test("GameState with identical pointTimestamps are equal")
    func gameStateEquatableSame() {
        let t = Date(timeIntervalSinceReferenceDate: 42)
        var g1 = GameState(gameNumber: 1)
        g1.pointTimestamps = [t]

        var g2 = GameState(gameNumber: 1)
        g2.pointTimestamps = [t]

        #expect(g1 == g2)
    }

    // MARK: - Undo does not double-count timestamps

    @Test("Undo reverts to previous state, removing the last timestamp")
    func undoRevertsTimestamp() {
        var state = MatchState.newSinglesMatch()
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        let countAfterOne = state.currentGame.pointTimestamps.count
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        let countAfterTwo = state.currentGame.pointTimestamps.count
        state = MatchEngine.apply(event: .undo, to: state)
        #expect(state.currentGame.pointTimestamps.count == countAfterOne)
        #expect(countAfterTwo == countAfterOne + 1)
    }

    // MARK: - RallyAnalytics equality

    @Test("RallyAnalytics Equatable conformance")
    func rallyAnalyticsEquatable() {
        let a = RallyAnalytics(matchDuration: 100, averageRallyLength: 10, longestRally: 20)
        let b = RallyAnalytics(matchDuration: 100, averageRallyLength: 10, longestRally: 20)
        let c = RallyAnalytics(matchDuration: 200, averageRallyLength: 10, longestRally: 20)
        #expect(a == b)
        #expect(a != c)
    }
}
