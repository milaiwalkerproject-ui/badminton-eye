import Foundation
import ScoringEngine

// MARK: - Per-Rally Result Data Contract (v0.1)
//
// The seam between the scoring brain (Vision: position scorer + CV pipeline)
// and the app (AppDev: score state machine, persistence, UI).
//
// Design rules (see agents/Vision/output/RESULT-DATA-CONTRACT.md):
//   1. No single signal is gold — carry WHO said what + WHETHER they agree.
//   2. Store landing COORDINATES (CourtPoint), never a bare in/out.
//   3. `source` + `corroboration` are first-class (UI trust cues + training eligibility).
//   4. Backward compatible — projects down to the existing RallySuggestion.
//
// `CourtPoint` / `LandingResult` live in the app target (TrajectoryCalculator.swift),
// so `RallyResult` lives here in the app target too — NOT in the ScoringEngine package.

// NOTE: `CourtPoint` and `LandingResult` conform to Codable/Sendable/Equatable
// in their declaring file (TrajectoryCalculator.swift) — Swift requires those
// conformances there, not via a retroactive extension here.

// MARK: - Provenance enums

/// Which signal produced a winner call.
enum ResultSource: String, Codable, Sendable, Equatable {
    case positionScorer   // System 1: inferred from serve-court positions (BWF serve rule)
    case cvPipeline       // System 2: shot-by-shot detector → trajectory → landing
    case fused            // both agreed and were combined
    case human            // user override / manual tap (always authoritative)
}

/// Did independent signals agree on the winner?
enum Corroboration: String, Codable, Sendable, Equatable {
    case corroborated     // ≥2 independent signals agree → training-grade eligible
    case singleSignal     // only one signal had an opinion (other abstained/low-conf)
    case conflict         // signals disagreed → DO NOT train; surface for review
    case unverified       // not yet checked against the next-serve oracle
}

// MARK: - Evidence structs

/// A pointer to a rally clip as a time-range into an existing per-game video file.
/// Matches `GameVideoRecord.fileName`; no separate clip files are written.
struct ClipRef: Codable, Sendable, Equatable {
    let fileName: String          // the game-video file in Footage/ (matches GameVideoRecord.fileName)
    let startTime: TimeInterval   // seconds from the start of that game video
    let endTime: TimeInterval
}

/// One close-call landing, in court space. Mirrors HawkEyeResult's landing fields.
struct LandingCall: Codable, Sendable, Equatable {
    let point: CourtPoint            // normalized court coords (0…1), NOT a bare in/out
    let result: LandingResult        // .inBounds / .outOfBounds / .uncertain (derived)
    let marginFromLine: Double       // court-normalized distance to nearest line
    let confidence: Double           // 0…1, this landing's own confidence
}

/// One scorer's opinion, kept separate so disagreements stay inspectable.
struct SideVote: Codable, Sendable, Equatable {
    let side: Side
    let confidence: Double           // 0…1
}

// MARK: - The contract

/// The per-rally result AppDev consumes to advance the score state machine.
struct RallyResult: Codable, Sendable, Equatable {
    let rallyIndex: Int                  // 0-based, monotonic within a game
    let winner: Side                     // the consumed verdict (sideA/sideB)
    let confidence: Double               // 0…1, overall confidence in `winner`
    let source: ResultSource             // which scorer produced `winner`
    let corroboration: Corroboration     // agreement status across signals

    // evidence (optional; present when CV ran)
    let landing: LandingCall?            // close-call landing, if a CV landing was computed
    let clipRef: ClipRef?                // time-range into the per-game video (training + replay)

    // per-signal breakdown (UI trust cues + disagreement triage)
    let positionVote: SideVote?          // System 1's opinion (nil if it abstained)
    let cvVote: SideVote?                // System 2's opinion (nil if it abstained)
    let nextServeVerified: Bool?         // next-serve oracle agreement; nil until next serve seen
}

extension RallyResult {
    /// Lets any existing `RallySuggesting` caller consume the new result unchanged.
    var asSuggestion: RallySuggestion { RallySuggestion(side: winner, confidence: confidence) }

    /// Adapter for the MVP path: lift the EXISTING geometric `TrajectoryRallySuggestor`'s
    /// `RallySuggestion` into a `RallyResult` with the correct contract semantics.
    /// Use this until the trained classifier is bundled on-device (the scope-gated build).
    /// `source = .cvPipeline`, `corroboration = .singleSignal` (only the suggestor opined),
    /// `positionVote = nil` (System 1 deferred), `nextServeVerified = nil` (oracle unavailable).
    static func fromSuggestion(
        rallyIndex: Int,
        suggestion: RallySuggestion,
        clipRef: ClipRef? = nil,
        landing: LandingCall? = nil
    ) -> RallyResult {
        RallyResult(
            rallyIndex: rallyIndex,
            winner: suggestion.side,
            confidence: suggestion.confidence,
            source: .cvPipeline,
            corroboration: .singleSignal,
            landing: landing,
            clipRef: clipRef,
            positionVote: nil,
            cvVote: SideVote(side: suggestion.side, confidence: suggestion.confidence),
            nextServeVerified: nil
        )
    }

    /// Convenience for the human-override path: AppDev's manual tap / override.
    /// Produces an authoritative result and preserves what the auto-scorers said
    /// (so a *corrected* call becomes high-value training signal).
    static func humanOverride(
        rallyIndex: Int,
        winner: Side,
        clipRef: ClipRef? = nil,
        landing: LandingCall? = nil,
        positionVote: SideVote? = nil,
        cvVote: SideVote? = nil
    ) -> RallyResult {
        RallyResult(
            rallyIndex: rallyIndex,
            winner: winner,
            confidence: 1.0,
            source: .human,
            corroboration: .corroborated,   // human is authoritative → training-grade
            landing: landing,
            clipRef: clipRef,
            positionVote: positionVote,
            cvVote: cvVote,
            nextServeVerified: nil
        )
    }
}
