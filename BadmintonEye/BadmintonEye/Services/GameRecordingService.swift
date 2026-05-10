@preconcurrency import AVFoundation
import Foundation
import Photos

// MARK: - GameRecordingService

/// Auto-starts a full-length AVCaptureMovieFileOutput recording when a match
/// begins and saves the resulting video to the user's Photos library when the
/// match ends.
///
/// **Simulator safety**: When running in the Simulator (no physical camera) the
/// service skips AVCaptureSession setup and behaves as a no-op so that the rest
/// of the app remains functional during development.
///
/// **Usage** (from LiveMatchViewModel):
/// ```swift
/// let recorder = GameRecordingService()
/// await recorder.startMatchRecording()   // call on match start
/// await recorder.stopMatchRecording()    // call on match end / app background
/// ```
///
/// **Capsule scope**: Services/GameRecordingService.swift,
///                    Services/VideoCaptureManager.swift
/// Out-of-scope wiring (Info.plist keys, LiveMatchView REC badge, LiveMatchViewModel
/// integration) is tracked in follow-up tasks.
@MainActor
@Observable
final class GameRecordingService: NSObject {

    // MARK: - Observable state

    /// `true` while the capture session is actively writing frames.
    private(set) var isRecording: Bool = false

    /// Set when a permission denial occurs so the UI can surface an alert.
    /// Mutable so the alert binding can reset it to false on dismissal.
    var permissionDenied: Bool = false

    /// URL of the most recently completed recording, available for preview.
    private(set) var lastRecordingURL: URL?

    /// Non-fatal error description (e.g. session config failure).
    private(set) var recordingError: String?

    // MARK: - Private

    private var captureSession: AVCaptureSession?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var activeOutputURL: URL?

    // MARK: - Simulator detection

    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Public API

    /// Requests camera + microphone authorisation then starts recording.
    /// Call this when the match transitions to the **active** state.
    func startMatchRecording() async {
        guard !isRecording else { return }

        if isSimulator {
            // Simulator: pretend we are recording so the REC badge shows
            isRecording = true
            return
        }

        // Check / request AVCaptureDevice permissions
        let cameraGranted = await requestCameraAuthorization()
        let micGranted    = await requestMicrophoneAuthorization()

        guard cameraGranted else {
            permissionDenied = true
            return
        }

        // Configure and start the session
        do {
            try configureSession(includeAudio: micGranted)
        } catch {
            recordingError = error.localizedDescription
            return
        }

        guard let session = captureSession, !session.isRunning else { return }

        // Start session on a background queue
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak session] in
                session?.startRunning()
                continuation.resume()
            }
        }

        beginFileOutput()
    }

    /// Stops the capture session, finalises the file, and saves it to Photos.
    /// Call this on match end or when the app moves to background.
    func stopMatchRecording() async {
        guard isRecording else { return }

        if isSimulator {
            isRecording = false
            return
        }

        // Stop writing — delegate callback fires when file is finalised
        movieFileOutput?.stopRecording()
        // Actual isRecording → false happens in delegate callback
    }

    // MARK: - Private helpers

    private func configureSession(includeAudio: Bool) throws {
        let session = AVCaptureSession()
        session.beginConfiguration()

        // Video — back camera
        guard let videoDevice = AVCaptureDevice.default(
                .builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput) else {
            throw RecordingError.cameraUnavailable
        }
        session.addInput(videoInput)

        // Audio (optional — silently omit if denied)
        if includeAudio,
           let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput  = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        // Movie file output
        let fileOutput = AVCaptureMovieFileOutput()
        guard session.canAddOutput(fileOutput) else {
            throw RecordingError.outputUnavailable
        }
        session.addOutput(fileOutput)

        session.commitConfiguration()
        captureSession = session
        movieFileOutput = fileOutput
    }

    private func beginFileOutput() {
        guard let fileOutput = movieFileOutput, !fileOutput.isRecording else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("match-\(UUID().uuidString)")
            .appendingPathExtension("mov")

        activeOutputURL = url
        fileOutput.startRecording(to: url, recordingDelegate: self)
        isRecording = true
    }

    // MARK: - Permission helpers

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

    private func requestMicrophoneAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    // MARK: - Photos save

    private func saveToPhotosLibrary(url: URL) async {
        // Request Photos add-only access if needed
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            await MainActor.run {
                self.lastRecordingURL = url
            }
        } catch {
            await MainActor.run {
                self.recordingError = "Failed to save video: \(error.localizedDescription)"
            }
        }

        // Clean up temp file regardless of outcome
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension GameRecordingService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            self.isRecording = false

            if let err = error {
                // AVFoundation may pass an error AND a usable file; check the flag
                let userInfoKey = AVErrorRecordingSuccessfullyFinishedKey
                let finished = (err as NSError).userInfo[userInfoKey] as? Bool ?? false
                if !finished {
                    self.recordingError = err.localizedDescription
                    try? FileManager.default.removeItem(at: outputFileURL)
                    return
                }
            }

            // Stop the capture session
            let localSession = self.captureSession
            DispatchQueue.global(qos: .utility).async {
                localSession?.stopRunning()
            }

            // Save to Photos
            await self.saveToPhotosLibrary(url: outputFileURL)
        }
    }
}

// MARK: - Error types

extension GameRecordingService {
    enum RecordingError: LocalizedError {
        case cameraUnavailable
        case outputUnavailable

        var errorDescription: String? {
            switch self {
            case .cameraUnavailable:
                return "Camera is not available on this device."
            case .outputUnavailable:
                return "Could not configure video file output."
            }
        }
    }
}
