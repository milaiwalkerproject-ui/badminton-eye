// RallyLabel.swift
// A human "who won this rally?" ground-truth label, created by the in-app
// labeler (wave 1 Phase 1 — see .planning/FULLMATCH-WAVE1-PLAN.md).
//
// Keyed by (videoStem, rallyID):
//   - `videoStem` = `GameVideoRecord.fileName` minus its extension — the same
//     stem the hawkeye python pipeline uses as the `video` join key.
//   - `rallyID` = `RallyResult.rallyIndex` (match-monotonic; a game video only
//     contains one game, so it is unique per video).
// Uniqueness is enforced by fetch-then-upsert in code, NOT with
// @Attribute(.unique) — the same schema list feeds the future CloudKit
// configuration and CloudKit rejects unique constraints.
//
// Deliberately RELATIONSHIP-FREE (string keys only): labels are training data
// and must survive the user pruning footage rows, and a relationship would
// drag RallyLabel into every existing test Schema list.
//
// Wiring checklist for this file (all done, kept for the next model's author):
// 1. `RallyLabel.self` added to BOTH `ModelContainer(for:...)` calls in
//    `App/BadmintonEyeApp.swift`.
// 2. Registered in `BadmintonEye.xcodeproj/project.pbxproj` (app target only —
//    the Watch target does not compile SwiftData models).

import Foundation
import SwiftData

/// How a video was filmed, matching the hawkeye ADR-0001 sidecar values.
/// Spatial meaning of a winner label is bound to (winner, orientation):
/// side_on A = left / B = right; end_on A = near (bottom) / B = far (top).
enum VideoOrientation: String, Codable, Sendable, CaseIterable {
    case sideOn = "side_on"
    case endOn = "end_on"
}

/// The labeler's verdict for one rally. `skip` is intentionally NOT a case:
/// skipping writes no label at all (the python contract — absence means
/// unlabeled, and `_load_done` resume treats it as still to-do).
enum RallyVerdict: String, Codable, Sendable, CaseIterable {
    case sideA
    case sideB
    case notRally = "not_rally"
}

@Model
final class RallyLabel {
    var id: UUID = UUID()
    /// `GameVideoRecord.fileName` without extension. Never empty for a valid
    /// label — an empty stem means "no video captured" and is unlabelable.
    var videoStem: String = ""
    /// `RallyResult.rallyIndex` for this rally (0-based, match-monotonic).
    var rallyID: Int = 0
    /// Raw `RallyVerdict` value: "sideA" | "sideB" | "not_rally".
    var verdictRaw: String = ""
    /// Denormalized copy of the video's orientation at labeling time
    /// ("side_on" | "end_on"); the video record is the source of truth.
    var orientationRaw: String?
    var labeledAt: Date = Date()
    /// Set after the label has been included in a share-sheet export at least
    /// once (informational; exports always include all labels).
    var exported: Bool = false

    init() {}

    convenience init(videoStem: String, rallyID: Int,
                     verdict: RallyVerdict, orientation: VideoOrientation?) {
        self.init()
        self.videoStem = videoStem
        self.rallyID = rallyID
        self.verdictRaw = verdict.rawValue
        self.orientationRaw = orientation?.rawValue
    }

    var verdict: RallyVerdict? { RallyVerdict(rawValue: verdictRaw) }

    /// Fetches the existing label for (videoStem, rallyID) and updates it, or
    /// inserts a new one. Call on the main actor with the UI's model context.
    static func upsert(videoStem: String, rallyID: Int,
                       verdict: RallyVerdict, orientation: VideoOrientation?,
                       in context: ModelContext) {
        guard !videoStem.isEmpty else { return }
        let descriptor = FetchDescriptor<RallyLabel>(
            predicate: #Predicate { $0.videoStem == videoStem && $0.rallyID == rallyID }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.verdictRaw = verdict.rawValue
            existing.orientationRaw = orientation?.rawValue
            existing.labeledAt = Date()
            existing.exported = false
        } else {
            context.insert(RallyLabel(videoStem: videoStem, rallyID: rallyID,
                                      verdict: verdict, orientation: orientation))
        }
        try? context.save()
    }
}
