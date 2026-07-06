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
                    GameVideoRecord.self, RallyLabel.self,
                    configurations: config
                )
                return (container, nil)
            } catch let primaryError {
                // Primary store failed — fall back to an in-memory container so
                // the app never crashes, and surface a friendly alert.
                let fallbackConfig = ModelConfiguration(isStoredInMemoryOnly: true)
                if let fallback = try? ModelContainer(
                    for: PersistedMatch.self, Player.self, CalibrationProfile.self,
                    GameVideoRecord.self, RallyLabel.self,
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
    /// Set when launch cleanup found a resumable in-progress match — drives
    /// the "Resume Match?" prompt. The match stays untouched until the user
    /// chooses Resume or Discard.
    @State private var pendingResumeID: PersistentIdentifier?
    /// Presents the standalone video-import / Hawk-Eye challenge flow
    /// (`ChallengeVideoView`) from the Matches tab. This restores a top-level
    /// entry point for importing a clip from the photo library — previously the
    /// only way to reach the importer was the premium challenge button inside a
    /// live match.
    @State private var showVideoImport = false

    /// First-run onboarding gate. While `false`, the onboarding flow is shown
    /// instead of the main app; `OnboardingView` flips it on completion/skip.
    @AppStorage(OnboardingStore.completedKey) private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            home
        } else {
            OnboardingView(onFinish: { hasCompletedOnboarding = true })
        }
    }

    @ViewBuilder private var home: some View {
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
            // Launch leftover-match pass: the NEWEST resumable in-progress
            // match is offered to the user via a "Resume Match?" prompt
            // (Resume / Discard) instead of silently vanishing — felt data
            // loss was a review trust-breaker. Any other leftovers (older
            // duplicates, undecodable state) are finalized as abandoned.
            if !hasCheckedRestore {
                hasCheckedRestore = true
                // PERF: run the leftover-match pass off the main thread.
                // Time Profiler on a cold launch (iPhone 16) showed a ~2.0s
                // SEVERE main-thread hang starting the instant ContentView
                // appeared. The dominant frames were SwiftData materialization
                // (`PersistedMatch.init(backingData:)`,
                // `-[NSSQLiteConnection fetchResultSet:usingFetchPlan:]`,
                // relationship faulting) driven by this synchronous fetch in
                // `onAppear`. Doing it in a detached background `ModelContext`
                // keeps the main thread free for first paint; only the
                // (Sendable) ID of a resumable match hops back to the main
                // actor to raise the prompt.
                let containerForCleanup = modelContext.container
                Task.detached(priority: .utility) {
                    let context = ModelContext(containerForCleanup)
                    let descriptor = FetchDescriptor<PersistedMatch>(
                        predicate: #Predicate { !$0.isComplete && !$0.isAbandoned },
                        sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
                    )
                    guard let leftovers = try? context.fetch(descriptor),
                          !leftovers.isEmpty else { return }
                    var resumeID: PersistentIdentifier?
                    let now = Date()
                    for match in leftovers {
                        if resumeID == nil,
                           MatchResumeService.isResumable(
                               isComplete: match.isComplete,
                               isAbandoned: match.isAbandoned,
                               stateJSON: match.stateJSON
                           ) {
                            resumeID = match.persistentModelID
                        } else {
                            match.isAbandoned = true
                            match.endedAt = now
                        }
                    }
                    try? context.save()
                    if let resumeID {
                        await MainActor.run { pendingResumeID = resumeID }
                    }
                }
            }
            if !AppMode.freeAppleIDMode {
                WatchSyncManager.shared.activate()
                AuthManager.shared.checkAuthState()
            }
            // NOTE: deliberately NO @Query "prewarm" fetch here. A previous
            // revision fetched ALL PersistedMatch + Player rows on the main
            // actor shortly after launch to warm caches; profiling showed that
            // just re-paid the full main-thread materialization cost for no
            // rendering benefit (each tab's own `@Query` fetches lazily, and
            // only the rows it needs, when that tab is first shown).
        }
        // Standalone video-import / Hawk-Eye challenge entry point, shared by
        // both the iPhone TabView and the iPad sidebar.
        .sheet(isPresented: $showVideoImport) {
            ChallengeVideoView()
        }
        // Resume prompt for an in-progress match persisted by a previous
        // session. The user explicitly chooses; nothing is dropped silently.
        .alert(
            "Resume Match?",
            isPresented: Binding(
                get: { pendingResumeID != nil },
                set: { if !$0 { pendingResumeID = nil } }
            )
        ) {
            Button("Resume") {
                if let id = pendingResumeID { resumeMatch(id: id) }
            }
            Button("Discard", role: .destructive) {
                if let id = pendingResumeID { discardMatch(id: id) }
            }
        } message: {
            Text("You have an unfinished match from a previous session.")
        }
    }

    /// Rebuilds the live-match view model from the persisted crash-recovery
    /// state and presents the live screen. Falls back to discarding if the
    /// state can no longer be restored.
    private func resumeMatch(id: PersistentIdentifier) {
        guard let match = modelContext.model(for: id) as? PersistedMatch,
              let vm = LiveMatchViewModel.restoreFromPersistedMatch(
                  match, modelContext: modelContext
              )
        else {
            discardMatch(id: id)
            return
        }
        restoredViewModel = vm
    }

    /// Finalizes the leftover match as abandoned (it gets an end date and the
    /// abandoned flag, same as ending a match from the live screen).
    private func discardMatch(id: PersistentIdentifier) {
        guard let match = modelContext.model(for: id) as? PersistedMatch else { return }
        match.isAbandoned = true
        match.endedAt = Date()
        try? modelContext.save()
    }
}
