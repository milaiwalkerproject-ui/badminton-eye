@preconcurrency import AVFoundation
import Foundation

// MARK: - GameRecordingService

/// Owns the live `AVCaptureSession` for an in-progress match. Its sole job
/// is to feed an injected `CircularFrameBuffer` with recent frames so the
/// rally-end auto-suggest pipeline (`TrajectoryRallySuggestor`) has
/// something to analyse.
///
/// The session is exposed via `captureSession` so the SwiftUI camera
/// preview (`LiveCameraPreview`) can attach its `AVCaptureVideoPreviewLayer`
/// to the **same** session — running two `AVCaptureSession`s on the same
/// back camera causes severe lag and one of them silently fails.
///
/// Beyond feeding the ring buffer, the service records the **full length of
/// each game** to `Application Support/Footage/` (the Footage feature).
/// Rather than re-adding an `AVCaptureMovieFileOutput` (which can't reliably
/// coexist with the `AVCaptureVideoDataOutput` we depend on), the same
/// data-output sample buffers are appended to a long-running `AVAssetWriter`
/// (`FootageWriter`) on `sampleQueue`. The audio capture and Photos-library
/// save removed in 2026-05-21 are NOT restored — Footage owns its files for
/// the later highlight pipeline.
///
/// **Simulator safety**: in the Simulator the service skips
/// `AVCaptureSession` setup and behaves as a no-op so the rest of the app
/// stays functional during development.
@MainActor
final class GameRecordingService: NSObject {

    // MARK: - State

    /// `true` while the capture session is actively running. Read-only
    /// from outside; mutated only on the main actor.
    private(set) var isRecording: Bool = false

    /// Set when camera authorisation was denied so the UI can surface it.
    private(set) var permissionDenied: Bool = false

    /// Non-fatal error description (e.g. session config failure).
    private(set) var recordingError: String?

    /// The live `AVCaptureSession`. `nil` until `startMatchRecording()`
    /// has finished configuring and started it. The owning view model
    /// republishes this as an `@Observable` property so SwiftUI can
    /// attach the preview layer — keeping `@Observable` out of this
    /// `NSObject` + AVFoundation-delegate class avoids macro/runtime
    /// surprises with the strict-concurrency / Observation cocktail.
    private(set) var captureSession: AVCaptureSession?

    // MARK: - Public injection points

    /// Rolling-window buffer fed by the video data output. The
    /// AVFoundation sample-buffer callback runs on `sampleQueue`, not the
    /// main actor; `CircularFrameBuffer` is `@unchecked Sendable` and
    /// internally locked, so cross-actor access is safe.
    nonisolated let frameBuffer: CircularFrameBuffer?

    // MARK: - Init

    init(frameBuffer: CircularFrameBuffer? = nil) {
        self.frameBuffer = frameBuffer
        super.init()
    }

    // MARK: - Private

    private var videoDataOutput: AVCaptureVideoDataOutput?
    private let sampleQueue = DispatchQueue(
        label: "com.badmintoneye.GameRecordingService.sample",
        qos: .userInitiated
    )

    /// Frame counter for the sample-buffer delegate. We forward only
    /// every `frameStride`-th frame to the buffer (so ~5 fps from a
    /// 30 fps source). Combined with the buffer's short capacity this
    /// keeps the retained `CVPixelBuffer` count well under iOS's
    /// camera-pool ceiling (~15) — retaining more stalls the preview
    /// because the camera can't allocate new pool buffers to write into.
    /// Touched only on `sampleQueue`.
    private let frameStride: Int = 6
    nonisolated(unsafe) private var frameCounter: Int = 0

    /// Per-game full-length recorder. Created on `startGameRecording`,
    /// detached + finalised on `finishCurrentGameRecording`. Touched only
    /// on `sampleQueue` (the delegate appends to it; start/finish hop onto
    /// the same queue), so the `nonisolated(unsafe)` access stays serial.
    nonisolated(unsafe) private var footageWriter: FootageWriter?

    // MARK: - Simulator detection

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Public API

