// RallyLabelTests.swift
// Pins for wave 1 Phase 1: the RallyLabel model (upsert semantics, additive
// migration) and RallyLabelExport (queue folding + the exact python contract
// for annotations_human_holdout.jsonl / orientation.json).

import XCTest
import SwiftData
import ScoringEngine
@testable import BadmintonEye

@MainActor
final class RallyLabelTests: XCTestCase {

    // MARK: - Export line format (the python flywheel contract)

    private func decodeLine(_ line: String) throws -> [String: Any] {
        let obj = try JSONSerialization.jsonObject(with: Data(line.utf8))
        return try XCTUnwrap(obj as? [String: Any])
    }

    func testHoldoutLineWinnerRow() throws {
        let line = try XCTUnwrap(RallyLabelExport.holdoutLine(
            videoStem: "ABC-game1", rallyID: 3, verdict: .sideA,
            orientation: .endOn, timestamp: Date(timeIntervalSince1970: 0)))
        let rec = try decodeLine(line)

        XCTAssertEqual(rec["video"] as? String, "ABC-game1")
        XCTAssertEqual(rec["winner"] as? String, "sideA")
        XCTAssertEqual(rec["annotator"] as? String, "in_app")
        XCTAssertEqual(rec["split"] as? String, "holdout")
        XCTAssertEqual(rec["orientation"] as? String, "end_on")
        XCTAssertNil(rec["not_rally"], "winner rows must not carry not_rally")
        // rally_id MUST be a JSON number — hit_attribution_eval joins with raw
        // == against int rally ids and does not cast.
        let rallyID = try XCTUnwrap(rec["rally_id"] as? NSNumber)
        XCTAssertEqual(rallyID.intValue, 3)
        let ts = try XCTUnwrap(rec["timestamp"] as? String)
        XCTAssertTrue(ts.hasSuffix("Z"))
    }

    func testHoldoutLineNotRallyRowCarriesAllThreeMarkers() throws {
        let line = try XCTUnwrap(RallyLabelExport.holdoutLine(
            videoStem: "ABC-game1", rallyID: 4, verdict: .notRally,
            orientation: .sideOn, timestamp: Date(timeIntervalSince1970: 0)))
        let rec = try decodeLine(line)
        // Readers accept any one of the three markers; the writer sets all three.
        XCTAssertEqual(rec["winner"] as? String, "not_rally")
        XCTAssertEqual(rec["split"] as? String, "not_rally")
        XCTAssertEqual(rec["not_rally"] as? Bool, true)
    }

    func testHoldoutLineOmitsUnknownOrientationAndRejectsEmptyStem() throws {
        let line = try XCTUnwrap(RallyLabelExport.holdoutLine(
            videoStem: "V", rallyID: 0, verdict: .sideB,
            orientation: nil, timestamp: Date(timeIntervalSince1970: 0)))
        let rec = try decodeLine(line)
        XCTAssertNil(rec["orientation"], "absent orientation means side_on downstream")
        XCTAssertEqual(rec["winner"] as? String, "sideB")

        XCTAssertNil(RallyLabelExport.holdoutLine(
            videoStem: "", rallyID: 0, verdict: .sideA,
            orientation: nil, timestamp: Date()))
    }

    func testHoldoutFileContentSortsAndTerminates() {
        let content = RallyLabelExport.holdoutFileContent([
            (videoStem: "B-game1", rallyID: 0, verdict: .sideA, orientation: nil,
             labeledAt: Date(timeIntervalSince1970: 0)),
            (videoStem: "A-game1", rallyID: 1, verdict: .sideB, orientation: nil,
             labeledAt: Date(timeIntervalSince1970: 0)),
            (videoStem: "A-game1", rallyID: 0, verdict: .sideB, orientation: nil,
             labeledAt: Date(timeIntervalSince1970: 0)),
        ])
        let lines = content.split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(content.hasSuffix("\n"), "file must end with a newline")
        XCTAssertTrue(lines[0].contains("\"A-game1\"") && lines[0].contains("\"rally_id\":0"))
        XCTAssertTrue(lines[1].contains("\"A-game1\"") && lines[1].contains("\"rally_id\":1"))
        XCTAssertTrue(lines[2].contains("\"B-game1\""))
        XCTAssertEqual(RallyLabelExport.holdoutFileContent([]), "")
    }

