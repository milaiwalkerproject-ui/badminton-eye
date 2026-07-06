// FullMatchAnalyzerTests.swift
// Pins for wave 1 Phase 2: the chunked analysis store (append/fold/resume,
// crash tolerance) and FullMatchAnalyzer's pure dedupe rule. The AVAssetReader
// path itself needs a real video file and a CoreML model, so it is exercised
// on-device, not here (the simulator's Footage/ directory is empty by design).

import XCTest
@testable import BadmintonEye

final class FullMatchAnalyzerTests: XCTestCase {

    private func det(_ f: Int, conf: Double, vis: Bool = true) -> AnalyzedDetection {
        AnalyzedDetection(f: f, x: 0.5, y: 0.5, conf: conf, vis: vis)
    }

    private func chunkLine(_ chunk: AnalyzedChunk) throws -> Data {
        var data = try JSONEncoder().encode(chunk)
        data.append(0x0A)
        return data
    }

    // MARK: - Store fold + resume

    func testChunksFoldLatestPerIndexAndSort() throws {
        var data = Data()
        data.append(try chunkLine(AnalyzedChunk(chunk: 1, fStart: 900, fEnd: 1799,
                                                detections: [det(900, conf: 0.9)])))
        data.append(try chunkLine(AnalyzedChunk(chunk: 0, fStart: 0, fEnd: 899,
                                                detections: [det(0, conf: 0.8)])))
        // Rewritten chunk 0 (e.g. a redundant re-run): latest line wins.
        data.append(try chunkLine(AnalyzedChunk(chunk: 0, fStart: 0, fEnd: 899,
                                                detections: [det(1, conf: 0.7)])))

        let chunks = FullMatchAnalysisStore.chunks(jsonlData: data)
        XCTAssertEqual(chunks.map(\.chunk), [0, 1])
        XCTAssertEqual(chunks[0].detections, [det(1, conf: 0.7)])
    }

    func testChunksSkipTornAndMalformedLines() throws {
        var data = Data("not json at all\n".utf8)
        data.append(try chunkLine(AnalyzedChunk(chunk: 0, fStart: 0, fEnd: 899,
                                                detections: [])))
        // A torn final line (kill mid-write) must not poison the file.
        data.append(Data("{\"schema\":1,\"chunk\":2,\"fSta".utf8))

        let chunks = FullMatchAnalysisStore.chunks(jsonlData: data)
        XCTAssertEqual(chunks.map(\.chunk), [0])
    }

    func testContiguousCompletedChunksStopsAtGap() {
        func chunk(_ index: Int) -> AnalyzedChunk {
            AnalyzedChunk(chunk: index, fStart: index * 900,
                          fEnd: index * 900 + 899, detections: [])
        }
        XCTAssertEqual(FullMatchAnalysisStore.contiguousCompletedChunks([]), 0)
        XCTAssertEqual(FullMatchAnalysisStore.contiguousCompletedChunks(
            [chunk(0), chunk(1), chunk(2)]), 3)
        // Gap at 2: resume there even though 3 exists (3 is harmless overlap).
        XCTAssertEqual(FullMatchAnalysisStore.contiguousCompletedChunks(
            [chunk(0), chunk(1), chunk(3)]), 2)
        XCTAssertEqual(FullMatchAnalysisStore.contiguousCompletedChunks(
            [chunk(1), chunk(2)]), 0)
    }

    // MARK: - Store round-trip on disk

    func testAppendAndReadRoundTrip() throws {
        let stem = "test-\(UUID().uuidString)"
        defer { FullMatchAnalysisStore.clear(videoStem: stem) }

        FullMatchAnalysisStore.append(
            AnalyzedChunk(chunk: 0, fStart: 0, fEnd: 899,
                          detections: [det(10, conf: 0.9), det(11, conf: 0.4, vis: false)]),
            videoStem: stem)
        FullMatchAnalysisStore.append(
            AnalyzedChunk(chunk: 1, fStart: 900, fEnd: 1799,
                          detections: [det(900, conf: 0.7)]),
            videoStem: stem)

        let all = FullMatchAnalysisStore.allDetections(videoStem: stem)
        XCTAssertEqual(all.map(\.f), [10, 11, 900])
        XCTAssertEqual(all[1].vis, false)

        FullMatchAnalysisStore.clear(videoStem: stem)
        XCTAssertTrue(FullMatchAnalysisStore.chunks(videoStem: stem).isEmpty)
    }

    func testEmptyStemHasNoFile() {
        XCTAssertNil(FullMatchAnalysisStore.fileURL(videoStem: ""))
        FullMatchAnalysisStore.append(
            AnalyzedChunk(chunk: 0, fStart: 0, fEnd: 0, detections: []), videoStem: "")
        XCTAssertTrue(FullMatchAnalysisStore.chunks(videoStem: "").isEmpty)
    }

    // MARK: - Canonical-frame dedupe (60 fps → 30 canonical)

    func testBetterPrefersVisibleThenConfidence() {
        let visible = det(5, conf: 0.6)
        let invisible = det(5, conf: 0.9, vis: false)
        XCTAssertEqual(FullMatchAnalyzer.better(visible, invisible), visible)
        XCTAssertEqual(FullMatchAnalyzer.better(invisible, visible), visible)

        let strong = det(5, conf: 0.9)
        XCTAssertEqual(FullMatchAnalyzer.better(visible, strong), strong)
        XCTAssertEqual(FullMatchAnalyzer.better(strong, visible), strong)

        let alsoInvisible = det(5, conf: 0.2, vis: false)
        XCTAssertEqual(FullMatchAnalyzer.better(invisible, alsoInvisible), invisible)
    }
}
