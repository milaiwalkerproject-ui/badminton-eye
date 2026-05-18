import SwiftUI
import SwiftData

struct MatchHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<PersistedMatch> { $0.isComplete },
        sort: \PersistedMatch.startedAt,
        order: .reverse
    )
    private var completedMatches: [PersistedMatch]

    @State private var showDeleteConfirmation = false
    @State private var matchToDelete: PersistedMatch?
    @State private var localization = LocalizationManager.shared

    var body: some View {
        Group {
            if completedMatches.isEmpty {
                emptyState
            } else {
                matchList
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle(localization.localized("history.title"))
        .alert("Delete Match?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let match = matchToDelete {
                    modelContext.delete(match)
                    matchToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) {
                matchToDelete = nil
            }
        } message: {
            Text("This match will be permanently removed.")
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: BE.Space.l) {
            Spacer()
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [BE.TeamA.top.opacity(0.15), BE.TeamB.top.opacity(0.12)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 120, height: 120)
                Image(systemName: "sportscourt")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.tint)
            }
            VStack(spacing: 6) {
                Text(localization.localized("history.noMatches"))
                    .font(BE.displayTitle)
                Text("Start your first match to see results here.")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BE.Space.l)
            }
            NavigationLink {
                MatchSetupView()
            } label: {
                Label("New Match", systemImage: "plus")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .padding(.horizontal, BE.Space.l)
                    .padding(.vertical, 14)
                    .background(BE.card(14).fill(Color.accentColor))
                    .foregroundStyle(.white)
                    .shadow(color: Color.accentColor.opacity(0.25), radius: 10, y: 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    private var matchList: some View {
        List {
            let grouped = groupedMatches
            ForEach(grouped, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.matches) { match in
                        NavigationLink {
                            MatchDetailView(match: match)
                        } label: {
                            matchRow(match)
                        }
                    }
                    .onDelete { offsets in
                        if let first = offsets.first {
                            matchToDelete = section.matches[first]
                            showDeleteConfirmation = true
                        }
                    }
                }
            }
        }
    }

    // MARK: - Match Row

    private func matchRow(_ match: PersistedMatch) -> some View {
        HStack(spacing: BE.Space.m) {
            // Vertical accent stripe — winner-tinted
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accentColor(for: match))
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text(playerNamesText(for: match))
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: BE.Space.s) {
                    Text(formatBadge(for: match))
                        .font(BE.eyebrow)
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous).fill(Color(.tertiarySystemFill))
                        )

                    if let winner = winnerName(for: match) {
                        HStack(spacing: 3) {
                            Image(systemName: "trophy.fill").font(.system(size: 9))
                            Text(winner)
                                .font(.system(.caption, design: .rounded).weight(.medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: BE.Space.s)

            VStack(alignment: .trailing, spacing: 2) {
                Text(gameScoresText(for: match))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Text(match.startedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }

    private func accentColor(for match: PersistedMatch) -> Color {
        switch match.winnerSide {
        case "sideA": return BE.TeamA.top
        case "sideB": return BE.TeamB.top
        default:      return Color(.tertiarySystemFill)
        }
    }

    // MARK: - Helpers

    private func playerNamesText(for match: PersistedMatch) -> String {
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

    private func gameScoresText(for match: PersistedMatch) -> String {
        var scores: [String] = []
        scores.append("\(match.game1ScoreA)-\(match.game1ScoreB)")
        if let g2a = match.game2ScoreA, let g2b = match.game2ScoreB {
            scores.append("\(g2a)-\(g2b)")
        }
        if let g3a = match.game3ScoreA, let g3b = match.game3ScoreB {
            scores.append("\(g3a)-\(g3b)")
        }
        return scores.joined(separator: ", ")
    }

    private func formatBadge(for match: PersistedMatch) -> String {
        switch match.format {
        case "doubles": return "Doubles"
        case "mixed": return "Mixed"
        default: return "Singles"
        }
    }

    private func winnerName(for match: PersistedMatch) -> String? {
        guard let side = match.winnerSide else { return nil }
        if side == "sideA" {
            return match.playerAName ?? "Team A"
        } else {
            return match.playerBName ?? "Team B"
        }
    }

    // MARK: - Date Grouping

    private struct MatchSection {
        let title: String
        let matches: [PersistedMatch]
    }

    private var groupedMatches: [MatchSection] {
        let calendar = Calendar.current
        var today: [PersistedMatch] = []
        var yesterday: [PersistedMatch] = []
        var thisWeek: [PersistedMatch] = []
        var older: [PersistedMatch] = []

        for match in completedMatches {
            let date = match.startedAt
            if calendar.isDateInToday(date) {
                today.append(match)
            } else if calendar.isDateInYesterday(date) {
                yesterday.append(match)
            } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
                thisWeek.append(match)
            } else {
                older.append(match)
            }
        }

        var sections: [MatchSection] = []
        if !today.isEmpty { sections.append(MatchSection(title: "Today", matches: today)) }
        if !yesterday.isEmpty { sections.append(MatchSection(title: "Yesterday", matches: yesterday)) }
        if !thisWeek.isEmpty { sections.append(MatchSection(title: "This Week", matches: thisWeek)) }
        if !older.isEmpty { sections.append(MatchSection(title: "Older", matches: older)) }
        return sections
    }
}
