import SwiftUI
import SwiftData
import PhotosUI

/// Matches tab home (restructure PR 3): a hero "Start Match" button above the
/// date-grouped history. The query also surfaces abandoned matches that have
/// footage (own section) so their videos stay reachable once the Footage tab
/// retires in PR 5. Filter pushed into SQL per the launch-perf convention.
///
/// Restructure PR 5: the Footage tab is retired, so this screen also owns the
/// photo-library footage import (wave 1 Phase 4) and lists imported videos in
/// a trailing section.
struct MatchHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<PersistedMatch> { match in
            match.isComplete ||
            (match.isAbandoned && (match.gameVideos?.contains { !$0.fileName.isEmpty } ?? false))
        },
        sort: \PersistedMatch.startedAt,
        order: .reverse
    )
    private var matches: [PersistedMatch]

    // Imported (photo-library) videos — standalone records with no match.
    // Relocated from the retired Footage tab; leaf-table SQL predicate per
    // the launch-perf convention.
    @Query(
        filter: #Predicate<GameVideoRecord> { record in
            record.match == nil && !record.fileName.isEmpty
        },
        sort: \GameVideoRecord.startedAt,
        order: .reverse
    )
    private var importedVideos: [GameVideoRecord]

    @State private var showDeleteConfirmation = false
    @State private var matchToDelete: PersistedMatch?
    @State private var showVideoImport = false
    @State private var localization = LocalizationManager.shared

    // Photo-library import into Footage (wave 1 Phase 4, relocated from the
    // retired Footage tab).
    @State private var footageImportItem: PhotosPickerItem?
    @State private var isImportingFootage = false
    @State private var footageImportError: String?

    var body: some View {
        Group {
            if matches.isEmpty && importedVideos.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    heroHeader
                    matchList
                        .scrollContentBackground(.hidden)
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle(localization.localized("history.title"))
        .sheet(isPresented: $showVideoImport) {
            ChallengeVideoView()
        }
        .onChange(of: footageImportItem) { _, item in
            guard let item else { return }
            isImportingFootage = true
            Task {
                let errorMessage = await FootageImporter.importVideo(
                    item, modelContext: modelContext
                )
                isImportingFootage = false
                footageImportItem = nil
                footageImportError = errorMessage
            }
        }
        .alert("Import failed", isPresented: .constant(footageImportError != nil)) {
            Button("OK") { footageImportError = nil }
        } message: {
            Text(footageImportError ?? "")
        }
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

    // MARK: - Hero header (restructure PR 3)

    private var heroHeader: some View {
        VStack(spacing: BE.Space.s) {
            NavigationLink {
                MatchSetupView()
            } label: {
                HStack(spacing: BE.Space.s) {
                    Image(systemName: "play.fill")
                        .font(.title3)
                    Text(localization.localized("home.startMatch"))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .opacity(0.7)
                }
                .foregroundStyle(.white)
                .padding(BE.Space.m)
                .background(BE.card(16).fill(Color.accentColor))
                .shadow(color: Color.accentColor.opacity(0.25), radius: 10, y: 4)
            }

            Menu {
                importMenuItems
            } label: {
                Group {
                    if isImportingFootage {
                        ProgressView()
                    } else {
                        Label(localization.localized("home.importVideo"),
                              systemImage: "square.and.arrow.down.on.square")
                    }
                }
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(BE.card(12).fill(Color(.secondarySystemGroupedBackground)))
            }
            .buttonStyle(.plain)
            .disabled(isImportingFootage)
        }
        .padding(.horizontal, BE.Space.m)
        .padding(.top, BE.Space.s)
    }

    /// Shared menu content for the hero and empty-state import entry points:
    /// photo-library import into Footage (analyzable/labelable, wave 1) plus
    /// the Hawk Eye in/out challenge flow.
    private var importMenuItems: some View {
        // Hoisted: PhotosPicker's label closure is nonisolated in the
        // iOS 18.5 SDK, so it can't touch the main-actor LocalizationManager.
        let importTitle = localization.localized("footage.importToFootage")
        let challengeTitle = localization.localized("hawkeye.challenge")
        return Group {
            PhotosPicker(selection: $footageImportItem, matching: .videos) {
                Label(importTitle, systemImage: "square.and.arrow.down.on.square")
            }
            Button {
                showVideoImport = true
            } label: {
                Label(challengeTitle, systemImage: "eye")
            }
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
            // With the Footage tab retired, this is the only import entry
            // point when there's nothing to list yet.
            Menu {
                importMenuItems
            } label: {
                if isImportingFootage {
                    ProgressView()
                } else {
                    Label(localization.localized("home.importVideo"),
                          systemImage: "square.and.arrow.down.on.square")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                }
            }
            .disabled(isImportingFootage)
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

            // Photo-library imports (no owning match) — trailing section,
            // relocated from the retired Footage tab.
            if !importedVideos.isEmpty {
                Section(localization.localized("footage.imported.section")) {
                    ForEach(importedVideos) { record in
                        NavigationLink {
                            ImportedFootageDetailView(record: record)
                        } label: {
                            Label {
                                Text(record.startedAt, style: .date)
                            } icon: {
                                Image(systemName: "square.and.arrow.down.on.square")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Match Row

    private func matchRow(_ match: PersistedMatch) -> some View {
        HStack(spacing: BE.Space.m) {
            // Vertical accent stripe — winner-tinted.
            // Self-sizes to the row's intrinsic height (driven by the text columns)
            // instead of greedily demanding infinite height, which previously
            // distorted the HStack's width distribution.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accentColor(for: match))
                .frame(width: 3)
                .frame(maxHeight: .infinity)
                .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: BE.Space.xs) {
                Text(playerNamesText(for: match))
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.85)

                HStack(spacing: BE.Space.s) {
                    Text(formatBadge(for: match))
                        .font(BE.eyebrow)
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous).fill(Color(.tertiarySystemFill))
                        )

                    if let winner = winnerName(for: match) {
                        HStack(spacing: 3) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 9))
                            Text(winner)
                                .font(.system(.caption, design: .rounded).weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .foregroundStyle(.secondary)
                        // Truncate the winner name (rather than the format badge)
                        // when horizontal space is tight.
                        .layoutPriority(-1)
                    }
                }
            }
            // Leading column may shrink, but should win the width contest over
            // the trailing score column so names stay readable.
            .layoutPriority(1)

            Spacer(minLength: BE.Space.s)

            VStack(alignment: .trailing, spacing: 2) {
                Text(gameScoresText(for: match))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(match.startedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            // Keep the score column at its natural width so the score line never
            // wraps onto a second line.
            .fixedSize(horizontal: true, vertical: false)
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
        var abandoned: [PersistedMatch] = []

        for match in matches {
            // Abandoned matches (surfaced only when they carry footage) get
            // their own trailing section instead of polluting the date groups.
            if match.isAbandoned && !match.isComplete {
                abandoned.append(match)
                continue
            }
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
        if !abandoned.isEmpty {
            sections.append(MatchSection(title: localization.localized("history.abandoned"),
                                         matches: abandoned))
        }
        return sections
    }
}

// MARK: - Photo-library import (wave 1 Phase 4)

/// Loads a picked photo-library video, validates it, and files it as an
/// imported `GameVideoRecord` (no owning match) so it shows up in the
/// imported-videos section, analyzable and labelable. Shared by the home
/// screen and the retired `FootageView` so the copy/validate/cleanup steps
/// live in one place.
@MainActor
enum FootageImporter {
    /// Returns a user-facing error message, or nil on success.
    static func importVideo(
        _ item: PhotosPickerItem,
        modelContext: ModelContext
    ) async -> String? {
        do {
            guard let video = try await item.loadTransferable(type: ImportedVideo.self) else {
                throw VideoImportError.unsupportedItem
            }
            try ImportedVideo.validate(url: video.url)
            let record = try GameVideoRecord.makeImported(copyingFrom: video.url)
            modelContext.insert(record)
            try? modelContext.save()
            try? FileManager.default.removeItem(at: video.url)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
