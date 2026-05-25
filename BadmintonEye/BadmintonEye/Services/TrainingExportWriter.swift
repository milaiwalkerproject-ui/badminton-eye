import Foundation

/// Appends finalized per-rally `RallyResult`s to a per-match JSONL file at
/// `Application Support/TrainingExport/<matchUUID>.jsonl`.
///
/// Vision's `export_shots.py --ingest-ondevice <dir>` reads these to build the
/// training set (see TRAINING-EXPORT-SCHEMA §6c). The on-device contract is
/// deliberately minimal — we just persist the rich, `Codable` `RallyResult`
/// we already have, one JSON object per line:
///   - **latest line per `rallyIndex` wins**, so a human override written after
///     the auto entry supersedes it (no need to rewrite earlier lines);
///   - `source = .human` rows become training-grade offline; cv-only rows go to
///     the holdout; corroboration/training decisions are made by the python
///     ingest, NOT here.
///
/// Best-effort and non-throwing: training export must never disrupt live
/// scoring, so any I/O failure is silently dropped.
enum TrainingExportWriter {

    /// `Application Support/TrainingExport/`, created on demand. Nil only if
    /// Application Support itself is unavailable.
    static func directory() -> URL? {
        guard let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
        else { return nil }
        let dir = support.appendingPathComponent("TrainingExport", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }

    /// Resolved JSONL file URL for a match (no I/O).
    static func fileURL(matchID: UUID) -> URL? {
        directory()?.appendingPathComponent("\(matchID.uuidString).jsonl")
    }

    /// Append one `RallyResult` as a single JSON line to the match's file.
    static func append(_ result: RallyResult, matchID: UUID) {
        guard let url = fileURL(matchID: matchID) else { return }
        let encoder = JSONEncoder()
        guard var line = try? encoder.encode(result) else { return }
        line.append(0x0A) // '\n' — one JSON object per line

        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            // First write for this match creates the file.
            try? line.write(to: url, options: .atomic)
        }
    }
}
