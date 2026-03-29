import SwiftUI
import SwiftData

@main
struct BadmintonEyeApp: App {
    @State private var authManager = AuthManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(makeModelContainer())
    }

    private func makeModelContainer() -> ModelContainer {
        let config: ModelConfiguration
        if authManager.isSignedIn {
            config = ModelConfiguration(
                cloudKitDatabase: .automatic
            )
        } else {
            config = ModelConfiguration()
        }
        return try! ModelContainer(
            for: PersistedMatch.self, Player.self,
            configurations: config
        )
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
                // iPad: sidebar with Matches + Players + Settings sections
                NavigationSplitView {
                    List {
                        Section("Matches") {
                            NavigationLink {
                                MatchHistoryView()
                            } label: {
                                Label("Match History", systemImage: "sportscourt")
                            }
                            NavigationLink {
                                MatchSetupView()
                            } label: {
                                Label("New Match", systemImage: "plus.circle")
                            }
                        }
                        Section("Players") {
                            NavigationLink {
                                PlayerListView()
                            } label: {
                                Label("Player List", systemImage: "person.2")
                            }
                        }
                        Section("Settings") {
                            NavigationLink {
                                SettingsView()
                            } label: {
                                Label("Settings", systemImage: "gear")
                            }
                        }
                    }
                    .navigationTitle("Badminton Eye")
                } detail: {
                    MatchSetupView()
                }
            } else {
                // iPhone: TabView with Matches, Players, and Settings tabs
                TabView {
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
                    .tabItem {
                        Label("Matches", systemImage: "sportscourt")
                    }

                    NavigationStack {
                        PlayerListView()
                    }
                    .tabItem {
                        Label("Players", systemImage: "person.2")
                    }

                    NavigationStack {
                        SettingsView()
                    }
                    .tabItem {
                        Label("Settings", systemImage: "gear")
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
            AuthManager.shared.checkAuthState()
        }
    }
}
