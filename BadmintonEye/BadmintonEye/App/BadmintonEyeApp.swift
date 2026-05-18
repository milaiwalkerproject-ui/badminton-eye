import SwiftUI
import SwiftData

/// Global app-mode flags. Lets the same codebase build either as the full
/// paid-developer-account product (Watch, CloudKit, Sign in with Apple, IAP,
/// Live Activity) or as a free-Apple-ID prototype with those capabilities
/// inert. Flip `freeAppleIDMode` to `false` to restore full functionality.
/// See `.planning/PROJECT.md` → "Current Milestone: MVP".
enum AppMode {
    static let freeAppleIDMode: Bool = true
}

@main
struct BadmintonEyeApp: App {
    @State private var authManager = AuthManager.shared
    @State private var subscriptionManager = SubscriptionManager.shared
    @State private var showStorageError = false
    @State private var storageErrorMessage = ""

    private let container: ModelContainer

    init() {
        let isSignedIn = AuthManager.shared.isSignedIn
        let useCloudKit = isSignedIn && !AppMode.freeAppleIDMode
        let config: ModelConfiguration = useCloudKit
            ? ModelConfiguration(cloudKitDatabase: .automatic)
            : ModelConfiguration()

        do {
            container = try ModelContainer(
                for: PersistedMatch.self, Player.self, CalibrationProfile.self,
                configurations: config
            )
        } catch let primaryError {
            // Primary store failed — fall back to an in-memory container so the
            // app never crashes, and surface a friendly alert to the user.
            let fallbackConfig = ModelConfiguration(isStoredInMemoryOnly: true)
            if let fallback = try? ModelContainer(
                for: PersistedMatch.self, Player.self, CalibrationProfile.self,
                configurations: fallbackConfig
            ) {
                container = fallback
                _showStorageError = State(initialValue: true)
                _storageErrorMessage = State(initialValue: primaryError.localizedDescription)
            } else {
                // In-memory creation cannot fail for valid schema; guard anyway.
                fatalError("Unable to create in-memory ModelContainer: \(primaryError)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .alert("Storage Unavailable", isPresented: $showStorageError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(
                        "Your data could not be loaded from persistent storage " +
                        "and will not be saved this session.\n\n\(storageErrorMessage)"
                    )
                }
        }
        .modelContainer(container)
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
                        Section("Stats") {
                            NavigationLink {
                                StatsView()
                            } label: {
                                Label("Statistics", systemImage: "chart.bar")
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
                        StatsView()
                    }
                    .tabItem {
                        Label("Stats", systemImage: "chart.bar")
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
            if !AppMode.freeAppleIDMode {
                WatchSyncManager.shared.activate()
                AuthManager.shared.checkAuthState()
            }
        }
    }

}
