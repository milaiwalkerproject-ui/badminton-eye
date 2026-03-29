import SwiftUI
import SwiftData

@main
struct BadmintonEyeApp: App {
    var body: some Scene {
        WindowGroup {
            MatchSetupView()
        }
        .modelContainer(for: PersistedMatch.self)
    }
}