    /// Requests camera authorisation then starts the capture session.
    /// Call this when the match transitions to the **active** state.
    func startMatchRecording() async {
        guard !isRecording else { return }

        if isSimulator {
            isRecording = true
            return
        }

        let granted = await requestCameraAuthorization()
        guard granted else {
            permissionDenied = true
            return
        }

        let session: AVCaptureSession
        do {
            session = try configureSession()
        } catch {
            recordingError = error.localizedDescription
            return
        }

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak session] in
                session?.startRunning()
                continuation.resume()
            }
        }

        captureSession = session
        isRecording = true
    }

    /// Stops the capture session. Call on match end / abandon / background.
    func stopMatchRecording() async {
        guard isRecording else { return }

        if isSimulator {
            isRecording = false
            return
        }

        let session = captureSession
        captureSession = nil
        isRecording = false
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [weak session] in
                session?.stopRunning()
                continuation.resume()
            }
        }
    }

    // MARK: - Per-game footage recording

    /// Begins recording the current game's full-length video to
    /// `fileName` inside `Application Support/Footage/`. No-op in the
    /// Simulator or if the footage directory is unavailable — the caller
    /// then persists a `GameVideoRecord` with an empty `fileName`.
    func startGameRecording(fileName: String) {
        guard !isSimulator,
              let dir = GameVideoRecord.footageDirectory() else { return }
        let url = dir.appendingPathComponent(fileName)
        // Replace any stale file at this path (e.g. a re-recorded game).
        try? FileManager.default.removeItem(at: url)
        sampleQueue.async { [weak self] in
            self?.footageWriter = FootageWriter(outputURL: url)
        }
    }

    /// Finalises the in-flight game recording. Returns `true` if a
    /// playable file with at least one frame was written. Safe to call
    /// when nothing is recording (returns `false`).
    func finishCurrentGameRecording() async -> Bool {
        guard !isSimulator else { return false }
        return await withCheckedContinuation { continuation in
            sampleQueue.async { [weak self] in
                // Detach first so the delegate stops appending, then
                // finalise the detached writer off-queue.
                let writer = self?.footageWriter
                self?.footageWriter = nil
                guard let writer else {
                    continuation.resume(returning: false)
                    return
                }
                Task {
                    let url = await writer.finish()
                    continuation.resume(returning: url != nil)
                }
            }
        }
    }

    // MARK: - Private helpers

    private func configureSession() throws -> AVCaptureSession {
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        guard let videoDevice = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput) else {
            session.commitConfiguration()
            throw RecordingError.cameraUnavailable
        }
        session.addInput(videoInput)

        // Video data output → frame buffer. This is the only output we
        // attach — no movie file, no audio, no Photos save.
        if frameBuffer != nil {
            let dataOutput = AVCaptureVideoDataOutput()
            dataOutput.alwaysDiscardsLateVideoFrames = true
            dataOutput.setSampleBufferDelegate(self, queue: sampleQueue)
            if session.canAddOutput(dataOutput) {
                session.addOutput(dataOutput)
                videoDataOutput = dataOutput
            }
        }

        session.commitConfiguration()
        return session
    }

    private func requestCameraAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension GameRecordingService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Full-length footage gets every frame (the writer encodes and
        // releases them, so it doesn't pin the camera pool the way the
        // ring buffer would). Runs first so it isn't gated by the stride.
        footageWriter?.append(sampleBuffer)

        // Stride: only forward every Nth frame to the ring buffer so we
        // don't retain a full camera-rate stream of HD pixel buffers.
        // Counter is only touched on `sampleQueue`, so the
        // nonisolated(unsafe) access is serial in practice.
        frameCounter &+= 1
        guard frameCounter % frameStride == 0 else { return }
        frameBuffer?.append(sampleBuffer)
    }
}

// MARK: - FootageWriter

/// Writes one game's full-length video to disk via `AVAssetWriter`, fed
/// sample-by-sample from the capture delegate. Every method runs on the
/// owning service's `sampleQueue` (appends) except `finish()`, which is
/// only called after the writer has been detached from that queue — so no
/// two callers ever touch it concurrently. `@unchecked Sendable` encodes
/// that single-threaded contract.
private final class FootageWriter: @unchecked Sendable {
    let outputURL: URL
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var finished = false
    private var framesAppended = 0

    init(outputURL: URL) { self.outputURL = outputURL }

    /// Appends one captured frame. Lazily creates the underlying writer
    /// from the first frame's dimensions. Drops frames if the input isn't
    /// ready — live capture must never block the sample queue.
    func append(_ sampleBuffer: CMSampleBuffer) {
        guard !finished else { return }
        if writer == nil { _ = setup(with: sampleBuffer) }
        guard let writer, let input, writer.status == .writing,
              input.isReadyForMoreMediaData else { return }
        if input.append(sampleBuffer) {
            framesAppended &+= 1
        }
    }

    private func setup(with sampleBuffer: CMSampleBuffer) -> Bool {
        guard let fmt = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return false
        }
        let dims = CMVideoFormatDescriptionGetDimensions(fmt)
        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        else { return false }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(dims.width),
            AVVideoHeightKey: Int(dims.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { return false }
        writer.add(input)
        guard writer.startWriting() else { return false }
        writer.startSession(
            atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        )
        self.writer = writer
        self.input = input
        return true
    }

    /// Marks the writer finished and flushes the file. Returns the output
    /// URL when a non-empty file completed; `nil` otherwise. Must be called
    /// only after the writer has been detached from the sample queue.
    func finish() async -> URL? {
        guard !finished else { return nil }
        finished = true
        guard let writer, let input, writer.status == .writing else { return nil }
        input.markAsFinished()
        await writer.finishWriting()
        return (writer.status == .completed && framesAppended > 0) ? outputURL : nil
    }
}

// MARK: - Error types

extension GameRecordingService {
    enum RecordingError: LocalizedError {
        case cameraUnavailable

        var errorDescription: String? {
            switch self {
            case .cameraUnavailable:
                return "Camera is not available on this device."
            }
        }
    }
}
