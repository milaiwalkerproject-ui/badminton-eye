// OnboardingFlowTests.swift
// Unit tests for the pure first-run onboarding step model (OnboardingStep)
// and the persisted completion flag (OnboardingStore). The SwiftUI view layer
// (OnboardingView) is not exercised here — only the sequencing/persistence
// logic, which must stay correct independent of the UI.

import XCTest
@testable import BadmintonEye

final class OnboardingFlowTests: XCTestCase {

    // MARK: - Step ordering

    func testStepOrderMatchesOnboardingNarrative() {
        // welcome → sign in → auto-scoring → calibration → challenge → ready
        XCTAssertEqual(
            OnboardingStep.allCases,
            [.welcome, .signIn, .autoScoring, .calibration, .challenge, .ready]
        )
    }

    func testFirstAndLastFlags() {
        XCTAssertTrue(OnboardingStep.welcome.isFirst)
        XCTAssertFalse(OnboardingStep.welcome.isLast)

        XCTAssertTrue(OnboardingStep.ready.isLast)
        XCTAssertFalse(OnboardingStep.ready.isFirst)

        // Only the welcome step is first; only ready is last.
        XCTAssertEqual(OnboardingStep.allCases.filter(\.isFirst), [.welcome])
        XCTAssertEqual(OnboardingStep.allCases.filter(\.isLast), [.ready])
    }

    // MARK: - Navigation

    func testNextNilOnlyAtEnd() {
        XCTAssertNil(OnboardingStep.ready.next)
        for step in OnboardingStep.allCases where step != .ready {
            XCTAssertNotNil(step.next, "\(step) should have a next step")
        }
    }

    func testPreviousNilOnlyAtStart() {
        XCTAssertNil(OnboardingStep.welcome.previous)
        for step in OnboardingStep.allCases where step != .welcome {
            XCTAssertNotNil(step.previous, "\(step) should have a previous step")
        }
    }

    func testForwardTraversalVisitsEveryStepInOrder() {
        var visited: [OnboardingStep] = []
        var current: OnboardingStep? = .welcome
        while let step = current {
            visited.append(step)
            current = step.next
        }
        XCTAssertEqual(visited, OnboardingStep.allCases)
    }

    func testNextThenPreviousIsIdentity() {
        for step in OnboardingStep.allCases where !step.isLast {
            XCTAssertEqual(step.next?.previous, step)
        }
    }

    // MARK: - Completion flag persistence

    func testCompletionFlagRoundTrips() {
        let key = OnboardingStore.completedKey
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertFalse(OnboardingStore.hasCompleted, "absent flag must read as not-completed")

        OnboardingStore.hasCompleted = true
        XCTAssertTrue(OnboardingStore.hasCompleted)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: key))

        OnboardingStore.hasCompleted = false
        XCTAssertFalse(OnboardingStore.hasCompleted)
    }

    func testCompletionKeyIsVersioned() {
        // The key is intentionally versioned so a future onboarding revamp can
        // re-trigger the flow by bumping the suffix.
        XCTAssertTrue(OnboardingStore.completedKey.contains("_v"))
    }
}
