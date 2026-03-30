import SwiftUI
import ScoringEngine

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

            VStack(spacing: 12) {
                Spacer()

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
                    // Placeholder to keep layout stable
                    HStack(spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 14))
                        Text("R")
                            .font(.caption.bold())
                    }
                    .hidden()
                }

                // Score
                Text("\(score)")
                    .font(.system(size: 120, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)

                // Team/player names
                VStack(spacing: 2) {
                    ForEach(playerNames, id: \.self) { name in
                        Text(name)
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }

                Spacer()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }
}
