// ClipRefTests.swift
// Unit tests for the highlight clip (ClipRef) trim in/out clamping/validation
// and for ClipRef persistence on GameVideoRecord (in-memory + on-disk reopen).
//
// `ClipRef` is the existing time-range contract { fileName, startTime, endTime }
// in Services/RallyResult.swift; the highlight editor reuses it (no separate
// clip files). The trim clamping lives in the GameVideoRecord extension.

import XCTest
import SwiftData
@testable import BadmintonEye

private let kFile = "match-game1.mp4"

// MARK: - Trim in/out clamping & validation

final class ClipRefClampingTests: XCTestCase {

    // A normal in-bounds request is returned unchanged.
    func test_clamped_inBoundsRange_isUnchanged() {
        let clip = ClipRef.clamped(fileName: kFile, start: 2, end: 8, duration: 10)
        XCTAssertEqual(clip?.startTime, 2)
        XCTAssertEqual(clip?.endTime, 8)
        XCTAssertEqual(clip?.duration, 6)
        XCTAssertEqual(clip?.fileName, kFile)
    }

    // Start below zero clamps up to zero.
    func test_clamped_negativeStart_clampsToZero() {
        let clip = ClipRef.clamped(fileName: kFile, start: -5, end: 4, duration: 10)
        XCTAssertEqual(clip?.startTime, 0)
        XCTAssertEqual(clip?.endTime, 4)
    }

    // End beyond duration clamps down to duration.
    func test_clamped_endBeyondDuration_clampsToDuration() {
        let clip = ClipRef.clamped(fileName: kFile, start: 3, end: 99, duration: 10)
        XCTAssertEqual(clip?.startTime, 3)
        XCTAssertEqual(clip?.endTime, 10)
    }

