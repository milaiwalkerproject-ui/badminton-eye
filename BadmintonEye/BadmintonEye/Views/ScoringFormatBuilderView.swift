import SwiftUI
import ScoringEngine

/// Form-based UI for creating custom scoring rules.
struct ScoringFormatBuilderView: View {
    @Binding var customRules: ScoringRules?
    @Environment(\.dismiss) private var dismiss

    @State private var pointsToWin = 21
    @State private var deuceThreshold = 20
    @State private var capScore = 30
    @State private var gamesToWin = 2
    @State private var midGameSwitchPoint = 11

    private var maxGames: Int { gamesToWin * 2 - 1 }

    private var rules: ScoringRules {
        ScoringRules(
            pointsToWin: pointsToWin,
            deuceThreshold: deuceThreshold,
            capScore: capScore,
            gamesToWin: gamesToWin,
            maxGames: maxGames,
            midGameSwitchPoint: midGameSwitchPoint
        )
    }

    private var validationErrors: [String] {
        var errors: [String] = []
        if pointsToWin < 1 { errors.append("Points to win must be at least 1") }
        if deuceThreshold >= pointsToWin { errors.append("Deuce threshold must be less than points to win") }
        if capScore <= pointsToWin { errors.append("Cap score must be greater than points to win") }
        if midGameSwitchPoint >= pointsToWin { errors.append("Mid-game switch must be less than points to win") }
        if maxGames > 5 { errors.append("Maximum 5 games (best of 3 = games to win 3)") }
        return errors
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Points") {
                    Stepper("Points to win: \(pointsToWin)", value: $pointsToWin, in: 1...99)
                    Stepper("Deuce at: \(deuceThreshold)", value: $deuceThreshold, in: 0...98)
                    Stepper("Cap score: \(capScore)", value: $capScore, in: 2...99)
                }

                Section("Games") {
                    Stepper("Games to win: \(gamesToWin)", value: $gamesToWin, in: 1...3)
                    Text("Best of \(maxGames)")
                        .foregroundStyle(.secondary)
                }

                Section("Side Switch") {
                    Stepper("Switch at: \(midGameSwitchPoint) pts (final game)", value: $midGameSwitchPoint, in: 1...98)
                }

                if !validationErrors.isEmpty {
                    Section {
                        ForEach(validationErrors, id: \.self) { error in
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                }

                Section {
                    Button("Use These Rules") {
                        customRules = rules
                        dismiss()
                    }
                    .disabled(!validationErrors.isEmpty)
                    .frame(maxWidth: .infinity)
                    .font(.headline)
                }
            }
            .navigationTitle("Custom Scoring")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
