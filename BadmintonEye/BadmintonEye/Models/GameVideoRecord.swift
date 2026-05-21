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
