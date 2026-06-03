import Foundation
import SwiftData

/// A single recorded game within a `PersistedMatch`.
///
/// One row is produced per game (game 1, game 2, …) as the match progresses.
/// `fileName` is the local filename inside the app's
/// `Application Support/Footage/` directory — never a Photos asset, because the
/// Footage feature needs the app to own the file so it can run the highlight
/// pipeline on it later.
///
/// Wiring still required after this file lands:
/// 1. Add `GameVideoRecord.self` to the `ModelContainer(for: ...)` call in
///    `App/BadmintonEyeApp.swift` (two spots).
/// 2. Add a SwiftData relationship from `PersistedMatch` →
///    `[GameVideoRecord]?` with `deleteRule: .cascade` and
///    `inverse: \GameVideoRecord.match`.
/// 3. Register this file in `BadmintonEye.xcodeproj/project.pbxproj`.
/// 4. Append a new record from `LiveMatchViewModel` at each game-complete
///    transition (see HANDOFF.md in the job dir).
@Model
final class GameVideoRecord {
    var id: UUID = UUID()

    /// 1-indexed game number within the parent match.
    var gameNumber: Int = 1

    /// Filename inside `Application Support/Footage/` (no path, no scheme).
    /// Optional only so CloudKit migration stays additive — empty == no
    /// video captured (camera denied, simulator, etc.).
    var fileName: String = ""

    var startedAt: Date = Date()
    var endedAt: Date?

    /// Number of rallies recorded in this game. Sourced from
    /// `MatchEngine.events.count` at game completion.
    var rallyCount: Int = 0

    /// Final score for this game (side A / side B).
    var scoreA: Int = 0
    var scoreB: Int = 0

    /// Optional human-readable venue / court label. May come from match
    /// setup (user-entered) or, eventually, CoreLocation reverse geocode.
    var locationName: String?

    /// Back-reference to the owning match. No `inverse:` on this side —
    /// the inverse is declared on `PersistedMatch.gameVideos` once it's
    /// added there.
    var match: PersistedMatch?

    // MARK: - Highlight clip (ClipRef)

    /// Persisted highlight "clip": a time-range OFFSET into THIS game video
    /// (not a separate file). A clip is the rally segment the user trimmed in
    /// the highlight editor.
    ///
    /// Both fields are optional so the migration stays purely additive
    /// (matching the CloudKit-safe pattern used by every other property here):
    /// a row with `clipStartTime == nil` simply has no saved highlight yet.
    /// The clip's video file is THIS record's `fileName`, so it is not stored
    /// again here.
    ///
    /// Invariant when present: `0 <= clipStartTime < clipEndTime <= duration`.
    /// Use `clipRef` / `setClip(_:)` rather than touching these directly so the
    /// clamping in `ClipRef.clamped` is always applied.

    /// Highlight start offset, in seconds from the start of the game video.
    var clipStartTime: Double?

    /// Highlight end offset, in seconds from the start of the game video.
    var clipEndTime: Double?

    init() {}

    init(
        gameNumber: Int,
        fileName: String,
        startedAt: Date,
        endedAt: Date?,
        rallyCount: Int,
        scoreA: Int,
        scoreB: Int,
        locationName: String?
    ) {
        self.gameNumber = gameNumber
        self.fileName = fileName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.rallyCount = rallyCount
        self.scoreA = scoreA
        self.scoreB = scoreB
        self.locationName = locationName
    }
}

// MARK: - ClipRef trim validation

/// Trim in/out clamping / validation for the highlight clip. `ClipRef` itself
/// (the `{ fileName, startTime, endTime }` time-range contract) is declared in
/// `Services/RallyResult.swift`; this extension is the single source of truth
/// for producing a *valid* clip from a requested in/out range.
extension ClipRef {

    /// Smallest allowed clip length, in seconds. Prevents degenerate
    /// zero/near-zero exports that AVFoundation rejects.
    static let minimumDuration: Double = 0.5

