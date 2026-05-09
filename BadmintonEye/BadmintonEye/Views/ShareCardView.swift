import SwiftUI
import ScoringEngine

// MARK: - Share Card View

/// A branded scorecard view that can render itself as a UIImage for sharing.
struct ShareCardView: View {
    let state: MatchState
    let matchDate: Date

    private var teamALabel: String {
        state.teamANames.joined(separator: " & ")
            .isEmpty ? "Team A" : state.teamANames.joined(separator: " & ")
    }

    private var teamBLabel: String {
        state.teamBNames.joined(separator: " & ")
            .isEmpty ? "Team B" : state.teamBNames.joined(separator: " & ")
    }

    private var winnerLabel: String? {
        guard let winner = state.matchWinner else { return nil }
        return winner == .sideA ? teamALabel : teamBLabel
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: matchDate)
    }

    private var formatLabel: String {
        switch state.format {
        case .singles: return "Singles"
        case .doubles: return "Doubles"
        case .mixed:   return "Mixed Doubles"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "eye.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("BadmintonEye")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(red: 0.106, green: 0.369, blue: 0.125))

            // Players row
            HStack(alignment: .center, spacing: 12) {
                Text(teamALabel)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(winnerLabel == teamALabel ? .primary : .secondary)

                Text("vs")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(teamBLabel)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(winnerLabel == teamBLabel ? .primary : .secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider().padding(.horizontal, 20)

            // Game scores
            VStack(spacing: 8) {
                ForEach(Array(state.games.enumerated()), id: \.offset) { index, game in
                    HStack {
                        Text("Game \(index + 1)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .leading)
                        Spacer()
                        Text("\(game.scoreA)")
                            .font(.title3.bold())
                            .foregroundStyle(game.scoreA > game.scoreB ? .primary : .secondary)
                            .frame(width: 44, alignment: .center)
                        Text("–")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(game.scoreB)")
                            .font(.title3.bold())
                            .foregroundStyle(game.scoreB > game.scoreA ? .primary : .secondary)
                            .frame(width: 44, alignment: .center)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            Divider().padding(.horizontal, 20)

            // Winner banner
            if let winner = winnerLabel {
                Text("\(winner) wins!")
                    .font(.headline.bold())
                    .foregroundStyle(Color(red: 0.106, green: 0.369, blue: 0.125))
                    .padding(.vertical, 10)
            }

            // Meta row: date + format
            HStack {
                Text(formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatLabel)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            // Branded footer
            Text("Tracked with BadmintonEye")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(.systemGroupedBackground))
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
    }

    // MARK: - Image Export

    /// Renders this view as a UIImage using ImageRenderer (iOS 16+).
    @MainActor
    func renderedImage() -> UIImage? {
        let renderer = ImageRenderer(content: self.frame(width: 340))
        renderer.scale = 3.0
        return renderer.uiImage
    }
}

// MARK: - Share Sheet Presenter

/// Modal wrapper that renders the card and presents the iOS share sheet.
struct ShareCardSheet: View {
    let state: MatchState
    let matchDate: Date

    @Environment(\.dismiss) private var dismiss
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var isRendering = false

    var body: some View {
        NavigationStack {
            ScrollView {
                ShareCardView(state: state, matchDate: matchDate)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
            }

            Button {
                exportAndShare()
            } label: {
                if isRendering {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    Label("Share Image", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.106, green: 0.369, blue: 0.125))
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .disabled(isRendering)
        }
        .navigationTitle("Share Result")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityViewController(items: shareItems)
        }
    }

    @MainActor
    private func exportAndShare() {
        isRendering = true
        let card = ShareCardView(state: state, matchDate: matchDate)
        guard let image = card.renderedImage() else {
            isRendering = false
            return
        }
        shareItems = [image]
        isRendering = false
        showShareSheet = true
    }
}
