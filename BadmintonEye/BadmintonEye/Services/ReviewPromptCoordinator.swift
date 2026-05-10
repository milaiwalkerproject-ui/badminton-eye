// ReviewPromptCoordinator.swift
// Testable coordinator that encapsulates SKStoreReviewController prompt logic.
//
// Responsibilities:
//   - Track completed match count in UserDefaults
//   - Deduplicate: the same match session is only counted once (multi-fire guard)
//   - 30-day cooldown between prompts
//   - Injectable UserDefaults and date provider for unit testing

import Foundation

/// Manages when to request an in-app review prompt.
///
/// All state is stored in the provided `UserDefaults` so it survives
/// app launches. The `dateProvider` is injected so tests can control
/// time without sleeping.
///
/// Usage:
/// ```swift
/// var coordinator = ReviewPromptCoordinator()
/// let shouldPrompt = coordinator.process(matchID: matchID, isComplete: state.matchPhase == .complete)
/// if shouldPrompt { requestReview() }
/// ```
struct ReviewPromptCoordinator {

    // MARK: - Storage Keys

    static let completedMatchCountKey  = "completedMatchCount"
    static let lastReviewPromptDateKey = "lastReviewPromptDate"
    private let lastMatchIDKey         = "lastReviewCountedMatchID"

    // MARK: - Dependencies

    let defaults: UserDefaults
    let dateProvider: () -> Date

    // MARK: - Init

    init(defaults: UserDefaults = .standard,
         dateProvider: @escaping () -> Date = { Date() }) {
        self.defaults = defaults
        self.dateProvider = dateProvider
    }

    // MARK: - Public Accessors (exposed for tests)

    /// Number of completed matches counted so far.
    var completedMatchCount: Int {
        defaults.integer(forKey: Self.completedMatchCountKey)
    }

    /// Timestamp (since 1970) of the last time a review was prompted.
    var lastReviewPromptDate: TimeInterval {
        defaults.double(forKey: Self.lastReviewPromptDateKey)
    }

    // MARK: - Core Logic

    /// Processes one match-end event and returns `true` when a review
    /// prompt should be shown.
    ///
    /// - Parameters:
    ///   - matchID: A stable identifier for this match session. The same
    ///     ID can be passed multiple times (e.g. `onAppear` firing twice)
    ///     and will only be counted once.
    ///   - isComplete: `true` only for naturally completed matches.
    ///     Abandoned matches must pass `false` so they are not counted.
    ///
    /// - Returns: `true` exactly when the 5-match threshold is met AND
    ///   the 30-day cooldown has elapsed. Returns `false` in all other cases.
    mutating func process(matchID: String, isComplete: Bool) -> Bool {
        // Gate 1 — only complete matches count toward the prompt
        guard isComplete else { return false }

        // Gate 2 — per-match dedup: don't count the same session twice
        //          (guards against onAppear firing >1 time for one match)
        let lastCounted = defaults.string(forKey: lastMatchIDKey)
        guard lastCounted != matchID else { return false }
        defaults.set(matchID, forKey: lastMatchIDKey)

        // Increment persisted count
        let newCount = completedMatchCount + 1
        defaults.set(newCount, forKey: Self.completedMatchCountKey)

        // Gate 3 — prompt every 5 matches
        guard newCount % 5 == 0 else { return false }

        // Gate 4 — 30-day cooldown
        let cooldown: TimeInterval = 30 * 24 * 60 * 60
        let cutoff = dateProvider().timeIntervalSince1970 - cooldown
        guard lastReviewPromptDate < cutoff else { return false }

        // All gates passed — record prompt time and signal caller
        defaults.set(dateProvider().timeIntervalSince1970,
                     forKey: Self.lastReviewPromptDateKey)
        return true
    }
}
