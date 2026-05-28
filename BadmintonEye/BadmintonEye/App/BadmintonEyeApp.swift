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

    /// The SwiftData container is created lazily *after* first paint.
    ///
    /// Opening the on-disk store (and validating/migrating the schema across
    /// four model types) is synchronous, main-thread work that previously ran
    /// inside `App.init()` — which blocks the very first frame on *every* cold
    /// launch. Profiling the launch path showed this store-open dominated the
    /// felt lag (managers are inert in free mode, the leftover-match cleanup is
    /// already a deferred one-shot fetch, and there is no model/asset load at
    /// startup). We now show a lightweight splash immediately and build the
    /// container on a background actor, attaching it once ready.
    @State private var container: ModelContainer?

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    ContentView()
                        .modelContainer(container)
                } else {
                    LaunchPlaceholderView()
                }
            }
            .alert("Storage Unavailable", isPresented: $showStorageError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(
                    "Your data could not be loaded from persistent storage " +
                    "and will not be saved this session.\n\n\(storageErrorMessage)"
                )
            }
            .task {
                guard container == nil else { return }
                let result = await Self.makeContainer()
                container = result.container
                if let message = result.errorMessage {
                    storageErrorMessage = message
                    showStorageError = true
                }
            }
        }
    }

    /// Builds the `ModelContainer` off the main thread. SwiftData's
    /// `ModelContainer` is `Sendable`, so we hop it back to the caller (the
    /// main actor) once the store is open.
    private static func makeContainer() async -> (container: ModelContainer, errorMessage: String?) {
        await Task.detached(priority: .userInitiated) {
            let isSignedIn = AuthManager.shared.isSignedIn
            let useCloudKit = isSignedIn && !AppMode.freeAppleIDMode
            let config: ModelConfiguration = useCloudKit
                ? ModelConfiguration(cloudKitDatabase: .automatic)
                : ModelConfiguration()

            do {
                let container = try ModelContainer(
                    for: PersistedMatch.self, Player.self, CalibrationProfile.self,
                    GameVideoRecord.self,
                    configurations: config
                )
                return (container, nil)
            } catch let primaryError {
                // Primary store failed — fall back to an in-memory container so
                // the app never crashes, and surface a friendly alert.
                let fallbackConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                if let fallback = try? ModelContainer(
                    for: PersistedMatch.self, Player.self, CalibrationProfile.self,
                    GameVideoRecord.self,
                    configurations: fallbackConfig
                ) {
                    return (fallback, primaryError.localizedDescription)
                }
                // In-memory creation cannot fail for valid schema; guard anyway.
                fatalError("Unable to create in-memory ModelContainer: \(primaryError)")
            }
        }.value
    }
}

/// Minimal splash shown for the brief window between first paint and the
/// SwiftData store finishing opening on a background task.
private struct LaunchPlaceholderView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "sportscourt")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.tint)
                ProgressView()
            }
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass

    // NOTE: intentionally NO top-level `@Query` here. A reactive query at the
    // root re-runs `ContentView.body` — rebuilding the ENTIRE TabView /
    // NavigationSplitView tree — on every SwiftData save anywhere in the app
    // (scoring a point, writing footage records, abandoning a match). That
    // showed up as launch + tab-switch lag. The one leftover-match cleanup we
    // need at launch is a one-shot fetch in `.onAppear` instead.

    @State private var restoredViewModel: LiveMatchViewModel?
    @State private var hasCheckedRestore = false
    /// Presents the standalone video-import / Hawk-Eye challenge flow
    /// (`ChallengeVideoView`) from the Matches tab. This restores a top-level
    /// entry point for importing a clip from the photo library — previously the
    /// only way to reach the importer was the premium challenge button inside a
    /// live match.
    @State private var showVideoImport = false

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
                            Button {
                                showVideoImport = true
                            } label: {
                                Label("Import Video", systemImage: "square.and.arrow.down.on.square")
                            }
                        }
                        Section("Players") {
                            NavigationLink {
                                PlayerListView()
                            } label: {
                                Label("Player List", systemImage: "person.2")
                            }
                        }
                        Section("Footage") {
                            NavigationLink {
                                FootageView()
                            } label: {
                                Label("Footage", systemImage: "film.stack")
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
                                ToolbarItem(placement: .topBarLeading) {
                                    Button {
                                        showVideoImport = true
                                    } label: {
                                        Image(systemName: "square.and.arrow.down.on.square")
                                    }
                                    .accessibilityLabel("Import video")
                                }
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
                        FootageView()
                    }
                    .tabItem {
                        Label("Footage", systemImage: "film.stack")
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
            // MVP: skip crash-recovery auto-resume. Mark any leftover
            // in-progress matches as abandoned so they don't fight startup
            // performance (SwiftData notifications, Watch sync, etc.) and
            // so the user lands on the home tabs every launch. We can
            // reintroduce a proper "Resume in-progress match?" prompt
            // post-MVP if needed.
            if !hasCheckedRestore {
                hasCheckedRestore = true
                let descriptor = FetchDescriptor<PersistedMatch>(
                    predicate: #Predicate { !$0.isComplete && !$0.isAbandoned }
                )
                if let leftovers = try? modelContext.fetch(descriptor), !leftovers.isEmpty {
                    for match in leftovers {
                        match.isAbandoned = true
                        match.endedAt = Date()
                    }
                    try? modelContext.save()
                }
            }
            if !AppMode.freeAppleIDMode {
                WatchSyncManager.shared.activate()
                AuthManager.shared.checkAuthState()
            }
            // Prewarm SwiftData @Query caches so first-time tab switches
            // don't pay cold-fetch cost on screen. Runs on the main
            // actor (ModelContext is main-actor-isolated) after a tiny
            // delay so it doesn't block first paint.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                _ = try? modelContext.fetch(FetchDescriptor<PersistedMatch>())
                _ = try? modelContext.fetch(FetchDescriptor<Player>())
            }
        }
        // Standalone video-import / Hawk-Eye challenge entry point, shared by
        // both the iPhone TabView and the iPad sidebar.
        .sheet(isPresented: $showVideoImport) {
            ChallengeVideoView()
        }
    }

}
