import SwiftUI
import ScoringEngine

// MARK: - Suggestion model

/// Predicted result for a single rally.
struct RallySuggestion: Sendable, Equatable {
    let side: Side
    let confidence: Double  // 0...1
}

// MARK: - Protocol

/// Anything that can produce a winner suggestion for a finished rally.
/// Phase C ships a stubbed implementation; Phase D will provide one backed
/// by `CircularFrameBuffer` + `ShuttleDetecting` + `TrajectoryCalculator`
/// against a calibrated court — same protocol, no caller changes needed.
protocol RallySuggesting: Sendable {
    func suggest() async -> RallySuggestion
}

// MARK: - Stub implementation

/// Returns a coin-flip side with a plausible-looking confidence after a
/// brief artificial delay. Exists so the UX flow is testable on-device
/// before the real ML model lands.
struct StubRallySuggestor: RallySuggesting {
    func suggest() async -> RallySuggestion {
        try? await Task.sleep(nanoseconds: 900_000_000) // 0.9s
        let side: Side = Bool.random() ? .sideA : .sideB
        let confidence = Double.random(in: 0.55...0.85)
        return RallySuggestion(side: side, confidence: confidence)
    }
}

// MARK: - Sheet view

/// Modal presented after the user taps "Rally Ended". Shows a loading
/// state while the suggestor works, then a card with the predicted winner
/// + confidence and three options: Confirm the suggestion, override to the
/// other side, or Cancel without scoring.
struct RallySuggestionSheet: View {
    let teamANames: [String]
    let teamBNames: [String]
    /// Called with the chosen side, or `nil` if the user cancelled.
    let onResolve: (Side?) -> Void

    @State private var suggestion: RallySuggestion?
    @Environment(\.dismiss) private var dismiss

    /// Injected suggestor. Defaults to `StubRallySuggestor()` so previews
    /// and tests don't need a live capture pipeline. `LiveMatchView`
    /// passes in the real `TrajectoryRallySuggestor` from the view model.
    private let suggestor: RallySuggesting

    /// §3.1 auto-apply gate. Evaluated once, after the suggestor produces a
    /// result (which records the full `RallyResult` provenance). When it
    /// returns `true`, the sheet auto-resolves to the suggested side instead of
    /// waiting for a manual Confirm — high-confidence rallies don't interrupt
    /// play (the point stays undoable). Defaults to never auto-applying.
    private let autoApply: () -> Bool

    init(
        teamANames: [String],
        teamBNames: [String],
        suggestor: RallySuggesting = StubRallySuggestor(),
        autoApply: @escaping () -> Bool = { false },
        onResolve: @escaping (Side?) -> Void
    ) {
        self.teamANames = teamANames
        self.teamBNames = teamBNames
        self.suggestor = suggestor
        self.autoApply = autoApply
        self.onResolve = onResolve
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("Rally Ended")
                .font(.title2.bold())
                .padding(.top, 24)

            Spacer()

            if let s = suggestion {
                resultCard(for: s)
            } else {
                analyzingCard
            }

            Spacer()

            Button(role: .cancel) {
                resolve(with: nil)
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .task {
            // Run the suggestor only once per sheet presentation.
            guard suggestion == nil else { return }
            let produced = await suggestor.suggest()
            // §3.1: confident + corroborated + not a close call → auto-apply
            // without a manual tap (brief flash, then dismiss). Otherwise show
            // the confirm/override card so the user decides.
            if autoApply() {
                resolve(with: produced.side)
            } else {
                suggestion = produced
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Subviews

    private var analyzingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Analyzing rally…")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func resultCard(for suggestion: RallySuggestion) -> some View {
        let suggestedName = name(for: suggestion.side)
        let otherSide: Side = suggestion.side == .sideA ? .sideB : .sideA
        let otherName = name(for: otherSide)

        return VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Point to")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(suggestedName)
                    .font(.system(size: 36, weight: .bold))
                    .multilineTextAlignment(.center)
                Text("\(Int(suggestion.confidence * 100))% confidence")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(.green.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)

            Button {
                resolve(with: suggestion.side)
            } label: {
                Text("Confirm")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .padding(.horizontal, 24)

            Button {
                resolve(with: otherSide)
            } label: {
                Text("Actually, point to \(otherName)")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Helpers

    private func name(for side: Side) -> String {
        let names = side == .sideA ? teamANames : teamBNames
        return names.first ?? (side == .sideA ? "Side A" : "Side B")
    }

    private func resolve(with side: Side?) {
        onResolve(side)
        dismiss()
    }
}
