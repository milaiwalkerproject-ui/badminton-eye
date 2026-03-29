import SwiftUI
import SwiftData

@main
struct BadmintonEyeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: PersistedMatch.self)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query(
        filter: #Predicate<PersistedMatch> { !$0.isComplete && !$0.isAbandoned },
        sort: \PersistedMatch.startedAt,
        order: .reverse
    )
    private var inProgressMatches: [PersistedMatch]

    @Query(
        filter: #Predicate<PersistedMatch> { $0.isComplete || $0.isAbandoned },
        sort: \PersistedMatch.startedAt,
        order: .reverse
    )
    private var completedMatches: [PersistedMatch]

    @State private var restoredViewModel: LiveMatchViewModel?
    @State private var hasCheckedRestore = false

    var body: some View {
        Group {
            if sizeClass == .regular {
                // iPad: sidebar + detail
                NavigationSplitView {
                    matchListSidebar
                } detail: {
                    if let vm = restoredViewModel {
                        LiveMatchView(viewModel: vm, onMatchEnd: {
                            restoredViewModel = nil
                        })
                    } else {
                        MatchSetupView()
                    }
                }
            } else {
                // iPhone: existing NavigationStack
                NavigationStack {
                    if let vm = restoredViewModel {
                        LiveMatchView(viewModel: vm, onMatchEnd: {
                            restoredViewModel = nil
                        })
                    } else {
                        MatchSetupView()
                    }
                }
            }
        }
        .onAppear {
            if !hasCheckedRestore, let match = inProgressMatches.first {
                restoredViewModel = LiveMatchViewModel.restoreFromPersistedMatch(
                    match,
                    modelContext: modelContext
                )
                hasCheckedRestore = true
            }
            WatchSyncManager.shared.activate()
        }
    }

    private var matchListSidebar: some View {
        List {
            if !inProgressMatches.isEmpty {
                Section("In Progress") {
                    ForEach(inProgressMatches) { match in
                        matchRow(match)
                    }
                }
            }

            if !completedMatches.isEmpty {
                Section("Completed") {
                    ForEach(completedMatches) { match in
                        matchRow(match)
                    }
                }
            }

            if inProgressMatches.isEmpty && completedMatches.isEmpty {
                ContentUnavailableView(
                    "No Matches",
                    systemImage: "sportscourt",
                    description: Text("Start a new match to begin")
                )
            }
        }
        .navigationTitle("Matches")
    }

    private func matchRow(_ match: PersistedMatch) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(match.playerAName ?? "Player 1") vs \(match.playerBName ?? "Player 2")")
                .font(.headline)
            Text(match.format.capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)
            if match.isComplete {
                Text("\(match.game1ScoreA)-\(match.game1ScoreB)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
