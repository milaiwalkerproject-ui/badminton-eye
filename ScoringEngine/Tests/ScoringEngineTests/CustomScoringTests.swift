import Foundation
import Testing
@testable import ScoringEngine

@Suite("Custom Scoring & Codable Tests")
struct CustomScoringTests {

    // MARK: - TEST-01: Custom rules play a correct match

    @Test("Custom 11-point best-of-3 match plays correctly")
    func customElevenPointMatch() {
        let rules = ScoringRules(
            pointsToWin: 11, deuceThreshold: 10, capScore: 15,
            gamesToWin: 2, maxGames: 3, midGameSwitchPoint: 6
        )
        var state = MatchState.newSinglesMatch(scoringSystem: .custom(rules))

        // Win first game 11-0
        for _ in 0..<11 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.games.count == 1)
        #expect(state.games[0].scoreA == 11)
        #expect(state.matchPhase == .inProgress)

        // Win second game 11-0 -> match complete
        for _ in 0..<11 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        #expect(state.matchPhase == .complete)
        #expect(state.matchWinner == .sideA)
        #expect(state.gamesWon.sideA == 2)
    }

    @Test("Custom 7-point single-game match")
    func customSevenPointSingleGame() {
        let rules = ScoringRules(
            pointsToWin: 7, deuceThreshold: 6, capScore: 10,
            gamesToWin: 1, maxGames: 1, midGameSwitchPoint: 4
        )
        var state = MatchState.newSinglesMatch(scoringSystem: .custom(rules))

        for _ in 0..<7 {
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        #expect(state.matchPhase == .complete)
        #expect(state.matchWinner == .sideB)
    }

    // MARK: - TEST-02: ScoringRules.isValid

    @Test("Valid standard rules pass validation")
    func validStandardRules() {
        #expect(ScoringRules.standard21.isValid)
    }

    @Test("Valid 3x15 rules pass validation")
    func validThreeByFifteen() {
        #expect(ScoringRules.threeByFifteen.isValid)
    }

    @Test("Valid custom rules pass validation")
    func validCustomRules() {
        let rules = ScoringRules(
            pointsToWin: 11, deuceThreshold: 10, capScore: 15,
            gamesToWin: 2, maxGames: 3, midGameSwitchPoint: 6
        )
        #expect(rules.isValid)
    }

    @Test("Zero points-to-win is invalid")
    func zeroPointsInvalid() {
        let rules = ScoringRules(
            pointsToWin: 0, deuceThreshold: 0, capScore: 1,
            gamesToWin: 1, maxGames: 1, midGameSwitchPoint: 0
        )
        #expect(!rules.isValid)
    }

    @Test("Deuce >= cap is invalid")
    func deuceAboveCapInvalid() {
        let rules = ScoringRules(
            pointsToWin: 11, deuceThreshold: 15, capScore: 15,
            gamesToWin: 2, maxGames: 3, midGameSwitchPoint: 6
        )
        #expect(!rules.isValid)
    }

    @Test("Even maxGames for gamesToWin=2 is invalid (need best-of-odd)")
    func evenGamesInvalid() {
        // gamesToWin=2 needs maxGames >= 3 (2*2-1), but maxGames=2 would be invalid
        let rules = ScoringRules(
            pointsToWin: 11, deuceThreshold: 10, capScore: 15,
            gamesToWin: 2, maxGames: 2, midGameSwitchPoint: 6
        )
        #expect(!rules.isValid)
    }

    @Test("maxGames > 5 is invalid")
    func maxGamesOverFiveInvalid() {
        let rules = ScoringRules(
            pointsToWin: 11, deuceThreshold: 10, capScore: 15,
            gamesToWin: 4, maxGames: 7, midGameSwitchPoint: 6
        )
        #expect(!rules.isValid)
    }

    @Test("midGameSwitchPoint >= pointsToWin is invalid")
    func switchPointTooHighInvalid() {
        let rules = ScoringRules(
            pointsToWin: 11, deuceThreshold: 10, capScore: 15,
            gamesToWin: 2, maxGames: 3, midGameSwitchPoint: 11
        )
        #expect(!rules.isValid)
    }

    // MARK: - TEST-03: ScoringSystem Codable round-trip

    @Test("standard21 encodes and decodes correctly")
    func codableStandard21() throws {
        let original: ScoringSystem = .standard21
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScoringSystem.self, from: data)
        #expect(decoded == original)
    }

    @Test("threeByFifteen encodes and decodes correctly")
    func codableThreeByFifteen() throws {
        let original: ScoringSystem = .threeByFifteen
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScoringSystem.self, from: data)
        #expect(decoded == original)
    }

    @Test("custom rules encode and decode correctly")
    func codableCustom() throws {
        let rules = ScoringRules(
            pointsToWin: 11, deuceThreshold: 10, capScore: 15,
            gamesToWin: 2, maxGames: 3, midGameSwitchPoint: 6
        )
        let original: ScoringSystem = .custom(rules)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScoringSystem.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - TEST-04: v1.2 backward-compatible string decoding

    @Test("v1.2 raw string 'standard21' decodes correctly")
    func backwardCompatStandard21() throws {
        let json = Data("\"standard21\"".utf8)
        let decoded = try JSONDecoder().decode(ScoringSystem.self, from: json)
        #expect(decoded == .standard21)
    }

    @Test("v1.2 raw string 'threeByFifteen' decodes correctly")
    func backwardCompatThreeByFifteen() throws {
        let json = Data("\"threeByFifteen\"".utf8)
        let decoded = try JSONDecoder().decode(ScoringSystem.self, from: json)
        #expect(decoded == .threeByFifteen)
    }

    @Test("Unknown v1.2 raw string falls back to standard21")
    func backwardCompatUnknownFallback() throws {
        let json = Data("\"unknownFormat\"".utf8)
        let decoded = try JSONDecoder().decode(ScoringSystem.self, from: json)
        #expect(decoded == .standard21)
    }

    // MARK: - TEST-05: Abandon event

    @Test("Abandon transitions match to abandoned phase")
    func abandonMatch() {
        var state = MatchState.newSinglesMatch()
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        state = MatchEngine.apply(event: .abandon, to: state)
        #expect(state.matchPhase == .abandoned)
        #expect(state.matchWinner == nil)
    }

    @Test("Abandon preserves undo history")
    func abandonPreservesUndo() {
        var state = MatchState.newSinglesMatch()
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        state = MatchEngine.apply(event: .abandon, to: state)
        #expect(state.matchPhase == .abandoned)
        // Undo should restore to pre-abandon
        let restored = MatchEngine.apply(event: .undo, to: state)
        #expect(restored.matchPhase == .inProgress)
        #expect(restored.currentGame.scoreA == 1)
    }

    @Test("Scoring after abandon is ignored")
    func scoreAfterAbandonIgnored() {
        var state = MatchState.newSinglesMatch()
        state = MatchEngine.apply(event: .abandon, to: state)
        let afterScore = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(afterScore.currentGame.scoreA == 0)
        #expect(afterScore.matchPhase == .abandoned)
    }

    // MARK: - TEST-06: Custom scoring deuce/cap edge cases

    @Test("Custom deuce requires 2-point lead")
    func customDeuceRequiresTwoPointLead() {
        let rules = ScoringRules(
            pointsToWin: 11, deuceThreshold: 10, capScore: 15,
            gamesToWin: 2, maxGames: 3, midGameSwitchPoint: 6
        )
        var state = MatchState.newSinglesMatch(scoringSystem: .custom(rules))
        // Get to 10-10
        for _ in 0..<10 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        #expect(state.isDeuce)
        // 11-10 does not win
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(!state.isGameWon)
        #expect(state.games.count == 0) // game not completed
        // 12-10 wins
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.games.count == 1)
        #expect(state.games[0].scoreA == 12)
    }

    @Test("Custom cap score ends game at 1-point lead")
    func customCapEndsGame() {
        let rules = ScoringRules(
            pointsToWin: 11, deuceThreshold: 10, capScore: 13,
            gamesToWin: 2, maxGames: 3, midGameSwitchPoint: 6
        )
        var state = MatchState.newSinglesMatch(scoringSystem: .custom(rules))
        // Get to 12-12 (cap - 1 each)
        for _ in 0..<10 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        // 11-10
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        // 11-11
        state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        // 12-11
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        // 12-12
        state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        #expect(state.isAtCap)
        // 13-12 = cap, game over regardless of lead
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.games.count == 1)
        #expect(state.games[0].scoreA == 13)
    }

    @Test("Custom doubles match with custom rules works")
    func customDoublesMatch() {
        let rules = ScoringRules(
            pointsToWin: 11, deuceThreshold: 10, capScore: 15,
            gamesToWin: 2, maxGames: 3, midGameSwitchPoint: 6
        )
        var state = MatchState.newDoublesMatch(scoringSystem: .custom(rules))
        // Win two games
        for _ in 0..<2 {
            for _ in 0..<11 {
                state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            }
        }
        #expect(state.matchPhase == .complete)
        #expect(state.matchWinner == .sideA)
    }

    // MARK: - TEST-07: Custom mid-game switch (CST-MID-01)

    @Test("Custom: mid-game switch fires at midGameSwitchPoint in final game")
    func customMidGameSwitchFiresInFinalGame() {
        // 11-point best-of-3 with midGameSwitchPoint=6
        let rules = ScoringRules(
            pointsToWin: 11, deuceThreshold: 10, capScore: 15,
            gamesToWin: 2, maxGames: 3, midGameSwitchPoint: 6
        )
        var state = MatchState.newSinglesMatch(scoringSystem: .custom(rules))
        // Reach game 3: A wins game 1, B wins game 2
        for _ in 0..<11 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        for _ in 0..<11 { state = MatchEngine.apply(event: .scorePoint(.sideB), to: state) }
        #expect(state.currentGame.gameNumber == 3)

        // Score 5 points (one below the switch point of 6)
        for _ in 0..<5 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        #expect(state.currentGame.hasSwitchedInThirdGame == false)
        #expect(state.shouldSwitchSidesFlag == false)

        // Score the 6th point — switch fires
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.currentGame.scoreA == 6)
        #expect(state.shouldSwitchSidesFlag == true)
        #expect(state.currentGame.hasSwitchedInThirdGame == true)
    }

    // MARK: - TEST-08: Custom mid-game switch fires only once (CST-MID-02)

    @Test("Custom: mid-game switch fires only once in final game")
    func customMidGameSwitchFiresOnlyOnce() {
        let rules = ScoringRules(
            pointsToWin: 11, deuceThreshold: 10, capScore: 15,
            gamesToWin: 2, maxGames: 3, midGameSwitchPoint: 6
        )
        var state = MatchState.newSinglesMatch(scoringSystem: .custom(rules))
        // Reach game 3
        for _ in 0..<11 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        for _ in 0..<11 { state = MatchEngine.apply(event: .scorePoint(.sideB), to: state) }
        // Score through the switch point (6 points)
        for _ in 0..<6 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        #expect(state.currentGame.hasSwitchedInThirdGame == true)

        // Additional points should NOT re-fire the switch
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.shouldSwitchSidesFlag == false)

        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        #expect(state.shouldSwitchSidesFlag == false)
    }

    // MARK: - TEST-09: Custom mid-game switch does NOT fire in non-final games (CST-MID-03)

    @Test("Custom: mid-game switch does NOT fire in non-final games")
    func customMidGameSwitchNotInNonFinalGame() {
        let rules = ScoringRules(
            pointsToWin: 11, deuceThreshold: 10, capScore: 15,
            gamesToWin: 2, maxGames: 3, midGameSwitchPoint: 6
        )
        var state = MatchState.newSinglesMatch(scoringSystem: .custom(rules))
        // Score 6 points in game 1 (non-final game) — switch should NOT fire
        for _ in 0..<6 { state = MatchEngine.apply(event: .scorePoint(.sideA), to: state) }
        #expect(state.currentGame.gameNumber == 1)
        #expect(state.currentGame.scoreA == 6)
        #expect(state.currentGame.hasSwitchedInThirdGame == false)
        #expect(state.shouldSwitchSidesFlag == false)
    }

    // MARK: - TEST-10: isValid rejects capScore <= pointsToWin (CST-VAL-04)

    @Test("capScore equal to pointsToWin is invalid")
    func capScoreEqualToPointsToWinInvalid() {
        let rules = ScoringRules(
            pointsToWin: 11, deuceThreshold: 10, capScore: 11,
            gamesToWin: 2, maxGames: 3, midGameSwitchPoint: 6
        )
        #expect(!rules.isValid)
    }

    // MARK: - TEST-11: isValid rejects midGameSwitchPoint == 0 (CST-VAL-05)

    @Test("midGameSwitchPoint of zero is invalid")
    func midGameSwitchPointZeroInvalid() {
        let rules = ScoringRules(
            pointsToWin: 11, deuceThreshold: 10, capScore: 15,
            gamesToWin: 2, maxGames: 3, midGameSwitchPoint: 0
        )
        #expect(!rules.isValid)
    }

    // MARK: - TEST-12: isValid accepts minimal best-of-1 format (CST-VAL-06)

    @Test("Minimal best-of-1 custom format is valid")
    func minimalBestOfOneValid() {
        let rules = ScoringRules(
            pointsToWin: 7, deuceThreshold: 6, capScore: 10,
            gamesToWin: 1, maxGames: 1, midGameSwitchPoint: 4
        )
        #expect(rules.isValid)
    }
}
