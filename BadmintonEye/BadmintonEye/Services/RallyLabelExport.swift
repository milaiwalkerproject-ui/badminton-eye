// RallyLabelExport.swift
// Builds the labeler's per-video rally work queue from the on-device
// TrainingExport JSONL, and renders labels into the two files the hawkeye
// python flywheel consumes:
//
//   annotations_human_holdout.jsonl — one JSON object per labeled rally:
//     {"video": <stem>, "rally_id": <int>, "winner": "sideA"|"sideB"|"not_rally",
//      "annotator": "in_app", "split": "holdout"|"not_rally",
//      "orientation": "side_on"|"end_on", "timestamp": <ISO8601>Z,
//      "not_rally": true (present ONLY on not-a-rally rows)}
//   Skipped rallies write NO row (absence == unlabeled, per the python
//   contract — `_load_done` resume treats them as still to-do).
//
//   orientation.json — flat {"<video stem>": "side_on"|"end_on"} sidecar.
//   Only videos with a KNOWN orientation are included; absence means side_on
//   to every python reader, so nil orientations are simply omitted.
//
// `rally_id` here is `RallyResult.rallyIndex` — the same numbering the
// on-device TrainingExport uses, so labels join 1:1 with
// `export_shots.py --ingest-ondevice` rows. (Studio-side extract_rallies
// re-segmentation of app videos would number rallies differently; app-recorded
// footage must always join through the on-device numbering.)

import Foundation

/// One rally the labeler can present: a time range into a game video.
struct RallyLabelQueueItem: Identifiable, Sendable, Equatable {
    let rallyID: Int              // RallyResult.rallyIndex
    let startTime: TimeInterval   // seconds into the game video (approximate)
    let endTime: TimeInterval
    var id: Int { rallyID }
}

enum RallyLabelExport {

    // MARK: - Work queue from TrainingExport JSONL

    /// Rallies of one game video, from the match's TrainingExport file:
    /// folds "latest line per rallyIndex wins", keeps rows whose clip points
    /// at `fileName`, sorted by rally index. Tolerant of malformed lines.
    static func queueItems(matchID: UUID, fileName: String) -> [RallyLabelQueueItem] {
        guard !fileName.isEmpty,
              let url = TrainingExportWriter.fileURL(matchID: matchID),
              let data = try? Data(contentsOf: url)
        else { return [] }
        return queueItems(jsonlData: data, fileName: fileName)
    }

    /// Pure core of `queueItems(matchID:fileName:)`, separated for tests.
    static func queueItems(jsonlData: Data, fileName: String) -> [RallyLabelQueueItem] {
        let decoder = JSONDecoder()
        var latest: [Int: RallyResult] = [:]   // rallyIndex → last-seen row
        for line in jsonlData.split(separator: 0x0A) {
            guard let result = try? decoder.decode(RallyResult.self, from: Data(line)) else { continue }
            latest[result.rallyIndex] = result
        }
        return latest.values
            .compactMap { result -> RallyLabelQueueItem? in
                guard let clip = result.clipRef, clip.fileName == fileName else { return nil }
                return RallyLabelQueueItem(rallyID: result.rallyIndex,
                                           startTime: clip.startTime,
                                           endTime: clip.endTime)
            }
            .sorted { $0.rallyID < $1.rallyID }
    }

    // MARK: - Export rendering (pure, deterministic)

    /// One holdout JSONL line for a labeled rally. Field order is sorted for
    /// determinism; python readers use json.loads and don't care.
    static func holdoutLine(videoStem: String, rallyID: Int, verdict: RallyVerdict,
                            orientation: VideoOrientation?, timestamp: Date) -> String? {
        guard !videoStem.isEmpty else { return nil }
        var record: [String: Any] = [
            "video": videoStem,
            "rally_id": rallyID,
            "winner": verdict.rawValue,
            "annotator": "in_app",
            "split": verdict == .notRally ? "not_rally" : "holdout",
            "timestamp": isoTimestamp(timestamp),
        ]
        if let orientation { record["orientation"] = orientation.rawValue }
        if verdict == .notRally { record["not_rally"] = true }
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8)
        else { return nil }
        return line
    }

    /// Full holdout file content (one line per label, trailing newline).
    static func holdoutFileContent(
        _ labels: [(videoStem: String, rallyID: Int, verdict: RallyVerdict,
                    orientation: VideoOrientation?, labeledAt: Date)]
    ) -> String {
        let lines = labels
            .sorted { ($0.videoStem, $0.rallyID) < ($1.videoStem, $1.rallyID) }
            .compactMap { holdoutLine(videoStem: $0.videoStem, rallyID: $0.rallyID,
                                      verdict: $0.verdict, orientation: $0.orientation,
                                      timestamp: $0.labeledAt) }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }

    /// orientation.json content: {"<stem>": "side_on"|"end_on"}. Pass only
    /// KNOWN orientations; callers must omit nil (absent == side_on).
    static func orientationFileContent(_ orientations: [String: VideoOrientation]) -> String? {
        let raw = orientations.reduce(into: [String: String]()) { $0[$1.key] = $1.value.rawValue }
        guard let data = try? JSONSerialization.data(withJSONObject: raw,
                                                     options: [.sortedKeys, .prettyPrinted]),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text + "\n"
    }

    // MARK: - File assembly for the share sheet

    /// Writes both export files into a temp folder and returns their URLs
    /// (holdout first). Returns an empty array when there are no labels.
    static func writeExportFiles(
        labels: [(videoStem: String, rallyID: Int, verdict: RallyVerdict,
                  orientation: VideoOrientation?, labeledAt: Date)],
        orientations: [String: VideoOrientation]
    ) -> [URL] {
        let content = holdoutFileContent(labels)
        guard !content.isEmpty else { return [] }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RallyLabelExport", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var urls: [URL] = []
        let holdoutURL = dir.appendingPathComponent("annotations_human_holdout.jsonl")
        guard (try? content.write(to: holdoutURL, atomically: true, encoding: .utf8)) != nil
        else { return [] }
        urls.append(holdoutURL)

        if !orientations.isEmpty, let orientationText = orientationFileContent(orientations) {
            let orientationURL = dir.appendingPathComponent("orientation.json")
            if (try? orientationText.write(to: orientationURL, atomically: true, encoding: .utf8)) != nil {
                urls.append(orientationURL)
            }
        }
        return urls
    }

    // MARK: - Timestamp

    /// Fractional-seconds ISO 8601 UTC with a trailing "Z", matching the
    /// python writer's `datetime.utcnow().isoformat() + "Z"` shape.
    static func isoTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
