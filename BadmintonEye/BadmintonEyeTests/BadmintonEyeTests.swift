// BadmintonEyeTests.swift
// Unit tests for the BadmintonEye iOS app.
// Runs via TEST_HOST injection so @testable import BadmintonEye exposes internals.
//
// Coverage targets:
//   - ResultFusionService.fuse()  — verifies PR #6 guard path + weighted fusion logic
//   - SyncPayload.from(dictionary:) — verifies defensive decoding (PR #5 safe encoder guard)
//   - PlayerListView.winLossRecords — predicate-filtered query tallies ≡ full scan

import XCTest
import SwiftData
import ScoringEngine
@testable import BadmintonEye

// MARK: - ResultFusionService

final class ResultFusionServiceTests: XCTestCase {

    // MARK: Guard paths (PR #6 regression coverage)

    func testFuseEmptyArrayReturnsNil() {
        // Before PR #6, fuse([]) triggered fatalError. Now it returns nil.
        XCTAssertNil(ResultFusionService.fuse([]),
                     "fuse([]) must return nil — guard replaced fatalError in PR #6")
    }

    func testFuseSingleResultReturnsThatResult() throws {
        let r = makeResult(confidence: 0.75, x: 0.3, y: 0.6)
        let fused = try XCTUnwrap(ResultFusionService.fuse([r]),
                                   "fuse of a single result must return that result")
        XCTAssertEqual(fused.confidence, 0.75, accuracy: 0.001)
        XCTAssertEqual(fused.landingPoint.x, 0.3, accuracy: 0.001)
        XCTAssertEqual(fused.landingPoint.y, 0.6, accuracy: 0.001)
    }

    // MARK: Weighted-average landing point

    func testFuseTwoResultsProducesWeightedLandingPoint() throws {
        // confidence 0.6 and 0.4 → total 1.0
        let r1 = makeResult(confidence: 0.6, x: 0.4, y: 0.3)
        let r2 = makeResult(confidence: 0.4, x: 0.6, y: 0.5)
        let fused = try XCTUnwrap(ResultFusionService.fuse([r1, r2]))
        // Weighted X: 0.4*(0.6/1.0) + 0.6*(0.4/1.0) = 0.48
        XCTAssertEqual(fused.landingPoint.x, 0.48, accuracy: 0.001)
        // Weighted Y: 0.3*(0.6/1.0) + 0.5*(0.4/1.0) = 0.38
        XCTAssertEqual(fused.landingPoint.y, 0.38, accuracy: 0.001)
    }

    // MARK: Confidence boost and cap

    func testFusedConfidenceIsCapAt99Percent() throws {
        let r1 = makeResult(confidence: 0.95)
        let r2 = makeResult(confidence: 0.90)
        let fused = try XCTUnwrap(ResultFusionService.fuse([r1, r2]))
        XCTAssertLessThanOrEqual(fused.confidence, 0.99,
                                  "fused confidence must be capped at 0.99")
    }

    func testFusedConfidenceExceedsMaxInput() throws {
        let r1 = makeResult(confidence: 0.60)
        let r2 = makeResult(confidence: 0.55)
        let fused = try XCTUnwrap(ResultFusionService.fuse([r1, r2]))
        // 15% boost: max(0.60) * 1.15 = 0.69
        XCTAssertGreaterThan(fused.confidence, 0.60,
                              "multi-angle fusion should boost confidence above the max input")
    }

    // MARK: Trajectory merge

    func testFusedTrajectoryMergesAllAngles() throws {
        let pt1 = CourtPoint(x: 0.1, y: 0.2)
        let pt2 = CourtPoint(x: 0.5, y: 0.6)
        let r1 = HawkEyeResult(
            trajectoryPoints: [pt1],
            landingPoint: CourtPoint(x: 0.5, y: 0.5),
            landingResult: .inBounds, confidence: 0.8, marginFromLine: 0.1)
        let r2 = HawkEyeResult(
            trajectoryPoints: [pt2],
            landingPoint: CourtPoint(x: 0.5, y: 0.5),
            landingResult: .inBounds, confidence: 0.7, marginFromLine: 0.1)
        let fused = try XCTUnwrap(ResultFusionService.fuse([r1, r2]))
        XCTAssertEqual(fused.trajectoryPoints.count, 2,
                        "trajectory points from all angles should be merged")
    }

    // MARK: - Helpers

