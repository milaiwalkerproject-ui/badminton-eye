// ImportedVideoTests.swift
// Unit tests for the streamed photo-library video import helpers:
// copy-to-temp behavior (extension handling, source preserved, unique
// destinations) and the non-empty-file validation gate that must pass
// before a video URL is handed to the Challenge review screen.

import XCTest
@testable import BadmintonEye

final class ImportedVideoTests: XCTestCase {

    private var sourceURL: URL!

    override func setUpWithError() throws {
        sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImportedVideoTests_\(UUID().uuidString)")
            .appendingPathExtension("mov")
        try Data([0x00, 0x01, 0x02, 0x03]).write(to: sourceURL)
    }

    override func tearDownWithError() throws {
        if let sourceURL {
            try? FileManager.default.removeItem(at: sourceURL)
        }
    }

    // MARK: - copyToUniqueTemporaryURL

    func test_copy_createsFileWithSameContents() throws {
        let copied = try ImportedVideo.copyToUniqueTemporaryURL(from: sourceURL)
        defer { try? FileManager.default.removeItem(at: copied) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: copied.path))
        XCTAssertEqual(try Data(contentsOf: copied), try Data(contentsOf: sourceURL))
    }

    func test_copy_preservesSourceExtension() throws {
        let copied = try ImportedVideo.copyToUniqueTemporaryURL(from: sourceURL)
        defer { try? FileManager.default.removeItem(at: copied) }

        XCTAssertEqual(copied.pathExtension, "mov")
    }

    func test_copy_fallsBackToMovExtensionWhenSourceHasNone() throws {
        let bare = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImportedVideoTests_noext_\(UUID().uuidString)")
        try Data([0xFF]).write(to: bare)
        defer { try? FileManager.default.removeItem(at: bare) }

        let copied = try ImportedVideo.copyToUniqueTemporaryURL(from: bare)
        defer { try? FileManager.default.removeItem(at: copied) }

        XCTAssertEqual(copied.pathExtension, "mov")
    }

    func test_copy_producesUniqueDestinations() throws {
        let first = try ImportedVideo.copyToUniqueTemporaryURL(from: sourceURL)
        let second = try ImportedVideo.copyToUniqueTemporaryURL(from: sourceURL)
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        XCTAssertNotEqual(first, second)
    }

    func test_copy_doesNotDeleteSource() throws {
        let copied = try ImportedVideo.copyToUniqueTemporaryURL(from: sourceURL)
        defer { try? FileManager.default.removeItem(at: copied) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    func test_copy_throwsWhenSourceMissing() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImportedVideoTests_missing_\(UUID().uuidString).mov")

        XCTAssertThrowsError(try ImportedVideo.copyToUniqueTemporaryURL(from: missing))
    }

    // MARK: - validate

    func test_validate_passesForNonEmptyFile() throws {
        XCTAssertNoThrow(try ImportedVideo.validate(url: sourceURL))
    }

    func test_validate_throwsEmptyFileForZeroByteFile() throws {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImportedVideoTests_empty_\(UUID().uuidString).mov")
        try Data().write(to: empty)
        defer { try? FileManager.default.removeItem(at: empty) }

        XCTAssertThrowsError(try ImportedVideo.validate(url: empty)) { error in
            guard case VideoImportError.emptyFile = error else {
                return XCTFail("Expected .emptyFile, got \(error)")
            }
        }
    }

    func test_validate_throwsEmptyFileForMissingFile() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImportedVideoTests_missing_\(UUID().uuidString).mov")

        XCTAssertThrowsError(try ImportedVideo.validate(url: missing)) { error in
            guard case VideoImportError.emptyFile = error else {
                return XCTFail("Expected .emptyFile, got \(error)")
            }
        }
    }
}
