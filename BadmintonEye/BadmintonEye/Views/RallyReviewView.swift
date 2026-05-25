import SwiftUI
import AVKit
import AVFoundation
import ScoringEngine

/// Non-blocking review of low-confidence / uncertain rally calls. Opened from a
/// badge in `LiveMatchView` (never auto-presented, so it can't block live
/// play). Each call replays its ~2 s window from the recorded game video with
/// slow-motion + pinch-zoom; the user can confirm the auto call or override it.
/// An override records a human-sourced label to the training export — it does
/// not retroactively change the live score (the point was already played).
struct RallyReviewView: View {
    let items: [LiveMatchViewModel.ReviewItem]
    let teamANames: [String]
    let teamBNames: [String]
    let onVerdict: (LiveMatchViewModel.ReviewItem, Side) -> Void
    let onDismissItem: (LiveMatchViewModel.ReviewItem) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView {
                        Label("All caught up", systemImage: "checkmark.circle")
                    } description: {
                        Text("No calls to review. Close calls the system wasn't sure about show up here.")
                            .multilineTextAlignment(.center)
                    }
                } else {
                    List {
                        Section {
                            ForEach(items) { item in
                                NavigationLink {
                                    RallyReviewDetail(
                                        item: item,
                                        teamANames: teamANames,
                                        teamBNames: teamBNames,
                                        onVerdict: { side in
                                            onVerdict(item, side)
                                            dismiss()
                                        },
                                        onAgree: {
                                            onDismissItem(item)
                                            dismiss()
                                        }
                                    )
                                } label: {
                                    row(for: item)
                                }
                            }
                        } footer: {
                            Text("Reviewing a call records your verdict to improve future scoring. It doesn't change the current match score.")
                                .font(.footnote)
                        }
                    }
                }
            }
            .navigationTitle("Review Calls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(for item: LiveMatchViewModel.ReviewItem) -> some View {
        let r = item.result
        return HStack(spacing: 12) {
            Image(systemName: r.landing?.result == .uncertain ? "questionmark.circle" : "magnifyingglass.circle")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto: point to \(name(for: r.winner))")
                    .font(.system(.body, design: .rounded).weight(.medium))
                Text("\(Int(r.confidence * 100))% confidence\(r.landing?.result == .uncertain ? " · close call" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func name(for side: Side) -> String {
        let names = side == .sideA ? teamANames : teamBNames
        return names.first ?? (side == .sideA ? "Side A" : "Side B")
    }
}

// MARK: - Detail (zoom + slow-mo player + verdict)

private struct RallyReviewDetail: View {
    let item: LiveMatchViewModel.ReviewItem
    let teamANames: [String]
    let teamBNames: [String]
    let onVerdict: (Side) -> Void
    let onAgree: () -> Void

    @State private var player: AVPlayer?
    @State private var clipAvailable = false
    @State private var zoom: CGFloat = 1.6

    private var result: RallyResult { item.result }

    var body: some View {
        VStack(spacing: 20) {
            playerArea
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16))

            if clipAvailable {
                HStack {
                    Image(systemName: "minus.magnifyingglass")
                    Slider(value: $zoom, in: 1.0...3.0)
                    Image(systemName: "plus.magnifyingglass")
                }
                .padding(.horizontal)
                Text("Slow-motion · pinch or drag to zoom")
                    .font(.caption).foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Text("System called: point to \(name(for: result.winner))")
                    .font(.headline)
                Text("\(Int(result.confidence * 100))% confidence\(result.landing?.result == .uncertain ? " · close call" : "")")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                Button {
                    onAgree()
                } label: {
                    Label("Looks right (point to \(name(for: result.winner)))", systemImage: "checkmark")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent).tint(.green)

                Button {
                    onVerdict(otherSide)
                } label: {
                    Text("Actually, point to \(name(for: otherSide))")
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered).tint(.orange)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.top, 16)
        .navigationTitle("Game \(result.rallyIndex >= 0 ? "rally \(result.rallyIndex + 1)" : "call")")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: setupPlayer)
        .onDisappear { player?.pause() }
    }

    @ViewBuilder
    private var playerArea: some View {
        if let player, clipAvailable {
            VideoPlayer(player: player)
                .scaleEffect(zoom)
                .clipped()
                .gesture(MagnificationGesture().onChanged { zoom = min(max($0 * 1.6, 1.0), 3.0) })
                .onTapGesture { replay() }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "film.slash").font(.largeTitle).foregroundStyle(.secondary)
                Text("Clip not available")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Footage records on device during a live match.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding()
        }
    }

    private var otherSide: Side { result.winner == .sideA ? .sideB : .sideA }

    private func name(for side: Side) -> String {
        let names = side == .sideA ? teamANames : teamBNames
        return names.first ?? (side == .sideA ? "Side A" : "Side B")
    }

    private func setupPlayer() {
        guard let clip = result.clipRef, !clip.fileName.isEmpty,
              let dir = GameVideoRecord.footageDirectory() else { return }
        let url = dir.appendingPathComponent(clip.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let p = AVPlayer(url: url)
        p.seek(to: CMTime(seconds: clip.startTime, preferredTimescale: 600))
        p.rate = 0.5   // slow-motion review
        player = p
        clipAvailable = true
    }

    private func replay() {
        guard let player, let clip = result.clipRef else { return }
        player.seek(to: CMTime(seconds: clip.startTime, preferredTimescale: 600))
        player.rate = 0.5
    }
}
