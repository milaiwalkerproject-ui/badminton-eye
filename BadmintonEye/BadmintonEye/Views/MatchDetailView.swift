import SwiftUI
import UIKit
import ScoringEngine

struct MatchDetailView: View {
    let match: PersistedMatch
    @State private var showExportPicker = false
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    @State private var localization = LocalizationManager.shared

    private var decodedState: CodableMatchState? {
        guard let data = match.stateJSON else { return nil }
        return try? JSONDecoder().decode(CodableMatchState.self, from: data)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Match metadata header
                metadataSection

                // Scorecard
                if let state = decodedState {
                    decodedScorecard(state)
                    rallyAnalyticsSection(state)
                } else {
                    fallbackScorecard
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
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
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
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