    func testOrientationFileContent() throws {
        let text = try XCTUnwrap(RallyLabelExport.orientationFileContent(
            ["IMG_1": .endOn, "IMG_2": .sideOn]))
        let obj = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: String])
        XCTAssertEqual(obj, ["IMG_1": "end_on", "IMG_2": "side_on"])
    }

    // MARK: - Work-queue folding from TrainingExport JSONL

    private func jsonl(_ results: [RallyResult]) throws -> Data {
        let encoder = JSONEncoder()
        var data = Data()
        for r in results {
            data.append(try encoder.encode(r))
            data.append(0x0A)
        }
        return data
    }

    private func result(index: Int, fileName: String?, winner: Side = .sideA,
                        start: Double = 10, end: Double = 18) -> RallyResult {
        RallyResult.humanOverride(
            rallyIndex: index, winner: winner,
            clipRef: fileName.map { ClipRef(fileName: $0, startTime: start, endTime: end) })
    }

    func testQueueItemsFoldLatestLineAndFilterByFileName() throws {
        let data = try jsonl([
            result(index: 0, fileName: "M-game1.mp4", start: 5, end: 9),
            result(index: 1, fileName: "M-game1.mp4", start: 20, end: 26),
            result(index: 0, fileName: "M-game1.mp4", start: 6, end: 10),  // override: latest wins
            result(index: 2, fileName: "M-game2.mp4"),                     // other game video
            result(index: 3, fileName: nil),                               // no clip → unlabelable
        ])
        let items = RallyLabelExport.queueItems(jsonlData: data, fileName: "M-game1.mp4")
        XCTAssertEqual(items.map(\.rallyID), [0, 1])
        XCTAssertEqual(items[0].startTime, 6, accuracy: 1e-9)   // folded to the later line
        XCTAssertEqual(items[0].endTime, 10, accuracy: 1e-9)
    }

    func testQueueItemsTolerateMalformedLines() {
        let data = Data("not json\n{\"also\": \"wrong shape\"}\n".utf8)
        XCTAssertTrue(RallyLabelExport.queueItems(jsonlData: data, fileName: "x.mp4").isEmpty)
    }

    // MARK: - Upsert semantics (in-memory SwiftData)

    private func makeContext() throws -> ModelContext {
        let schema = Schema([RallyLabel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    func testUpsertInsertsThenOverwritesSameKey() throws {
        let context = try makeContext()
        RallyLabel.upsert(videoStem: "V-game1", rallyID: 7, verdict: .sideA,
                          orientation: .sideOn, in: context)
        RallyLabel.upsert(videoStem: "V-game1", rallyID: 7, verdict: .sideB,
                          orientation: .sideOn, in: context)
        RallyLabel.upsert(videoStem: "V-game1", rallyID: 8, verdict: .notRally,
                          orientation: .sideOn, in: context)

        let all = try context.fetch(FetchDescriptor<RallyLabel>(
            sortBy: [SortDescriptor(\.rallyID)]))
        XCTAssertEqual(all.count, 2, "same (stem, rallyID) must update, not duplicate")
        XCTAssertEqual(all[0].verdict, .sideB)
        XCTAssertEqual(all[1].verdict, .notRally)
    }

    func testUpsertRefusesEmptyStem() throws {
        let context = try makeContext()
        RallyLabel.upsert(videoStem: "", rallyID: 0, verdict: .sideA,
                          orientation: nil, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<RallyLabel>()).count, 0)
    }

    // MARK: - Additive migration (real on-disk store reopen)

    func testAddingRallyLabelToExistingStoreIsAdditive() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RallyLabelMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("store.sqlite")

        // Pass 1: write with the OLD schema (no RallyLabel).
        do {
            let schema = Schema([PersistedMatch.self, GameVideoRecord.self])
            let container = try ModelContainer(
                for: schema, configurations: [ModelConfiguration(url: storeURL)])
            let context = ModelContext(container)
            let record = GameVideoRecord()
            record.fileName = "M-game1.mp4"
            context.insert(record)
            try context.save()
        }

        // Pass 2: REOPEN the same files with the NEW schema including
        // RallyLabel + the orientationRaw addition — the real migration path.
        let schema = Schema([PersistedMatch.self, GameVideoRecord.self, RallyLabel.self])
        let container = try ModelContainer(
            for: schema, configurations: [ModelConfiguration(url: storeURL)])
        let context = ModelContext(container)

        let videos = try context.fetch(FetchDescriptor<GameVideoRecord>())
        XCTAssertEqual(videos.count, 1)
        XCTAssertNil(videos[0].orientationRaw, "pre-existing rows get nil orientation")
        XCTAssertEqual(videos[0].videoStem, "M-game1")

        RallyLabel.upsert(videoStem: videos[0].videoStem, rallyID: 0,
                          verdict: .sideA, orientation: .endOn, in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<RallyLabel>()).count, 1)
    }
}
