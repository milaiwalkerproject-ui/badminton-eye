import XCTest
@testable import BadmintonEye

final class OnboardingViewTests: XCTestCase {
    func testOnboardingLocalizationKeysExist() {
        let keys = [
            "onboarding.page1.title", "onboarding.page1.description",
            "onboarding.page2.title", "onboarding.page2.description",
            "onboarding.page3.title", "onboarding.page3.description",
            "onboarding.getStarted", "common.skip",
        ]
        for key in keys {
            let value = NSLocalizedString(key, bundle: Bundle.main, comment: "")
            XCTAssertNotEqual(value, key, "Key '\(key)' not found in Localizable.strings")
            XCTAssertFalse(value.isEmpty, "Key '\(key)' resolves to empty string")
        }
    }

    @MainActor
    func testOnboardingDefaultsNotCompleted() {
        // Fresh app should show onboarding
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "hasCompletedOnboarding")
        let hasCompleted = defaults.bool(forKey: "hasCompletedOnboarding")
        XCTAssertFalse(hasCompleted)
    }
}
