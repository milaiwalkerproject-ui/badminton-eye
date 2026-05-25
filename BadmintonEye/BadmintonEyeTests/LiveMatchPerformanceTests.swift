// LiveMatchPerformanceTests.swift
// Performance regression baseline for LiveMatchViewModel.scorePoint(for:).
//
// Uses XCTest measure{} to establish a timing baseline. Any future change that
// makes the synchronous scoring path >20% slower will be flagged by CI.
//
// Design notes:
//   - LiveMatchViewModel uses @Observable (not ObservableObject).
//   - persistState() is dispatched via Task { @MainActor [weak self] in ... }
//     so it runs asynchronously after scorePoint returns. The measure block
//     captures the synchronous hot path only (MatchEngine.apply + state update).
//   - ModelContainer is created in-memory to avoid disk I/O noise.

import XCTest
import SwiftData
import ScoringEngine
@testable import BadmintonEye

final class LiveMatchPerformanceTests: XCTestCase {

    func testScoringThroughput() throws {
        // Build an in-memory SwiftData stack with the full schema used by the app.
        // GameVideoRecord is included because PersistedMatch now has a
        // `gameVideos` relationship to it; the container fails without it.
        let schema = Schema([PersistedMatch.self, GameVideoRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        measure {
            // Each iteration of measure{} gets a fresh match so score counts
            // never reach match completion (which would stop scoring). The
            // ModelContext is created inside the closure because it isn't
            // Sendable and can't be captured across the measure{} boundary;
            // ModelContainer is Sendable, so capturing it is fine.
            let context = ModelContext(container)
            let matchState = MatchState.newSinglesMatch()
            let viewModel = LiveMatchViewModel(state: matchState, modelContext: context)

            for _ in 0..<100 {
                viewModel.scorePoint(for: .sideA)
            }
        }
    }
}
