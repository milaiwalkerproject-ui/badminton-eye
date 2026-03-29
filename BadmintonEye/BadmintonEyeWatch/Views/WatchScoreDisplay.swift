import SwiftUI

struct WatchScoreDisplay: View {
    let score: Int
    let teamName: String
    let isServing: Bool
    let color: Color

    var body: some View {
        Text("\(score)")
    }
}
