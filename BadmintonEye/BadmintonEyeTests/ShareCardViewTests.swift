import XCTest
@testable import BadmintonEye

final class ShareCardViewTests: XCTestCase {
    func testShareCardLocalizationKeysExist() {
        let keys = [
            "share.format.singles", "share.format.doubles", "share.format.mixed",
            "share.wins", "share.vs", "share.title", "share.shareImage",
        ]
        for key in keys {
            let value = NSLocalizedString(key, bundle: Bundle.main, comment: "")
            XCTAssertNotEqual(value, key, "Key '\(key)' not found in Localizable.strings")
        }
    }
}
