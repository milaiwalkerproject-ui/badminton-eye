import SwiftUI
import UIKit
import AVKit
import ScoringEngine

/// Unified match screen (restructure PR 2): score + video + highlights in one
/// place. The video cards reuse the PR 1 components (VideoThumbnailView,
/// FullMatchAnalysisCoordinator) in this screen's BE-card language —
/// GameVideoSection stays the List-based variant used by the Footage screens.
struct MatchDetailView: View {
    let match: PersistedMatch
    @State private var showExportPicker = false
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    @State private var localization = LocalizationManager.shared

    // Video + highlights (restructure PR 2)
    @State private var analysis = FullMatchAnalysisCoordinator()
    @State private var editingRecord: GameVideoRecord?
    @State private var showPaywall = false
    @State private var highlightShareURL: ShareableURL?
    @State private var playingClip: PlayableClip?

    private var decodedState: CodableMatchState? {
        guard let data = match.stateJSON else { return nil }
        return try? JSONDecoder().decode(CodableMatchState.self, from: data)
    }

    private var games: [GameVideoRecord] {
        (match.gameVideos ?? []).sorted { $0.gameNumber < $1.gameNumber }
    }

    private var highlightRecords: [GameVideoRecord] {
        games.filter { $0.clipRef != nil && $0.resolvedURL() != nil }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: BE.Space.l) {
                // Match metadata header
                metadataSection

                // Scorecard
                if let state = decodedState {
                    decodedScorecard(state)
                    rallyAnalyticsSection(state)
                } else {
                    fallbackScorecard
                }

                if !highlightRecords.isEmpty {
                    highlightsStrip
                }

                if !games.isEmpty {
                    videoSection
                }
            }
            .padding()
        }
        .navigationTitle(localization.localized("match.details"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        shareImage = ScorecardRenderer.renderImage(for: match)
                        if shareImage != nil { showShareSheet = true }
                    } label: {
                        Label(localization.localized("match.shareScorecard"), systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showExportPicker = true
                    } label: {
                        Label(localization.localized("match.export"), systemImage: "doc.text")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showExportPicker) {
            ExportFormatPicker(match: match, isPresented: $showExportPicker)
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ActivityViewController(items: [image])
            }
        }
        .sheet(item: $editingRecord) { rec in
            HighlightClipEditorView(record: rec)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(item: $highlightShareURL) { wrapper in
            ActivityViewController(items: [wrapper.url])
        }
        .sheet(item: $playingClip) { clip in
            ClipPlayerSheet(url: clip.url, startTime: clip.startTime, endTime: clip.endTime)
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(spacing: 8) {
            Text(playerNamesText)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Label(formatBadge, systemImage: "sportscourt")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary)
                    .clipShape(Capsule())

                Text(match.startedAt, format: .dateTime.month().day().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let duration = matchDuration {
                    Text(duration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let side = match.winnerSide {
                let winnerNames = side == "sideA"
                    ? (match.playerAName ?? "Team A")
                    : (match.playerBName ?? "Team B")
                Text("\(winnerNames) Won!")
                    .font(.headline)
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Rally Analytics Section

    private func rallyAnalyticsSection(_ state: CodableMatchState) -> some View {
        let matchState = state.toMatchState()
        guard let analytics = matchState.rallyAnalytics else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 12) {
                Text(localization.localized("analytics.rallyTitle"))
                    .font(.headline)

                HStack(spacing: 16) {
                    analyticsCell(
                        title: localization.localized("analytics.matchDuration"),
                        value: formatInterval(analytics.matchDuration)
                    )
                    Divider()
                    analyticsCell(
                        title: localization.localized("analytics.avgRally"),
                        value: formatInterval(analytics.averageRallyLength)
                    )
                    Divider()
                    analyticsCell(
                        title: localization.localized("analytics.longestRally"),
                        value: formatInterval(analytics.longestRally)
                    )
                }
                .frame(maxWidth: .infinity)
            }
            .padding(BE.Space.l)
            .background(.ultraThinMaterial)
            .clipShape(BE.card(16))
        )
    }

    private func analyticsCell(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatInterval(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    // MARK: - Decoded Scorecard

    private func decodedScorecard(_ state: CodableMatchState) -> some View {
        VStack(spacing: 16) {
            // Header row
            HStack {
                Text("")
                    .frame(width: 80)
                Spacer()
                Text(state.teamANames.first ?? "Team A")
                    .font(.headline)
                    .frame(width: 80)
                Text(state.teamBNames.first ?? "Team B")
                    .font(.headline)
                    .frame(width: 80)
            }

            Divider()

            // Game rows
            ForEach(Array(state.games.enumerated()), id: \.offset) { index, game in
                HStack {
                    Text(String(format: localization.localized("game.number"), index + 1))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Spacer()
                    Text("\(game.scoreA)")
                        .font(.title2.bold())
                        .foregroundStyle(game.scoreA > game.scoreB ? .primary : .secondary)
                        .frame(width: 80)
                    Text("\(game.scoreB)")
                        .font(.title2.bold())
                        .foregroundStyle(game.scoreB > game.scoreA ? .primary : .secondary)
                        .frame(width: 80)
                }
            }

            Divider()

            // Games won summary
            let gamesWon = state.games.reduce((a: 0, b: 0)) { result, game in
                if game.scoreA > game.scoreB {
                    return (result.a + 1, result.b)
                } else if game.scoreB > game.scoreA {
                    return (result.a, result.b + 1)
                }
                return result
            }

            HStack {
                Text(localization.localized("match.games"))
                    .font(.subheadline.bold())
                    .frame(width: 80, alignment: .leading)
                Spacer()
                Text("\(gamesWon.a)")
                    .font(.title2.bold())
                    .frame(width: 80)
                Text("\(gamesWon.b)")
                    .font(.title2.bold())
                    .frame(width: 80)
            }
        }
        .padding(BE.Space.l)
        .background(.ultraThinMaterial)
        .clipShape(BE.card(16))
    }

    // MARK: - Fallback Scorecard

    private var fallbackScorecard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("")
                    .frame(width: 80)
                Spacer()
                Text(match.playerAName ?? "Team A")
                    .font(.headline)
                    .frame(width: 80)
                Text(match.playerBName ?? "Team B")
                    .font(.headline)
                    .frame(width: 80)
            }

            Divider()

            gameRow(String(format: localization.localized("game.number"), 1), scoreA: match.game1ScoreA, scoreB: match.game1ScoreB)

            if let g2a = match.game2ScoreA, let g2b = match.game2ScoreB {
                gameRow(String(format: localization.localized("game.number"), 2), scoreA: g2a, scoreB: g2b)
            }

            if let g3a = match.game3ScoreA, let g3b = match.game3ScoreB {
                gameRow(String(format: localization.localized("game.number"), 3), scoreA: g3a, scoreB: g3b)
            }
        }
        .padding(BE.Space.l)
        .background(.ultraThinMaterial)
        .clipShape(BE.card(16))
    }

    private func gameRow(_ label: String, scoreA: Int, scoreB: Int) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Spacer()
            Text("\(scoreA)")
                .font(.title2.bold())
                .foregroundStyle(scoreA > scoreB ? .primary : .secondary)
                .frame(width: 80)
            Text("\(scoreB)")
                .font(.title2.bold())
                .foregroundStyle(scoreB > scoreA ? .primary : .secondary)
                .frame(width: 80)
        }
    }

    // MARK: - Highlights strip (restructure PR 2)

    private var highlightsStrip: some View {
        VStack(alignment: .leading, spacing: BE.Space.s) {
            Text(localization.localized("match.highlights.title").uppercased())
                .font(BE.eyebrow)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BE.Space.s) {
                    ForEach(highlightRecords) { record in
                        highlightChip(record)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func highlightChip(_ record: GameVideoRecord) -> some View {
        Button {
            if let url = record.resolvedURL(), let clip = record.clipRef {
                playingClip = PlayableClip(id: record.id,
                                           url: url,
                                           startTime: clip.startTime,
                                           endTime: clip.endTime)
            }
        } label: {
            HStack(spacing: BE.Space.xs) {
                Image(systemName: "play.fill")
                    .font(.caption2)
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(format: localization.localized("game.number"), record.gameNumber))
                        .font(.caption.weight(.semibold))
                    Text(GameVideoSection.highlightLabel(record))
                        .font(.caption2)
                        .opacity(0.8)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, BE.Space.m)
            .padding(.vertical, BE.Space.s)
            .background(BE.card(14).fill(BE.TeamA.gradient))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Video section (restructure PR 2)

    private var videoSection: some View {
        VStack(alignment: .leading, spacing: BE.Space.s) {
            Text(localization.localized("match.video.title").uppercased())
                .font(BE.eyebrow)
                .foregroundStyle(.secondary)

            ForEach(games) { record in
                gameVideoCard(record)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func gameVideoCard(_ record: GameVideoRecord) -> some View {
        VStack(spacing: 0) {
            if let url = record.resolvedURL() {
                VideoThumbnailView(url: url, height: 190)
            } else {
                ZStack {
                    Color.black.opacity(0.05)
                    Image(systemName: "film.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .frame(height: 100)
            }

            VStack(spacing: BE.Space.s) {
                HStack {
                    Text(String(format: localization.localized("game.number"), record.gameNumber))
                        .font(BE.eyebrow)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(record.scoreA) – \(record.scoreB)")
                        .font(.subheadline.weight(.semibold))
                    if record.duration > 0 {
                        Text(GameVideoSection.durationLabel(record.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                gameVideoActions(record)
            }
            .padding(BE.Space.m)
        }
        .background(.ultraThinMaterial)
        .clipShape(BE.card(16))
    }

    @ViewBuilder
    private func gameVideoActions(_ record: GameVideoRecord) -> some View {
        let available = record.resolvedURL() != nil
        HStack(spacing: BE.Space.s) {
            NavigationLink {
                RallyLabelingView(record: record, matchID: match.id)
            } label: {
                Label(localization.localized("footage.labelRallies"),
                      systemImage: "checkmark.rectangle.stack")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .disabled(!available)

            analysisAction(record)

            Menu {
                Button {
                    editingRecord = record
                } label: {
                    Label(record.clipRef == nil ? "Create Highlight" : "Edit Highlight",
                          systemImage: "scissors")
                }
                Button {
                    if SubscriptionManager.shared.isPremium {
                        runHighlightShare(for: record)
                    } else {
                        showPaywall = true
                    }
                } label: {
                    Label("Share Highlight", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
            }
            .disabled(!available)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func analysisAction(_ record: GameVideoRecord) -> some View {
        if analysis.analyzingStem == record.videoStem, let progress = analysis.progress {
            ProgressView(value: Double(progress.completed),
                         total: Double(max(1, progress.total)))
                .frame(width: 60)
        } else if analysis.doneStem == record.videoStem {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Button {
                if let url = record.resolvedURL() {
                    analysis.start(url: url, stem: record.videoStem)
                }
            } label: {
                Label(localization.localized("footage.analyze"),
                      systemImage: "waveform.badge.magnifyingglass")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .disabled(record.resolvedURL() == nil || analysis.analyzingStem != nil)
        }
    }

    /// Same behavior as FootageDetailView's share flow: export the trimmed
    /// clip when one exists, otherwise share the whole game video.
    private func runHighlightShare(for record: GameVideoRecord) {
        guard let url = record.resolvedURL() else { return }
        guard let clip = record.clipRef else {
            highlightShareURL = ShareableURL(url: url)
            return
        }
        Task {
            if let outURL = try? await HighlightExporter.exportTrimmed(
                sourceURL: url, clip: clip
            ) {
                await MainActor.run { highlightShareURL = ShareableURL(url: outURL) }
            } else {
                await MainActor.run { highlightShareURL = ShareableURL(url: url) }
            }
        }
    }

    // MARK: - Computed

    private var playerNamesText: String {
        let isDoubles = match.format == "doubles" || match.format == "mixed"
        if isDoubles {
            let teamA = [match.playerAName, match.playerA2Name]
                .compactMap { $0 }.joined(separator: " & ")
            let teamB = [match.playerBName, match.playerB2Name]
                .compactMap { $0 }.joined(separator: " & ")
            return "\(teamA.isEmpty ? "Team A" : teamA) vs \(teamB.isEmpty ? "Team B" : teamB)"
        }
        return "\(match.playerAName ?? "Player 1") vs \(match.playerBName ?? "Player 2")"
    }

    private var formatBadge: String {
        let base: String
        switch match.format {
        case "doubles": base = localization.localized("setup.doubles")
        case "mixed": base = localization.localized("setup.mixed")
        default: base = localization.localized("setup.singles")
        }
        switch match.scoringSystemRaw {
        case "threeByFifteen": return "\(base) · 3×15"
        case "custom":
            if let data = match.customRulesJSON,
               let rules = try? JSONDecoder().decode(ScoringRules.self, from: data) {
                return "\(base) · " + String(format: localization.localized("setup.customDetail"), rules.pointsToWin, rules.gamesToWin)
            }
            return "\(base) · Custom"
        default: return base
        }
    }

    private var matchDuration: String? {
        guard let end = match.endedAt else { return nil }
        let seconds = Int(end.timeIntervalSince(match.startedAt))
        let minutes = seconds / 60
        if minutes < 1 { return "<1 min" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

// MARK: - Clip playback helpers (restructure PR 2)

private struct ShareableURL: Identifiable {
    let url: URL
    var id: String { url.path }
}

private struct PlayableClip: Identifiable {
    let id: UUID              // GameVideoRecord.id
    let url: URL
    let startTime: TimeInterval
    let endTime: TimeInterval
}

/// Plays a saved highlight directly as a time range into the game video —
/// no export needed. Seeks to the clip start and stops at the clip end via
/// forwardPlaybackEndTime (the HighlightClipEditorView preview pattern).
private struct ClipPlayerSheet: View {
    let url: URL
    let startTime: TimeInterval
    let endTime: TimeInterval

    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .task {
                let newPlayer = AVPlayer(url: url)
                newPlayer.currentItem?.forwardPlaybackEndTime =
                    CMTime(seconds: endTime, preferredTimescale: 600)
                await newPlayer.seek(to: CMTime(seconds: startTime, preferredTimescale: 600),
                                     toleranceBefore: .zero, toleranceAfter: .zero)
                player = newPlayer
                newPlayer.play()
            }
    }
}
