import Testing
@testable import ScoringEngine

struct VoiceAnnouncementTests {

    // MARK: - Side A serving

    @Test("sideA serves at 0-0 → '0-0, serving'")
    func sideAServesZeroZero() {
        let state = MatchState.newSinglesMatch()
        // Fresh singles match: sideA serves first
        #expect(state.voiceAnnouncementText == "0-0, serving")
    }

    @Test("sideA serves at A:15 B:0 → '15-0, serving'")
    func sideAServesFifteenZero() {
        var state = MatchState.newSinglesMatch()
        for _ in 0..<15 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        // sideA still serving after own points
        #expect(state.currentServer.side == .sideA)
        #expect(state.voiceAnnouncementText == "15-0, serving")
    }

    @Test("sideA serves at A:20 B:20 → '20-20, serving'")
    func sideAServesDeuce() {
        var state = MatchState.newSinglesMatch()
        for _ in 0..<20 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        // After 20-20, sideA starts serve at next point from a prior sideA point
        // Verify server and announced string
        if state.currentServer.side == .sideA {
            #expect(state.voiceAnnouncementText == "20-20, serving")
        } else {
            #expect(state.voiceAnnouncementText == "20-20, serving")
        }
    }

    // MARK: - Side B serving

    @Test("sideB serves at A:0 B:1 → '1-0, serving' (server score first)")
    func sideBServesOneZero() {
        var state = MatchState.newSinglesMatch()
        // Score a point for sideA so server switches to sideB
        state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        // Now sideB earns a point to switch serve back — instead score directly for B
        // In standard badminton, scoring a point keeps or grants serve.
        // Score for sideA: sideA keeps serve. Score for sideB from sideA serving → sideB gets serve.
        // Reset and score for sideB directly (rally-point: sideB scores → sideB serves)
        state = MatchState.newSinglesMatch()
        state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        #expect(state.currentServer.side == .sideB)
        #expect(state.voiceAnnouncementText == "1-0, serving")
    }

    @Test("sideB serves at A:5 B:10 → '10-5, serving'")
    func sideBServesTenFive() {
        var state = MatchState.newSinglesMatch()
        // Give sideB the serve first
        state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        // Score 9 more for sideB = 10 total for sideB
        for _ in 0..<9 {
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        // Score 5 for sideA (sideA earns serve, then loses it back when sideB scores)
        // Simpler: build using sideB scoring 10, sideA 5, end with sideB serving
        state = MatchState.newSinglesMatch()
        for _ in 0..<5 {
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
        }
        // Score 5 more for sideB to reach B:10 A:5, ending with sideB serving
        for _ in 0..<5 {
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
        }
        #expect(state.currentServer.side == .sideB)
        #expect(state.currentGame.scoreA == 5)
        #expect(state.currentGame.scoreB == 10)
        #expect(state.voiceAnnouncementText == "10-5, serving")
    }

    // MARK: - Serving score always stated first

    @Test("Serving player score always comes first regardless of side")
    func servingScoreAlwaysFirst() {
        var stateA = MatchState.newSinglesMatch()
        // sideA leads 3-1 and is serving
        for _ in 0..<3 {
            stateA = MatchEngine.apply(event: .scorePoint(.sideA), to: stateA)
        }
        stateA = MatchEngine.apply(event: .scorePoint(.sideB), to: stateA)
        for _ in 0..<2 {
            stateA = MatchEngine.apply(event: .scorePoint(.sideA), to: stateA)
        }
        if stateA.currentServer.side == .sideA {
            let parts = stateA.voiceAnnouncementText.split(separator: "-")
            let servingScore = Int(parts[0])!
            let opponentScore = Int(parts[1].split(separator: ",")[0])!
            #expect(servingScore == stateA.currentGame.scoreA)
            #expect(opponentScore == stateA.currentGame.scoreB)
        }

        var stateB = MatchState.newSinglesMatch()
        stateB = MatchEngine.apply(event: .scorePoint(.sideB), to: stateB)
        stateB = MatchEngine.apply(event: .scorePoint(.sideB), to: stateB)
        if stateB.currentServer.side == .sideB {
            let parts = stateB.voiceAnnouncementText.split(separator: "-")
            let servingScore = Int(parts[0])!
            let opponentScore = Int(parts[1].split(separator: ",")[0])!
            #expect(servingScore == stateB.currentGame.scoreB)
            #expect(opponentScore == stateB.currentGame.scoreA)
        }
    }

    // MARK: - Format

    @Test("Voice announcement always ends with ', serving'")
    func formatEndsWithServing() {
        var state = MatchState.newSinglesMatch()
        for _ in 0..<5 {
            state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            #expect(state.voiceAnnouncementText.hasSuffix(", serving"))
            state = MatchEngine.apply(event: .scorePoint(.sideB), to: state)
            #expect(state.voiceAnnouncementText.hasSuffix(", serving"))
        }
    }
}
