import SwiftUI
import ScoringEngine

/// Full-height score panel for one side of the match.
///
/// Visual language: full-bleed brand gradient with a subtle top highlight,
/// SF-Rounded score numeral that animates on increment, and a glass-pill
/// service indicator. Tapping anywhere on the panel scores a point.
struct ScorePanel: View {
    let score: Int
    let teamName: String
    let isServing: Bool
    let serviceCourt: Court?
    let playerNames: [String]
    /// Brand gradient for this side.
    let gradient: LinearGradient

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
            gradient
                .ignoresSafeArea()
                .overlay(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .blendMode(.plusLighter)
                    .ignoresSafeArea()
                )

            VStack(spacing: BE.Space.m) {
                Spacer().frame(maxHeight: 110)

                Group {
                    if isServing {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(BE.serveAccent)
                                .frame(width: 8, height: 8)
                                .shadow(color: BE.serveAccent.opacity(0.7), radius: 6)
                            Text("SERVING")
                                .font(BE.eyebrow)
                                .tracking(1.2)
                                .foregroundStyle(.white)
                            if let court = serviceCourt {
                                Text(court == .right ? "R" : "L")
                                    .font(BE.eyebrow)
                                    .foregroundStyle(BE.serveAccent)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                        )
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        Capsule().fill(.clear).frame(width: 100, height: 26)
                    }
                }
                .animation(BE.pop, value: isServing)

                Text("\(score)")
                    .font(BE.scoreNumeral())
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.35)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                    .contentTransition(.numericText(value: Double(score)))
                    .animation(BE.pop, value: score)

                VStack(spacing: 2) {
                    ForEach(playerNames, id: \.self) { name in
                        Text(name)
                            .font(.system(.headline, design: .rounded).weight(.medium))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }
                .padding(.horizontal, BE.Space.m)
                .multilineTextAlignment(.center)

                Spacer()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }
}