    private func makeResult(
        confidence: Double,
        x: Double = 0.5,
        y: Double = 0.5,
        landing: LandingResult = .inBounds
    ) -> HawkEyeResult {
        HawkEyeResult(
            trajectoryPoints: [],
            landingPoint: CourtPoint(x: x, y: y),
            landingResult: landing,
            confidence: confidence,
            marginFromLine: 0.05
        )
    }
}

// MARK: - SyncPayload

final class SyncPayloadTests: XCTestCase {

    func testFromEmptyDictionaryReturnsNil() {
        XCTAssertNil(SyncPayload.from(dictionary: [:]),
                      "SyncPayload.from must return nil for an empty dictionary")
    }

    func testFromDictionaryWithWrongTypeReturnsNil() {
        // "syncPayload" key exists but value is a String, not Data
        XCTAssertNil(SyncPayload.from(dictionary: ["syncPayload": "not-data"]),
                      "SyncPayload.from must return nil when syncPayload value is not Data")
    }

    func testFromDictionaryWithCorruptDataReturnsNil() {
        let garbage = Data([0xFF, 0xFE, 0x00])
        XCTAssertNil(SyncPayload.from(dictionary: ["syncPayload": garbage]),
                      "SyncPayload.from must return nil for corrupt JSON data")
    }
}

// MARK: - PlayerListView win/loss tally predicate equivalence

@MainActor
final class PlayerRecordsPredicateTests: XCTestCase {

