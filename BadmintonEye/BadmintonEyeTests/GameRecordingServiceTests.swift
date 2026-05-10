@testable import BadmintonEye
import XCTest

// MARK: - GameRecordingServiceTests

/// Unit tests for GameRecordingService.
///
/// All tests run in the simulator — actual AVCaptureSession + PHPhotoLibrary
/// calls are gated behind `#if targetEnvironment(simulator)` in the service,
/// so tests verify state transitions without touching hardware.
@MainActor
final class GameRecordingServiceTests: XCTestCase {

    // MARK: - Setup

    private var sut: GameRecordingService!

    override func setUp() {
        super.setUp()
        sut = GameRecordingService()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Initial state

    func test_initialState_isNotRecording() {
        XCTAssertFalse(sut.isRecording)
    }

    func test_initialState_permissionNotDenied() {
        XCTAssertFalse(sut.permissionDenied)
    }

    func test_initialState_noLastRecordingURL() {
        XCTAssertNil(sut.lastRecordingURL)
    }

    func test_initialState_noRecordingError() {
        XCTAssertNil(sut.recordingError)
    }

    // MARK: - Simulator start recording

    func test_startMatchRecording_onSimulator_setsIsRecordingTrue() async {
        await sut.startMatchRecording()
        // On simulator the service sets isRecording = true to allow REC badge display
        XCTAssertTrue(sut.isRecording)
    }

    func test_startMatchRecording_onSimulator_noPermissionDenied() async {
        await sut.startMatchRecording()
        XCTAssertFalse(sut.permissionDenied)
    }

    func test_startMatchRecording_whenAlreadyRecording_isIdempotent() async {
        await sut.startMatchRecording()
        XCTAssertTrue(sut.isRecording)
        // Second call must not crash and must leave isRecording = true
        await sut.startMatchRecording()
        XCTAssertTrue(sut.isRecording)
    }

    // MARK: - Simulator stop recording

    func test_stopMatchRecording_onSimulator_setsIsRecordingFalse() async {
        await sut.startMatchRecording()
        XCTAssertTrue(sut.isRecording)
        await sut.stopMatchRecording()
        XCTAssertFalse(sut.isRecording)
    }

    func test_stopMatchRecording_whenNotRecording_isIdempotent() async {
        // Must not crash when called without a prior start
        await sut.stopMatchRecording()
        XCTAssertFalse(sut.isRecording)
    }

    // MARK: - Start → Stop → Start cycle

    func test_canRestartRecordingAfterStop() async {
        await sut.startMatchRecording()
        await sut.stopMatchRecording()
        await sut.startMatchRecording()
        XCTAssertTrue(sut.isRecording)
    }

    // MARK: - Error type coverage

    func test_recordingError_cameraUnavailable_hasDescription() {
        let error = GameRecordingService.RecordingError.cameraUnavailable
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    func test_recordingError_outputUnavailable_hasDescription() {
        let error = GameRecordingService.RecordingError.outputUnavailable
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    func test_recordingError_cameraUnavailable_differFromOutputUnavailable() {
        let a = GameRecordingService.RecordingError.cameraUnavailable.errorDescription
        let b = GameRecordingService.RecordingError.outputUnavailable.errorDescription
        XCTAssertNotEqual(a, b)
    }
}