    // Inverted range (end <= start) is corrected to at least the minimum length.
    func test_clamped_invertedRange_isCorrectedToMinimum() {
        let clip = ClipRef.clamped(fileName: kFile, start: 6, end: 4, duration: 10)
        XCTAssertNotNil(clip)
        XCTAssertEqual(clip!.startTime, 6, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(clip!.duration, ClipRef.minimumDuration - 0.0001)
    }

    // Equal start/end is widened to at least the minimum length.
    func test_clamped_zeroLength_isWidenedToMinimum() {
        let clip = ClipRef.clamped(fileName: kFile, start: 5, end: 5, duration: 10)
        XCTAssertNotNil(clip)
        XCTAssertGreaterThanOrEqual(clip!.duration, ClipRef.minimumDuration - 0.0001)
    }

    // Start near the very end is walked back so a minimum clip still fits.
    func test_clamped_startNearEnd_walksStartBackToFitMinimum() {
        let clip = ClipRef.clamped(fileName: kFile, start: 9.9, end: 10, duration: 10)
        XCTAssertNotNil(clip)
        XCTAssertLessThanOrEqual(clip!.endTime, 10.0001)
        XCTAssertGreaterThanOrEqual(clip!.duration, ClipRef.minimumDuration - 0.0001)
    }

    // A video shorter than the minimum clip length cannot produce a clip.
    func test_clamped_durationShorterThanMinimum_returnsNil() {
        let clip = ClipRef.clamped(fileName: kFile, start: 0, end: 0.2, duration: 0.3)
        XCTAssertNil(clip)
    }

    // Unknown duration (nil): start has no upper bound, end >= start + min.
    func test_clamped_unknownDuration_allowsOpenEnded() {
        let clip = ClipRef.clamped(fileName: kFile, start: 100, end: 105, duration: nil)
        XCTAssertEqual(clip?.startTime, 100)
        XCTAssertEqual(clip?.endTime, 105)
    }

    // NaN inputs are sanitized rather than producing a NaN clip.
    func test_clamped_nanInputs_areSanitized() {
        let clip = ClipRef.clamped(fileName: kFile, start: .nan, end: .nan, duration: 10)
        XCTAssertNotNil(clip)
        XCTAssertTrue(clip!.startTime.isFinite)
        XCTAssertTrue(clip!.endTime.isFinite)
        XCTAssertGreaterThan(clip!.duration, 0)
    }

    // Non-finite duration is rejected.
    func test_clamped_infiniteDuration_returnsNil() {
        XCTAssertNil(ClipRef.clamped(fileName: kFile, start: 0, end: 5, duration: .infinity))
    }
}

// MARK: - ClipRef persistence on GameVideoRecord (round-trip in memory)

@MainActor
final class ClipRefPersistenceTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([PersistedMatch.self, GameVideoRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    func test_setClip_thenClipRef_roundTrips() throws {
        let context = try makeContext()
        let rec = GameVideoRecord(
            gameNumber: 1, fileName: kFile,
            startedAt: Date(), endedAt: Date().addingTimeInterval(120),
            rallyCount: 10, scoreA: 21, scoreB: 15, locationName: nil
        )
        context.insert(rec)

        let clip = ClipRef(fileName: kFile, startTime: 3.5, endTime: 12.0)
        rec.setClip(clip)
        try context.save()

        let reread = try XCTUnwrap(rec.clipRef)
        XCTAssertEqual(reread.startTime, 3.5)
        XCTAssertEqual(reread.endTime, 12.0)
        XCTAssertEqual(reread.fileName, kFile)
    }

    func test_noClip_clipRefIsNil() throws {
        let context = try makeContext()
        let rec = GameVideoRecord(
            gameNumber: 1, fileName: kFile,
            startedAt: Date(), endedAt: nil,
            rallyCount: 0, scoreA: 0, scoreB: 0, locationName: nil
        )
        context.insert(rec)
        XCTAssertNil(rec.clipRef)
    }

    func test_setClipNil_clearsPersistedFields() throws {
        let context = try makeContext()
        let rec = GameVideoRecord(
            gameNumber: 1, fileName: kFile,
            startedAt: Date(), endedAt: nil,
            rallyCount: 0, scoreA: 0, scoreB: 0, locationName: nil
        )
        context.insert(rec)
        rec.setClip(ClipRef(fileName: kFile, startTime: 1, endTime: 5))
        rec.setClip(nil)
        try context.save()
        XCTAssertNil(rec.clipRef)
        XCTAssertNil(rec.clipStartTime)
        XCTAssertNil(rec.clipEndTime)
    }

    // Inconsistent persisted values (end <= start) surface as no clip.
    func test_inconsistentStoredRange_clipRefIsNil() throws {
        let context = try makeContext()
        let rec = GameVideoRecord(
            gameNumber: 1, fileName: kFile,
            startedAt: Date(), endedAt: nil,
            rallyCount: 0, scoreA: 0, scoreB: 0, locationName: nil
        )
        context.insert(rec)
        rec.clipStartTime = 8
        rec.clipEndTime = 4
        XCTAssertNil(rec.clipRef)
    }

    // Empty fileName means there's no real video, so no clip.
    func test_emptyFileName_clipRefIsNil() throws {
        let context = try makeContext()
        let rec = GameVideoRecord(
            gameNumber: 1, fileName: "",
            startedAt: Date(), endedAt: nil,
            rallyCount: 0, scoreA: 0, scoreB: 0, locationName: nil
        )
        context.insert(rec)
        rec.clipStartTime = 1
        rec.clipEndTime = 5
        XCTAssertNil(rec.clipRef)
    }
}

// MARK: - ClipRef migration on a populated on-disk store

final class ClipRefMigrationTests: XCTestCase {

    /// Writes a GameVideoRecord WITH a saved clip to a real on-disk store, then
    /// reopens a fresh container against the same files to confirm the new clip
    /// columns migrate additively without loss. In-memory configs skip the
    /// store-open migration path, so this must hit disk.
    func test_clipRef_migratesOnPopulatedOnDiskStore() throws {
        let schema = Schema([PersistedMatch.self, GameVideoRecord.self])
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipref-migration-\(UUID().uuidString).store")
        defer { Self.removeStoreFiles(at: storeURL) }

        let recordID: UUID
        let fileName = "match-game2.mp4"

        // Pass 1: write a record with a clip on disk.
        do {
            let config = ModelConfiguration(url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)

            let match = PersistedMatch()
            let record = GameVideoRecord(
                gameNumber: 2, fileName: fileName,
                startedAt: Date(timeIntervalSince1970: 2_000),
                endedAt: Date(timeIntervalSince1970: 2_180),
                rallyCount: 18, scoreA: 21, scoreB: 19, locationName: "Court 1"
            )
            recordID = record.id
            record.setClip(ClipRef(fileName: fileName, startTime: 5.25, endTime: 18.75))

            context.insert(match)
            context.insert(record)
            record.match = match
            match.gameVideos = [record]
            try context.save()
        }

        // Pass 2: reopen and verify the clip survived migration.
        let config = ModelConfiguration(url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let records = try context.fetch(FetchDescriptor<GameVideoRecord>())
        XCTAssertEqual(records.count, 1)
        let reloaded = try XCTUnwrap(records.first { $0.id == recordID })

        let clip = try XCTUnwrap(reloaded.clipRef,
                                 "ClipRef must survive store reopen / migration.")
        XCTAssertEqual(clip.startTime, 5.25, accuracy: 0.0001)
        XCTAssertEqual(clip.endTime, 18.75, accuracy: 0.0001)
        XCTAssertEqual(clip.fileName, fileName)
    }

    private static func removeStoreFiles(at url: URL) {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let p = URL(fileURLWithPath: url.path + suffix)
            try? fm.removeItem(at: p)
        }
    }
}
