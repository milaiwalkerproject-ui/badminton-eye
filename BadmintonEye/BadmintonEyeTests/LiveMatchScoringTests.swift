// LiveMatchScoringTests.swift
// Unit tests for the assisted-scoring MVP on LiveMatchViewModel:
//   - shouldAutoApplyLastResult() §3.1 state machine (all four branches + the
//     confidence boundary).
//   - resolveRally(for:) provenance for confirm vs human-override.
//   - recordReviewVerdict(...) no-retroactive-mutation guarantee.
//   - GameVideoRecord relationship migration on a POPULATED on-disk store (M3).
//
// Runs via TEST_HOST injection so `@testable import BadmintonEye` exposes the
// view model internals (rallyResultBox, reviewQueue, ReviewItem).

import XCTest
import SwiftData
import ScoringEngine
@testable import BadmintonEye

// MARK: - Test helpers

@MainActor
private enum LiveMatchTestSupport {

    /// Full in-memory SwiftData stack matching the app schema. GameVideoRecord
    /// must be included because PersistedMatch now relates to it.
    static func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([PersistedMatch.self, GameVideoRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    /// A fresh in-progress singles match wired to an in-memory store.
    static func makeViewModel() throws -> LiveMatchViewModel {
        let context = try makeInMemoryContext()
        return LiveMatchViewModel(state: .newSinglesMatch(), modelContext: context)
    }

    /// Builds a `.cvPipeline` RallyResult with the given knobs so individual
    /// §3.1 branches can be exercised in isolation.
    static func cvResult(
        winner: Side = .sideA,
        confidence: Double,
        corroboration: Corroboration = .singleSignal,
        landing: LandingCall? = nil,
        rallyIndex: Int = 0
    ) -> RallyResult {
        RallyResult(
            rallyIndex: rallyIndex,
            winner: winner,
            confidence: confidence,
            source: .cvPipeline,
            corroboration: corroboration,
            landing: landing,
            clipRef: nil,
            positionVote: nil,
            cvVote: SideVote(side: winner, confidence: confidence),
            nextServeVerified: nil
        )
    }

    static func uncertainLanding() -> LandingCall {
        LandingCall(
            point: CourtPoint(x: 0.5, y: 0.5),
            result: .uncertain,
            marginFromLine: 0.005,
            confidence: 0.5
        )
    }
}

// MARK: - shouldAutoApplyLastResult() §3.1 state machine

@MainActor
final class ShouldAutoApplyTests: XCTestCase {

    func test_noResult_doesNotAutoApply() throws {
        let vm = try LiveMatchTestSupport.makeViewModel()
        XCTAssertFalse(vm.shouldAutoApplyLastResult(),
                       "With no produced result there is nothing to auto-apply.")
    }

    func test_humanSource_alwaysAutoApplies_evenAtLowConfidence() throws {
        let vm = try LiveMatchTestSupport.makeViewModel()
        // A human override is authoritative regardless of confidence/conflict.
        let human = RallyResult.humanOverride(rallyIndex: 0, winner: .sideA)
        vm.rallyResultBox.record(human)
        XCTAssertTrue(vm.shouldAutoApplyLastResult(),
                      "source == .human must always auto-apply.")
    }

    func test_conflict_defersToConfirm_evenAtHighConfidence() throws {
        let vm = try LiveMatchTestSupport.makeViewModel()
        // Conflict wins over a high confidence — must confirm, never auto-apply.
        let conflicted = LiveMatchTestSupport.cvResult(
            confidence: 0.99, corroboration: .conflict
        )
        vm.rallyResultBox.record(conflicted)
        XCTAssertFalse(vm.shouldAutoApplyLastResult(),
                       "corroboration == .conflict must defer to a confirm.")
    }

    func test_uncertainLanding_defersToConfirm_evenAtHighConfidence() throws {
        let vm = try LiveMatchTestSupport.makeViewModel()
        // An uncertain landing forces a confirm even with high model confidence.
        let uncertain = LiveMatchTestSupport.cvResult(
            confidence: 0.99,
            corroboration: .singleSignal,
            landing: LiveMatchTestSupport.uncertainLanding()
        )
        vm.rallyResultBox.record(uncertain)
        XCTAssertFalse(vm.shouldAutoApplyLastResult(),
                       "An .uncertain landing must defer to a confirm.")
    }

    func test_confidenceBoundary_justBelowThreshold_confirms() throws {
        let vm = try LiveMatchTestSupport.makeViewModel()
        // 0.91 is below the 0.92 gate → confirm.
        vm.rallyResultBox.record(LiveMatchTestSupport.cvResult(confidence: 0.91))
        XCTAssertFalse(vm.shouldAutoApplyLastResult(),
                       "confidence 0.91 (< 0.92 gate) must confirm.")
    }

    func test_confidenceBoundary_atThreshold_autoApplies() throws {
        let vm = try LiveMatchTestSupport.makeViewModel()
        // 0.92 meets the >= gate → auto-apply.
        vm.rallyResultBox.record(LiveMatchTestSupport.cvResult(confidence: 0.92))
        XCTAssertTrue(vm.shouldAutoApplyLastResult(),
                      "confidence 0.92 (>= 0.92 gate) must auto-apply.")
    }
}

// MARK: - resolveRally(for:) provenance

@MainActor
final class ResolveRallyProvenanceTests: XCTestCase {

    func test_confirm_keepsAutoProvenance() throws {
        let vm = try LiveMatchTestSupport.makeViewModel()
        // Auto call says sideA; the user confirms sideA.
        let produced = LiveMatchTestSupport.cvResult(winner: .sideA, confidence: 0.95)
        vm.rallyResultBox.record(produced)

        vm.resolveRally(for: .sideA)

        let final = try XCTUnwrap(vm.rallyResultBox.latest)
        XCTAssertEqual(final.source, .cvPipeline,
                       "Confirming the auto call must keep the .cvPipeline provenance.")
        XCTAssertEqual(final.winner, .sideA)
        XCTAssertEqual(final.cvVote?.side, .sideA,
                       "The original CV vote must survive a confirm.")
    }

    func test_humanOverride_stampsHumanAndPreservesCvVote() throws {
        let vm = try LiveMatchTestSupport.makeViewModel()
        // Auto call says sideA with high confidence; the user overrides to sideB.
        let produced = LiveMatchTestSupport.cvResult(winner: .sideA, confidence: 0.97)
        vm.rallyResultBox.record(produced)

        vm.resolveRally(for: .sideB)

        let final = try XCTUnwrap(vm.rallyResultBox.latest)
        XCTAssertEqual(final.source, .human,
                       "A human override must stamp source == .human.")
        XCTAssertEqual(final.winner, .sideB,
                       "The override's winner must be the user's choice.")
        // The corrected call is a gold "human ≠ cv" example, so the auto vote
        // must be preserved verbatim.
        XCTAssertEqual(final.cvVote?.side, .sideA,
                       "The original CV vote (sideA) must be preserved on override.")
        XCTAssertEqual(final.cvVote?.confidence ?? 0, 0.97, accuracy: 0.0001,
                       "The original CV vote confidence must be preserved on override.")
    }
}

// MARK: - recordReviewVerdict no-retroactive-mutation guarantee

@MainActor
final class ReviewVerdictNoMutationTests: XCTestCase {

    func test_recordReviewVerdict_leavesScoreAndStateUnchanged() throws {
        let vm = try LiveMatchTestSupport.makeViewModel()

        // Play one rally so there's a non-zero score to protect.
        let produced = LiveMatchTestSupport.cvResult(winner: .sideA, confidence: 0.95)
        vm.rallyResultBox.record(produced)
        vm.resolveRally(for: .sideA)

        let scoreABefore = vm.state.currentGame.scoreA
        let scoreBBefore = vm.state.currentGame.scoreB
        let phaseBefore = vm.state.matchPhase
        XCTAssertEqual(scoreABefore, 1, "Sanity: sideA should have scored once.")

        // A low-confidence CV call gets queued for review.
        let queued = LiveMatchTestSupport.cvResult(
            winner: .sideA, confidence: 0.50, rallyIndex: 1
        )
        let item = LiveMatchViewModel.ReviewItem(result: queued)

        // The user reviews it and disagrees (verdict = sideB). This must write a
        // training label + dequeue, but NEVER touch the live score/state.
        vm.recordReviewVerdict(for: item, winner: .sideB)

        XCTAssertEqual(vm.state.currentGame.scoreA, scoreABefore,
                       "recordReviewVerdict must NOT mutate sideA's score.")
        XCTAssertEqual(vm.state.currentGame.scoreB, scoreBBefore,
                       "recordReviewVerdict must NOT mutate sideB's score.")
        XCTAssertEqual(vm.state.matchPhase, phaseBefore,
                       "recordReviewVerdict must NOT mutate the match phase.")
    }

    func test_recordReviewVerdict_dequeuesTheItem() throws {
        let vm = try LiveMatchTestSupport.makeViewModel()
        // Drive a low-confidence rally through resolution so it lands in the queue.
        let produced = LiveMatchTestSupport.cvResult(winner: .sideA, confidence: 0.50)
        vm.rallyResultBox.record(produced)
        vm.resolveRally(for: .sideA)
        let item = try XCTUnwrap(vm.reviewQueue.first,
                                 "A low-confidence call should be enqueued for review.")

        vm.recordReviewVerdict(for: item, winner: .sideB)

        XCTAssertFalse(vm.reviewQueue.contains { $0.id == item.id },
                       "recordReviewVerdict must dequeue the reviewed item.")
    }
}

// MARK: - M3: GameVideoRecord relationship migration on a populated on-disk store

final class GameVideoMigrationTests: XCTestCase {

    /// Opens an on-disk SwiftData store, writes a PersistedMatch + a related
    /// GameVideoRecord through the `gameVideos` relationship, persists, then
    /// REOPENS a fresh container against the same files to verify the new
    /// relationship migrates without loss or crash. In-memory configs skip the
    /// store-open migration path, so this must hit disk.
    func test_gameVideosRelationship_migratesOnPopulatedOnDiskStore() throws {
        let schema = Schema([PersistedMatch.self, GameVideoRecord.self])
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-\(UUID().uuidString).store")
        defer { Self.removeStoreFiles(at: storeURL) }

        let matchID: UUID
        let recordFileName = "match-game1.mp4"

        // --- Pass 1: write + persist on a real on-disk store. ---
        do {
            let config = ModelConfiguration(url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)

            let match = PersistedMatch()
            match.format = "singles"
            matchID = match.id

            let record = GameVideoRecord(
                gameNumber: 1,
                fileName: recordFileName,
                startedAt: Date(timeIntervalSince1970: 1_000),
                endedAt: Date(timeIntervalSince1970: 1_120),
                rallyCount: 31,
                scoreA: 21,
                scoreB: 10,
                locationName: "Court 3"
            )
            context.insert(match)
            context.insert(record)
            record.match = match
            match.gameVideos = [record]
            try context.save()
        }

        // --- Pass 2: REOPEN a fresh container on the same files. This exercises
        // the real store-open / migration path that an in-memory config skips. ---
        let config = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let matches = try context.fetch(FetchDescriptor<PersistedMatch>())
        XCTAssertEqual(matches.count, 1, "The match must survive reopen.")
        let reloaded = try XCTUnwrap(matches.first)
        XCTAssertEqual(reloaded.id, matchID)

        // The relationship must have migrated with its row intact.
        let videos = try XCTUnwrap(reloaded.gameVideos,
                                   "gameVideos relationship must not be nil after reopen.")
        XCTAssertEqual(videos.count, 1, "The related GameVideoRecord must survive reopen.")
        let video = try XCTUnwrap(videos.first)
        XCTAssertEqual(video.gameNumber, 1)
        XCTAssertEqual(video.fileName, recordFileName)
        XCTAssertEqual(video.scoreA, 21)
        XCTAssertEqual(video.scoreB, 10)
        XCTAssertEqual(video.rallyCount, 31)
        XCTAssertEqual(video.locationName, "Court 3")

        // Inverse must be wired back to the same match after migration.
        XCTAssertEqual(video.match?.id, matchID,
                       "The inverse relationship must point back to the owning match.")

        // The record must also be independently fetchable (no orphaning).
        let allRecords = try context.fetch(FetchDescriptor<GameVideoRecord>())
        XCTAssertEqual(allRecords.count, 1, "The GameVideoRecord row must persist on disk.")
    }

    /// Removes the SwiftData store and its WAL/SHM sidecars.
    private static func removeStoreFiles(at url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let p = URL(fileURLWithPath: url.path + suffix)
            try? fm.removeItem(at: p)
        }
    }
}
