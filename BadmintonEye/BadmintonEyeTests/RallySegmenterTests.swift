// RallySegmenterTests.swift
// Parity pins for the python detect_rallies port (extract_rallies.py:91-124).
// The inclusive/exclusive edges are the contract: gap STRICTLY > 1.0 s splits,
// duration >= 1.5 s keeps, rally ids are assigned after the duration filter.

import XCTest
@testable import BadmintonEye

final class RallySegmenterTests: XCTestCase {

    private func det(_ f: Int, vis: Bool = true, conf: Double = 0.9) -> AnalyzedDetection {
        AnalyzedDetection(f: f, x: 0.5, y: 0.5, conf: conf, vis: vis)
    }

    /// A visible run of frames [start, start+count) at canonical 30 fps.
    private func run(_ start: Int, count: Int) -> [AnalyzedDetection] {
        (0..<count).map { det(start + $0) }
    }

    func testGapOfExactlyOneSecondStaysInRally() {
        // 30 frames apart at 30 fps = exactly 1.0 s: NOT a boundary
        // (python: `gap_s > GAP_BOUNDARY_S`, strictly greater).
        let dets = [det(0)] + run(30, count: 60)
        let rallies = RallySegmenter.detectRallies(dets)
        XCTAssertEqual(rallies.count, 1)
        XCTAssertEqual(rallies[0].startFrame, 0)
        XCTAssertEqual(rallies[0].endFrame, 89)
    }

    func testGapOverOneSecondSplits() {
        // 31 frames apart = ~1.033 s: boundary.
        let dets = run(0, count: 60) + run(90, count: 60)
        let rallies = RallySegmenter.detectRallies(dets)
        XCTAssertEqual(rallies.count, 2)
        XCTAssertEqual(rallies[0].endFrame, 59)
        XCTAssertEqual(rallies[1].startFrame, 90)
    }

    func testDurationOfExactly1Point5SecondsIsKept() {
        // first→last span 45 frames = exactly 1.5 s: kept (python `>=`).
        let rallies = RallySegmenter.detectRallies(run(0, count: 46))
        XCTAssertEqual(rallies.count, 1)
        XCTAssertEqual(rallies[0].endFrame, 45)
    }

    func testShortRalliesDroppedAndDoNotConsumeIDs() {
        // Kept, dropped (1.0 s span), kept → ids must be 0 and 1, not 0 and 2.
        let dets = run(0, count: 60) + run(120, count: 31) + run(240, count: 60)
        let rallies = RallySegmenter.detectRallies(dets)
        XCTAssertEqual(rallies.map(\.rallyID), [0, 1])
        XCTAssertEqual(rallies[1].startFrame, 240)
    }

    func testInvisibleDetectionsAreSkippedEntirely() {
        // Invisible frames inside a gap neither bridge nor appear in output.
        var dets = run(0, count: 60)
        dets += (60..<95).map { det($0, vis: false) }
        dets += run(95, count: 60)
        let rallies = RallySegmenter.detectRallies(dets)
        XCTAssertEqual(rallies.count, 2, "invisible frames must not bridge a >1 s visible gap")
        XCTAssertTrue(rallies.allSatisfy { $0.trajectory.allSatisfy(\.vis) })
    }

    func testEmptyAndAllInvisibleInputs() {
        XCTAssertTrue(RallySegmenter.detectRallies([]).isEmpty)
        XCTAssertTrue(RallySegmenter.detectRallies((0..<100).map { det($0, vis: false) }).isEmpty)
    }

    // MARK: - trajectories JSON payload

    func testTrajectoriesJSONShape() throws {
        let rallies = RallySegmenter.detectRallies(run(0, count: 60))
        let json = try XCTUnwrap(RallySegmenter.trajectoriesJSON(
            videoStem: "M-game1", orientation: .endOn, rallies: rallies))
        let obj = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])

        XCTAssertEqual(obj["video"] as? String, "M-game1")
        XCTAssertEqual(obj["fps"] as? Double, 30.0, "canonical-30 indices require fps 30")
        XCTAssertEqual(obj["orientation"] as? String, "end_on")

        let ralliesJSON = try XCTUnwrap(obj["rallies"] as? [[String: Any]])
        XCTAssertEqual(ralliesJSON.count, 1)
        XCTAssertEqual(ralliesJSON[0]["rally_id"] as? Int, 0)
        XCTAssertEqual(ralliesJSON[0]["start_frame"] as? Int, 0)
        XCTAssertEqual(ralliesJSON[0]["end_frame"] as? Int, 59)
        let trajectory = try XCTUnwrap(ralliesJSON[0]["trajectory"] as? [[String: Any]])
        XCTAssertEqual(trajectory.count, 60)
        XCTAssertEqual(trajectory[0]["vis"] as? Bool, true, "vis must always be written")
    }

    func testTrajectoriesJSONDefaultsOrientationToSideOn() throws {
        let json = try XCTUnwrap(RallySegmenter.trajectoriesJSON(
            videoStem: "V", orientation: nil, rallies: []))
        let obj = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(obj["orientation"] as? String, "side_on")
    }

    // MARK: - Labeler bridge

    func testQueueItemsMapFramesToSeconds() {
        let items = RallySegmenter.detectRallies(run(90, count: 60)).map { rally in
            RallyLabelQueueItem(rallyID: rally.rallyID,
                                startTime: Double(rally.startFrame) / 30,
                                endTime: Double(rally.endFrame) / 30)
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].startTime, 3.0, accuracy: 1e-9)
        XCTAssertEqual(items[0].endTime, 149.0 / 30.0, accuracy: 1e-9)
    }
}

// MARK: - unmasked_import provenance (wave 1 Phase 4)

extension RallySegmenterTests {

    func testTrajectoriesJSONTagsUnmaskedImport() throws {
        let json = try XCTUnwrap(RallySegmenter.trajectoriesJSON(
            videoStem: "import-abc", orientation: nil, rallies: [],
            unmaskedImport: true))
        let obj = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(obj["unmasked_import"] as? Bool, true)

        let live = try XCTUnwrap(RallySegmenter.trajectoriesJSON(
            videoStem: "M-game1", orientation: nil, rallies: []))
        let liveObj = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(live.utf8)) as? [String: Any])
        XCTAssertNil(liveObj["unmasked_import"])
    }
}
