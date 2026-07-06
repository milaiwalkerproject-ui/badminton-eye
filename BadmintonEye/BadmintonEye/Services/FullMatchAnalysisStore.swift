// FullMatchAnalysisStore.swift
// Chunked, resumable persistence for full-match TrackNet analysis
// (wave 1 Phase 2 — see .planning/FULLMATCH-PHASE2-SPEC.md).
//
// One JSONL file per video at
// `Application Support/FullMatchAnalysis/<videoStem>.detections.jsonl`,
// one line per COMPLETED chunk (a chunk is complete iff its line exists).
// Cloned from the TrainingExportWriter pattern: best-effort writes (atomic
// first write, FileHandle append after) and torn/malformed lines silently
// skipped on read — a mid-write kill costs one chunk of work, never the file.

import Foundation

/// One per-canonical-frame detection. `x`/`y` are normalized image
/// coordinates (origin top-left, y down), `f` is the canonical frame index
/// `round(t × 30)`, `vis` false means no shuttle above threshold (python
/// trajectory parity: consumers filter on `vis` but the field is always
/// written).
struct AnalyzedDetection: Codable, Sendable, Equatable {
    let f: Int
    let x: Double
    let y: Double
    let conf: Double
    let vis: Bool
}

/// One completed analysis chunk (a contiguous time slice of the video).
struct AnalyzedChunk: Codable, Sendable, Equatable {
    var schema: Int = 1
    let chunk: Int          // 0-based chunk index
    let fStart: Int         // first canonical frame index covered (inclusive)
    let fEnd: Int           // last canonical frame index covered (inclusive)
    let detections: [AnalyzedDetection]
}

enum FullMatchAnalysisStore {

    /// `Application Support/FullMatchAnalysis/`, created on demand.
    static func directory() -> URL? {
        guard let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
        else { return nil }
        let dir = support.appendingPathComponent("FullMatchAnalysis", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func fileURL(videoStem: String) -> URL? {
        guard !videoStem.isEmpty else { return nil }
        return directory()?.appendingPathComponent("\(videoStem).detections.jsonl")
    }

    /// Append one completed chunk. Best-effort and non-throwing.
    static func append(_ chunk: AnalyzedChunk, videoStem: String) {
        guard let url = fileURL(videoStem: videoStem) else { return }
        let encoder = JSONEncoder()
        guard var line = try? encoder.encode(chunk) else { return }
        line.append(0x0A)

        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url, options: .atomic)
        }
    }

    /// All persisted chunks for a video, deduped (latest line per chunk
    /// index wins) and sorted. Malformed lines are skipped.
    static func chunks(videoStem: String) -> [AnalyzedChunk] {
        guard let url = fileURL(videoStem: videoStem),
              let data = try? Data(contentsOf: url)
        else { return [] }
        return chunks(jsonlData: data)
    }

    /// Pure core of `chunks(videoStem:)`, separated for tests.
    static func chunks(jsonlData: Data) -> [AnalyzedChunk] {
        let decoder = JSONDecoder()
        var byIndex: [Int: AnalyzedChunk] = [:]
        for line in jsonlData.split(separator: 0x0A) {
            guard let chunk = try? decoder.decode(AnalyzedChunk.self, from: Data(line)) else { continue }
            byIndex[chunk.chunk] = chunk
        }
        return byIndex.values.sorted { $0.chunk < $1.chunk }
    }

    /// Number of chunks completed WITHOUT a gap from chunk 0 — the resume
    /// point. (A file with chunks [0,1,3] resumes at 2; chunk 3 is redundant
    /// work that the dedup on read makes harmless.)
    static func contiguousCompletedChunks(_ chunks: [AnalyzedChunk]) -> Int {
        var next = 0
        for chunk in chunks {
            if chunk.chunk == next { next += 1 } else if chunk.chunk > next { break }
        }
        return next
    }

    /// Flat, f-sorted detection list across all completed chunks.
    static func allDetections(videoStem: String) -> [AnalyzedDetection] {
        chunks(videoStem: videoStem).flatMap(\.detections).sorted { $0.f < $1.f }
    }

    /// Removes the stored analysis (for a full re-analyze).
    static func clear(videoStem: String) {
        guard let url = fileURL(videoStem: videoStem) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
