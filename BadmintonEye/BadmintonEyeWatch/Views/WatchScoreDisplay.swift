import SwiftUI

struct WatchScoreDisplay: View {
    let score: Int
    let teamName: String
    let isServing: Bool
    let color: Color

    var body: some View {
        ZStack {
            color.opacity(0.85)

            VStack(spacing: 2) {
                // Shuttlecock server indicator
                if isServing {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.yellow)
                } else {
                    Spacer().frame(height: 8)
                }

                // Score -- large and centered
                Text("\(score)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)

                // Team name -- small
                Text(teamName)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
    }
}
