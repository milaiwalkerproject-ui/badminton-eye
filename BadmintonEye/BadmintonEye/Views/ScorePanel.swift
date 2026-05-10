import SwiftUI
import ScoringEngine

/// Full-height score panel for one side of the match.
///
/// Layout (task 585418ae — score visibility):
/// Score numerals are pinned to the upper portion of the panel so they
/// are immediately visible at a glance. A small top inset provides safe-area
/// breathing room; the remaining space below expands naturally so tapping
/// anywhere on the full half-screen scores a point.
struct ScorePanel: View {
    let score: Int
    let teamName: String
    let isServing: Bool
    let serviceCourt: Court?
    let playerNames: [String]
    let backgroundColor: Color

    /// VoiceOver label describing team, score, and serving status. (A11Y-01)
    private var accessibilityDescription: String {
        var parts = [teamName, "\(score) points"]
        if isServing {
            let courtName = serviceCourt.map { $0 == .right ? "right court" : "left court" } ?? ""
            parts.append("serving\(courtName.isEmpty ? "" : " from \(courtName)")")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 8) {
                // Small top spacer for safe-area breathing room.
                // maxHeight keeps the score in the upper ~40 % of the panel.
                Spacer().frame(maxHeight: 64)

                // Server indicator
                if isServing {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.yellow)
                        if let court = serviceCourt {
                            Text(court == .right ? "R" : "L")
                                .font(.caption.bold())
                                .foregroundStyle(.yellow)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.3))
                    .clipShape(Capsule())
                } else {
                    // Invisible placeholder preserves vertical rhythm
                    HStack(spacing: 6) {
                        Image(systemName: "circle.fill").font(.system(size: 14))
                        Text("R").font(.caption.bold())
                    }
                    .hidden()
                }

                // Score — large, bold, high-contrast (task 585418ae: ≥48 pt bold)
                Text("\(score)")
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.4)
                    .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)

                // Team / player names below score
                VStack(spacing: 2) {
                    ForEach(playerNames, id: \.self) { name in
                        Text(name)
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }

                // Fills the remaining lower 60 % of the panel — tap zone stays full-height
                Spacer()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }
}
