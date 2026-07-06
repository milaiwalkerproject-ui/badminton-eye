// RallySegmenter.swift
// Wave 1 Phase 3 — splits a full-match detection stream into rallies, ported
// EXACTLY from hawkeye/src/hawkeye/preprocess/extract_rallies.py:91-124 so
// (video, rally_id) keys match what the python flywheel would produce
// (parity rules recorded in .planning/FULLMATCH-PHASE2-SPEC.md):
//
//   - vis=false detections are skipped entirely (never appear in a rally).
//   - A gap STRICTLY GREATER than 1.0 s between visible detections starts a
//     new rally (a gap of exactly 1.0 s stays in-rally).
//   - A rally is kept iff its first→last visible span is >= 1.5 s (inclusive).
//   - start/end snap exactly to the first/last visible frame — no padding.
//   - rally_id is 0-based over KEPT rallies only, assigned after the
//     min-duration filter in a whole-video pass (dropped short rallies never
//     consume ids) — which is why segmentation must run over the complete
//     detection list, never per-chunk.
//
// Also renders the trajectories/<stem>.json payload the python consumers
// read. Detections carry canonical-30 frame indices, so the payload writes
// "fps": 30.0 — python computes every duration as f_delta/fps.

import Foundation

struct SegmentedRally: Sendable, Equatable {
    let rallyID: Int
    let startFrame: Int
    let endFrame: Int
    let trajectory: [AnalyzedDetection]
}

enum RallySegmenter {

    static let gapBoundarySeconds = 1.0
    static let minRallySeconds = 1.5

    /// Exact port of python detect_rallies. `detections` must cover the whole
    /// video and be sorted by `f` (FullMatchAnalysisStore.allDetections is).
    static func detectRallies(_ detections: [AnalyzedDetection],
                              fps: Double = 30) -> [SegmentedRally] {
        var rallies: [SegmentedRally] = []
        var current: [AnalyzedDetection] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let duration = Double(last.f - first.f) / fps
            if duration >= minRallySeconds {
                rallies.append(SegmentedRally(
                    rallyID: rallies.count,
                    startFrame: first.f, endFrame: last.f,
                    trajectory: current))
            }
            current.removeAll()
        }

        for detection in detections where detection.vis {
            if let last = current.last,
               Double(detection.f - last.f) / fps > gapBoundarySeconds {
                flush()
            }
            current.append(detection)
        }
        flush()
        return rallies
    }

    // MARK: - trajectories/<stem>.json (python consumer payload)

    /// Renders the exact structure extract_rallies.py writes. Always includes
    /// `vis` (python consumers filter on it defensively) and `"fps": 30.0`
    /// (frame indices are canonical-30).
    static func trajectoriesJSON(videoStem: String,
                                 orientation: VideoOrientation?,
                                 rallies: [SegmentedRally],
                                 fps: Double = 30) -> String? {
        let payload: [String: Any] = [
            "video": videoStem,
            "fps": fps,
            "orientation": (orientation ?? .sideOn).rawValue,
            "rallies": rallies.map { rally in
                [
                    "rally_id": rally.rallyID,
                    "start_frame": rally.startFrame,
                    "end_frame": rally.endFrame,
                    "trajectory": rally.trajectory.map { d in
                        ["f": d.f, "x": d.x, "y": d.y, "conf": d.conf, "vis": d.vis] as [String: Any]
                    },
                ] as [String: Any]
            },
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                     options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text
    }

    /// Writes `<stem>.json` (the trajectories payload) next to the detection
    /// store and returns its URL. Best-effort.
    @discardableResult
    static func writeTrajectoriesFile(videoStem: String,
                                      orientation: VideoOrientation?,
                                      rallies: [SegmentedRally]) -> URL? {
        guard !videoStem.isEmpty,
              let dir = FullMatchAnalysisStore.directory(),
              let json = trajectoriesJSON(videoStem: videoStem,
                                          orientation: orientation,
                                          rallies: rallies)
        else { return nil }
        let url = dir.appendingPathComponent("\(videoStem).json")
        guard (try? json.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        return url
    }

    // MARK: - Labeler bridge

    /// Rally queue items for analyzed (but not live-scored) footage: falls
    /// back to segmentation when the match's TrainingExport has no rallies
    /// for this video. The two id domains never mix for one video —
    /// TrainingExport rallyIndex takes precedence when present, and labels
    /// made against segmented rallies join the flywheel through the
    /// trajectories/<stem>.json this segmenter exports (same ids).
    static func queueItems(videoStem: String, fps: Double = 30) -> [RallyLabelQueueItem] {
        let detections = FullMatchAnalysisStore.allDetections(videoStem: videoStem)
        guard !detections.isEmpty else { return [] }
        return detectRallies(detections, fps: fps).map { rally in
            RallyLabelQueueItem(rallyID: rally.rallyID,
                                startTime: Double(rally.startFrame) / fps,
                                endTime: Double(rally.endFrame) / fps)
        }
    }
}
