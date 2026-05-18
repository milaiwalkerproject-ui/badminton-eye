import XCTest
import CoreML
import CoreVideo
@testable import BadmintonEye

/// Sanity check that the bundled TrackNetV3.mlpackage compiles into a
/// loadable .mlmodelc and runs a forward pass without crashing. Does not
/// validate accuracy — that lives in offline Python eval.
final class TrackNetShuttleDetectorTests: XCTestCase {

    func testModelLoadsFromBundle() throws {
        let detector = TrackNetShuttleDetector()
        XCTAssertNoThrow(try detector.loadModelIfNeeded())
    }

    func testForwardPassWithDummyInput() async throws {
        let detector = TrackNetShuttleDetector()
        let frames = (0..<TrackNetConstants.frameWindow).map { _ in makeBlackFrame() }
        let background = makeBlackFrame()

        let observations = try await detector.detect(
            frames: frames,
            background: background
        )

        XCTAssertEqual(observations.count, TrackNetConstants.frameWindow)
        // Black input → no shuttle. Expect all `position == nil` and
        // confidences below threshold.
        for obs in observations {
            XCTAssertNil(obs.position)
            XCTAssertLessThan(obs.confidence, TrackNetConstants.detectionThreshold)
        }
    }

    // MARK: - Helpers

    /// 288x512 BGRA black frame.
    private func makeBlackFrame() -> CVPixelBuffer {
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: TrackNetConstants.inputWidth,
            kCVPixelBufferHeightKey: TrackNetConstants.inputHeight
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            TrackNetConstants.inputWidth,
            TrackNetConstants.inputHeight,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pb
        )
        return pb!
    }
}
