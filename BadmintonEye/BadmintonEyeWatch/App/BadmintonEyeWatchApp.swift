import SwiftUI

@main
struct BadmintonEyeWatchApp: App {
    @State private var viewModel = WatchMatchViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if viewModel.isMatchActive {
                    WatchScoringView(viewModel: viewModel)
                } else {
                    WatchWaitingView()
                }
            }
            .onAppear {
                WatchSessionManager.shared.activate()
                Task { await WorkoutManager.shared.requestAuthorization() }
            }
        }
    }
}