    /// Clip length in seconds.
    var duration: Double { max(0, endTime - startTime) }

    /// Clamps a requested in/out range to a valid clip.
    ///
    /// Rules (single source of truth for trim validation):
    /// - `start` is clamped to `[0, duration - minimumDuration]` (or `[0, ∞)`
    ///   when `duration` is unknown/`nil`).
    /// - `end` is clamped to `[start + minimumDuration, duration]`.
    /// - If the requested range is inverted (`end <= start`), `end` is pushed to
    ///   `start + minimumDuration`.
    ///
    /// Returns `nil` only when no valid clip of at least `minimumDuration` can
    /// fit inside `duration` (i.e. the video is shorter than the minimum).
    static func clamped(
        fileName: String,
        start: Double,
        end: Double,
        duration: Double?
    ) -> ClipRef? {
        // A non-finite / too-short duration means we cannot place a clip.
        if let d = duration, !(d.isFinite) || d < minimumDuration {
            return nil
        }

        let safeStartLowerBound = 0.0
        let startUpperBound: Double
        if let d = duration {
            startUpperBound = max(safeStartLowerBound, d - minimumDuration)
        } else {
            startUpperBound = Double.greatestFiniteMagnitude
        }

        // Sanitize NaN/inf inputs to bounds.
        let reqStart = start.isFinite ? start : safeStartLowerBound
        let reqEnd = end.isFinite ? end : reqStart + minimumDuration

        var clampedStart = min(max(reqStart, safeStartLowerBound), startUpperBound)

        let endUpperBound = duration ?? Double.greatestFiniteMagnitude
        var clampedEnd = min(max(reqEnd, clampedStart + minimumDuration), endUpperBound)

        // If clamping the end against the duration squeezed it below the
        // minimum, walk the start back to preserve the minimum length.
        if clampedEnd - clampedStart < minimumDuration {
            clampedStart = max(safeStartLowerBound, clampedEnd - minimumDuration)
            clampedEnd = max(clampedEnd, clampedStart + minimumDuration)
            if let d = duration, clampedEnd > d {
                return nil
            }
        }

        guard clampedEnd > clampedStart else { return nil }
        return ClipRef(fileName: fileName, startTime: clampedStart, endTime: clampedEnd)
    }
}

// MARK: - ClipRef <-> GameVideoRecord

extension GameVideoRecord {
    /// The saved highlight clip, or `nil` if none has been saved. Returns `nil`
    /// rather than an invalid range if the persisted values are inconsistent.
    /// The clip's `fileName` is this record's own `fileName`.
    var clipRef: ClipRef? {
        guard let start = clipStartTime, let end = clipEndTime,
              end > start, !fileName.isEmpty
        else { return nil }
        return ClipRef(fileName: fileName, startTime: start, endTime: end)
    }

    /// Persists (or clears, when `nil`) the highlight clip on this record.
    /// Only the time-range is stored; the file is always this record's video.
    func setClip(_ clip: ClipRef?) {
        clipStartTime = clip?.startTime
        clipEndTime = clip?.endTime
    }
}

// MARK: - Footage directory

extension GameVideoRecord {
    /// Absolute URL to `Application Support/Footage/`. Created on demand.
    /// Returns nil only if Application Support itself is unavailable
    /// (should never happen on a real device).
    static func footageDirectory() -> URL? {
        guard let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
        else { return nil }
        let dir = support.appendingPathComponent("Footage", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }

    /// Resolved file URL for playback. nil when `fileName` is empty or
    /// the file has been removed from the device.
    func resolvedURL() -> URL? {
        guard !fileName.isEmpty,
              let dir = Self.footageDirectory()
        else { return nil }
        let url = dir.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Convenience: clock-time duration. Returns 0 while the recording is
    /// still in progress (endedAt nil).
    var duration: TimeInterval {
        guard let end = endedAt else { return 0 }
        return max(0, end.timeIntervalSince(startedAt))
    }
}
