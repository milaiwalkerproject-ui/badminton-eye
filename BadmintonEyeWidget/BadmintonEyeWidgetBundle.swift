import WidgetKit
import SwiftUI

/// The WidgetBundle entry point for the BadmintonEyeWidget extension.
///
/// To wire this extension into the Xcode project:
/// 1. File > New > Target > Widget Extension, name it "BadmintonEyeWidget".
/// 2. Add the App Group capability "group.com.badmintoneye.shared" to both the
///    main app target and this extension target.
/// 3. Remove the auto-generated widget stub and replace with the files in this directory.
@main
struct BadmintonEyeWidgetBundle: WidgetBundle {
    var body: some Widget {
        LiveScoreWidget()
        WinRateSummaryWidget()
    }
}
