import SwiftUI

struct WatchWaitingView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "applewatch.and.arrow.forward")
                .font(.system(size: 36))
                .foregroundStyle(.blue)

            Text("Waiting for Match")
                .font(.headline)

            Text("Start a match on your iPhone")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
