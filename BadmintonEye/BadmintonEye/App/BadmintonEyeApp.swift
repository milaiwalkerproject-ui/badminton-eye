import SwiftUI
import SwiftData

@main
struct BadmintonEyeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [PersistedMatch.self, Player.self])
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

    @State private var restoredViewModel: LiveMatchViewModel?
    @State private var hasCheckedRestore = false

    var body: some View {
        Group {
            if let vm = restoredViewModel {
                // Crash recovery: resume in-progress match
                NavigationStack {
                    LiveMatchView(viewModel: vm, onMatchEnd: {
                        restoredViewModel = nil
                    })
                }
            } else if sizeClass == .regular {
                // iPad: sidebar (match history) + detail
                NavigationSplitView {
                    MatchHistoryView()
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                NavigationLink {
                                    MatchSetupView()
                                } label: {
                                    Image(systemName: "plus")
                                }
                            }
                        }
                } detail: {
                    MatchSetupView()
                }
            } else {
                // iPhone: match history as root
                NavigationStack {
                    MatchHistoryView()
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                NavigationLink {
                                    MatchSetupView()
                                } label: {
                                    Image(systemName: "plus")
                                }
                            }
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
}
