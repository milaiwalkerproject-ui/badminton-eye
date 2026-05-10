// PaywallViewTests.swift
// Unit tests verifying PaywallView compliance with App Store Guideline 2.3.1.
// These tests confirm that no unverifiable marketing claims are embedded in
// localization keys and that all paywall strings resolve correctly.

import XCTest
@testable import BadmintonEye

final class PaywallViewTests: XCTestCase {

    // MARK: - Unverifiable Claims Guard

    func testNoUnverifiablePlayerCountInHeadline() {
        // paywall.headline must NOT contain an unverifiable player count stat
        let headline = NSLocalizedString("paywall.headline", bundle: Bundle.main, comment: "")
        XCTAssertFalse(
            headline.contains("10,000"),
            "Paywall headline must not contain unverifiable player count claims (App Store Guideline 2.3.1)"
        )
    }

    func testNoUnverifiableRatingInStrings() {
        // No paywall key should embed the unverifiable "4.8" rating claim
        let keysToCheck = [
            "paywall.headline",
            "paywall.subtitle",
            "paywall.feature.hawkeye",
            "paywall.feature.analytics",
            "paywall.feature.replay",
            "paywall.feature.share",
            "paywall.bestValue",
            "paywall.weeklyValue",
            "paywall.subscribe",
            "paywall.cancelAnytime"
        ]
        for key in keysToCheck {
            let value = NSLocalizedString(key, bundle: Bundle.main, comment: "")
            XCTAssertFalse(
                value.contains("4.8"),
                "Paywall key '\(key)' must not contain the unverifiable rating claim '4.8'"
            )
        }
    }

    // MARK: - Localization Key Completeness

    func testPaywallHeadlineKeyExists() {
        let headline = NSLocalizedString("paywall.headline", bundle: Bundle.main, comment: "")
        XCTAssertFalse(headline.isEmpty, "paywall.headline must resolve to a non-empty string")
        XCTAssertNotEqual(
            headline, "paywall.headline",
            "paywall.headline must be defined in Localizable.strings (key must not fall back to key name)"
        )
    }

    func testPaywallSubtitleKeyExists() {
        let value = NSLocalizedString("paywall.subtitle", bundle: Bundle.main, comment: "")
        XCTAssertFalse(value.isEmpty)
        XCTAssertNotEqual(value, "paywall.subtitle")
    }

    func testPaywallFeatureKeysExist() {
        let featureKeys = [
            "paywall.feature.hawkeye",
            "paywall.feature.analytics",
            "paywall.feature.replay",
            "paywall.feature.share"
        ]
        for key in featureKeys {
            let value = NSLocalizedString(key, bundle: Bundle.main, comment: "")
            XCTAssertFalse(value.isEmpty, "\(key) must not be empty")
            XCTAssertNotEqual(value, key, "\(key) must be defined in Localizable.strings")
        }
    }

    func testPaywallActionKeysExist() {
        let actionKeys = [
            "paywall.subscribe",
            "paywall.cancelAnytime",
            "paywall.restore",
            "paywall.terms",
            "paywall.privacy"
        ]
        for key in actionKeys {
            let value = NSLocalizedString(key, bundle: Bundle.main, comment: "")
            XCTAssertFalse(value.isEmpty, "\(key) must not be empty")
            XCTAssertNotEqual(value, key, "\(key) must be defined in Localizable.strings")
        }
    }

    func testPaywallPricingSuffixKeysExist() {
        let perYear = NSLocalizedString("paywall.perYear", bundle: Bundle.main, comment: "")
        let perMonth = NSLocalizedString("paywall.perMonth", bundle: Bundle.main, comment: "")
        XCTAssertFalse(perYear.isEmpty)
        XCTAssertFalse(perMonth.isEmpty)
        XCTAssertNotEqual(perYear, "paywall.perYear")
        XCTAssertNotEqual(perMonth, "paywall.perMonth")
    }

    // MARK: - Headline Content Validation

    func testPaywallHeadlineIsNeutralClaim() {
        let headline = NSLocalizedString("paywall.headline", bundle: Bundle.main, comment: "")
        // Must not contain numeric stat claims that are unverifiable
        let forbiddenPatterns = ["10,000", "10000", "4.8", "2K", "2,000"]
        for pattern in forbiddenPatterns {
            XCTAssertFalse(
                headline.contains(pattern),
                "paywall.headline contains forbidden unverifiable claim: '\(pattern)'"
            )
        }
    }

    // MARK: - CTA Label Correctness (Guideline 2.3.1 + Bait-and-Switch guard)

    func testYearlySubscribeKeyExists() {
        let value = NSLocalizedString("paywall.subscribe.yearly", bundle: Bundle.main, comment: "")
        XCTAssertFalse(value.isEmpty, "paywall.subscribe.yearly must not be empty")
        XCTAssertNotEqual(value, "paywall.subscribe.yearly",
                          "paywall.subscribe.yearly must be defined in Localizable.strings")
    }

    func testMonthlySubscribeKeyExists() {
        let value = NSLocalizedString("paywall.subscribe.monthly", bundle: Bundle.main, comment: "")
        XCTAssertFalse(value.isEmpty, "paywall.subscribe.monthly must not be empty")
        XCTAssertNotEqual(value, "paywall.subscribe.monthly",
                          "paywall.subscribe.monthly must be defined in Localizable.strings")
    }

    func testMonthlySubscribeKeyDoesNotMentionFreeTrial() {
        // Monthly product has no introductory offer — CTA must not say "Free Trial"
        let monthly = NSLocalizedString("paywall.subscribe.monthly", bundle: Bundle.main, comment: "")
        let lowercased = monthly.lowercased()
        XCTAssertFalse(
            lowercased.contains("trial") || lowercased.contains("free"),
            "paywall.subscribe.monthly must NOT mention 'free trial' — monthly plan has no intro offer. Got: '\(monthly)'"
        )
    }

    func testYearlySubscribeKeyMentionsTrial() {
        // Yearly product has a 7-day free trial — CTA should communicate the offer
        let yearly = NSLocalizedString("paywall.subscribe.yearly", bundle: Bundle.main, comment: "")
        let lowercased = yearly.lowercased()
        XCTAssertTrue(
            lowercased.contains("trial") || lowercased.contains("free") || lowercased.contains("7"),
            "paywall.subscribe.yearly should communicate the free trial offer. Got: '\(yearly)'"
        )
    }

    func testIAPDisclaimerKeyExists() {
        let value = NSLocalizedString("paywall.iapDisclaimer", bundle: Bundle.main, comment: "")
        XCTAssertFalse(value.isEmpty, "paywall.iapDisclaimer must not be empty")
        XCTAssertNotEqual(value, "paywall.iapDisclaimer",
                          "paywall.iapDisclaimer must be defined in Localizable.strings")
    }
}
