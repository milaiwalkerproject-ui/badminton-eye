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
}