    /// The Players tab now fetches only `isComplete && winnerSide != nil`
    /// rows instead of materializing every match. This pins the invariant
    /// that the store-level predicate yields EXACTLY the same win/loss
    /// tallies as a full scan of all matches.
    func testPredicateFilteredTalliesMatchFullScan() throws {
        let schema = Schema([PersistedMatch.self, GameVideoRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        func insertMatch(
            _ format: String, complete: Bool, winner: String?,
            a: String? = nil, a2: String? = nil,
            b: String? = nil, b2: String? = nil
        ) {
            let m = PersistedMatch()
            m.format = format
            m.isComplete = complete
            m.winnerSide = winner
            m.playerAName = a
            m.playerA2Name = a2
            m.playerBName = b
            m.playerB2Name = b2
            context.insert(m)
        }

        // Rows that MUST count toward tallies.
        insertMatch("singles", complete: true, winner: "sideA", a: "Alice", b: "Bob")
        insertMatch("singles", complete: true, winner: "sideB", a: "Alice", b: "Bob")
        insertMatch("doubles", complete: true, winner: "sideA",
                    a: "Alice", a2: "Cara", b: "Bob", b2: "Dan")
        // Rows that MUST NOT count (and must not change the tallies).
        insertMatch("singles", complete: false, winner: nil, a: "Alice", b: "Bob")     // in progress
        insertMatch("singles", complete: true, winner: nil, a: "Alice", b: "Bob")      // completed, never decided
        insertMatch("singles", complete: false, winner: "sideA", a: "Alice", b: "Bob") // inconsistent row
        try context.save()

        let all = try context.fetch(FetchDescriptor<PersistedMatch>())
        let filtered = try context.fetch(FetchDescriptor<PersistedMatch>(
            predicate: #Predicate { $0.isComplete && $0.winnerSide != nil }
        ))

        XCTAssertEqual(all.count, 6)
        XCTAssertEqual(filtered.count, 3,
                       "Predicate must exclude in-progress and undecided rows")

        let fromFiltered = PlayerListView.winLossRecords(from: filtered)
        let fromAll = PlayerListView.winLossRecords(from: all)
        XCTAssertEqual(fromFiltered, fromAll,
                       "Store-level predicate must not change the tallies")

        XCTAssertEqual(fromFiltered["Alice"], PlayerListView.WinLoss(wins: 2, losses: 1))
        XCTAssertEqual(fromFiltered["Bob"], PlayerListView.WinLoss(wins: 1, losses: 2))
        XCTAssertEqual(fromFiltered["Cara"], PlayerListView.WinLoss(wins: 1, losses: 0))
        XCTAssertEqual(fromFiltered["Dan"], PlayerListView.WinLoss(wins: 0, losses: 1))
    }
}

// MARK: - Recent Opponents derivation (placeholder filtering)

final class RecentOpponentsTests: XCTestCase {

    func testPlaceholderNamesAreExcluded() {
        // A singles match started without typed names persists the
        // ScoringEngine defaults "Player 1"/"Player 2"; doubles persists
        // "Player A1"… — none of these are real opponents.
        let recents = PlayerPickerView.recentOpponents(
            fromMatchNameLists: [
                ["Player 1", "Player 2"],
                ["Player A1", "Player A2", "Player B1", "Player B2"],
                ["Alice", "Bob"],
            ],
            excluding: []
        )
        XCTAssertEqual(recents, ["Alice", "Bob"],
                       "Placeholder defaults must never surface as recent opponents")
    }

    func testAllPlaceholderMatchesYieldEmptyRecents() {
        let recents = PlayerPickerView.recentOpponents(
            fromMatchNameLists: [["Player 1", "Player 2"], ["Side A", "Side B"]],
            excluding: []
        )
        XCTAssertTrue(recents.isEmpty,
                      "Matches with only placeholder names must produce no chips")
    }

    func testExcludedAndDuplicateNamesAreDropped() {
        let recents = PlayerPickerView.recentOpponents(
            fromMatchNameLists: [
                ["Alice", "Bob"],
                ["Bob", "Cara"],   // Bob deduplicated
                ["Dan", "Alice"],  // Alice deduplicated
            ],
            excluding: ["Alice"]   // already selected in the other slot
        )
        XCTAssertEqual(recents, ["Bob", "Cara", "Dan"])
    }

    func testRecencyOrderAndLimit() {
        let recents = PlayerPickerView.recentOpponents(
            fromMatchNameLists: [
                ["A", "B"], ["C", "D"], ["E", "F"], ["G", "H"],
            ],
            excluding: []
        )
        XCTAssertEqual(recents, ["A", "B", "C", "D", "E"],
                       "Most recent matches first, capped at 5 chips")
    }

    func testEmptyNamesAreIgnored() {
        let recents = PlayerPickerView.recentOpponents(
            fromMatchNameLists: [["", "Alice"]],
            excluding: []
        )
        XCTAssertEqual(recents, ["Alice"])
    }
}

// MARK: - Launch resume detection

final class MatchResumeServiceTests: XCTestCase {

    /// Crash-recovery JSON for a match in the given phase.
    private func stateJSON(complete: Bool) throws -> Data {
        var state = MatchState.newSinglesMatch(
            teamAName: "Alice", teamBName: "Bob", scoringSystem: .standard21
        )
        if complete {
            // Run side A to 21-0 so the engine marks the match complete.
            for _ in 0..<21 {
                state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            }
            // 21-0 wins game 1; for best-of-3 we need two games.
            for _ in 0..<21 {
                state = MatchEngine.apply(event: .scorePoint(.sideA), to: state)
            }
        }
        return try JSONEncoder().encode(CodableMatchState(from: state))
    }

    func testInProgressMatchIsResumable() throws {
        let json = try stateJSON(complete: false)
        XCTAssertTrue(MatchResumeService.isResumable(
            isComplete: false, isAbandoned: false, stateJSON: json
        ), "A leftover in-progress match must be offered for resume")
    }

    func testCompleteFlagBlocksResume() throws {
        let json = try stateJSON(complete: false)
        XCTAssertFalse(MatchResumeService.isResumable(
            isComplete: true, isAbandoned: false, stateJSON: json
        ))
    }

    func testAbandonedFlagBlocksResume() throws {
        let json = try stateJSON(complete: false)
        XCTAssertFalse(MatchResumeService.isResumable(
            isComplete: false, isAbandoned: true, stateJSON: json
        ))
    }

    func testMissingStateJSONBlocksResume() {
        XCTAssertFalse(MatchResumeService.isResumable(
            isComplete: false, isAbandoned: false, stateJSON: nil
        ), "No crash-recovery state → nothing to resume")
    }

    func testCorruptStateJSONBlocksResume() {
        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertFalse(MatchResumeService.isResumable(
            isComplete: false, isAbandoned: false, stateJSON: garbage
        ), "Undecodable state must be finalized as abandoned, not resumed")
    }

    func testCompletedPhaseInJSONBlocksResume() throws {
        // Flags say in-progress but the serialized state already reached a
        // terminal phase — the JSON is authoritative.
        let json = try stateJSON(complete: true)
        XCTAssertFalse(MatchResumeService.isResumable(
            isComplete: false, isAbandoned: false, stateJSON: json
        ))
    }
}
