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
/// The full-match movie file output, audio capture, and Photos library
/// save were removed in 2026-05-21 — they added significant overhead and
/// weren't consumed anywhere in the MVP. The Footage feature, when it
/// lands, will record to `Application Support/Footage/` via a separate
/// path.
///
/// **Simulator safety**: in the Simulator the service skips
/// `AVCaptureSession` setup and behaves as a no-op so the rest of the app
/// stays functional during development.
@MainActor
@Observable
final class GameRecordingService: NSObject {

    // MARK: - Observable state

    /// `true` while the capture session is actively running.
    private(set) var isRecording: Bool = false

    /// Set when camera authorisation was denied so the UI can surface it.
    private(set) var permissionDenied: Bool = false

    /// Non-fatal error description (e.g. session config failure).
    private(set) var recordingError: String?

    /// The live `AVCaptureSession`. `nil` until `startMatchRecording()`
    /// has finished configuring and started it. `LiveCameraPreview`
    /// observes this and re-attaches its preview layer when it becomes
    /// non-nil.
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
        frameBuffer?.append(sampleBuffer)
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
