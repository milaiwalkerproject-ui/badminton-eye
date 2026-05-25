// FeaturizeGoldenTests.swift
// Verifies the Swift `ClassifierRallyScorer.featurize` port reproduces the
// python `hawkeye.train.winner_classifier.featurize` golden vectors within
// 1e-5 (Vision's FEATURIZE-PORT-SPEC.md + Fixtures/featurize_golden.json).
//
// The classifier trained on these exact 38 features; any drift in the Swift
// port would silently corrupt on-device System-2 predictions, so this locks
// the port against the fixture.

import XCTest
@testable import BadmintonEye

final class FeaturizeGoldenTests: XCTestCase {

    private struct GoldenCase {
        let name: String
        let trajectory: [(x: Double, y: Double, f: Int, vis: Bool)]
        let expected: [Double]
    }

    func testFeaturizeMatchesGoldenVectors() throws {
        let cases = try loadCases()
        XCTAssertFalse(cases.isEmpty, "golden fixture has no cases")

        for c in cases {
            let features = ClassifierRallyScorer.featurize(c.trajectory).map { Double($0) }
            XCTAssertEqual(
                features.count, c.expected.count,
                "case \(c.name): feature count \(features.count) != expected \(c.expected.count)"
            )
            for i in 0..<min(features.count, c.expected.count) {
                XCTAssertEqual(
                    features[i], c.expected[i], accuracy: 1e-5,
                    "case \(c.name): feature[\(i)] = \(features[i]), expected \(c.expected[i])"
                )
            }
        }
    }

    // MARK: - Fixture loading

    /// Loads the fixture relative to this source file (no test-bundle resource
    /// needed), so the assertion runs against the committed golden data.
    private func loadCases() throws -> [GoldenCase] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/featurize_golden.json")
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let rawCases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        return try rawCases.map { raw in
            let name = (raw["name"] as? String) ?? "?"
            let traj = try XCTUnwrap(raw["trajectory"] as? [[String: Any]])
            let expected = try XCTUnwrap(raw["expected_features"] as? [Any])
                .map { ($0 as? NSNumber)?.doubleValue ?? .nan }
            let points: [(x: Double, y: Double, f: Int, vis: Bool)] = traj.map {
                (x: ($0["x"] as? NSNumber)?.doubleValue ?? .nan,
                 y: ($0["y"] as? NSNumber)?.doubleValue ?? .nan,
                 f: ($0["f"] as? NSNumber)?.intValue ?? 0,
                 vis: ($0["vis"] as? NSNumber)?.boolValue ?? true)
            }
            return GoldenCase(name: name, trajectory: points, expected: expected)
        }
    }
}
