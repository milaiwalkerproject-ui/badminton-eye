import AVFoundation
import Foundation

/// Manages AVFoundation video capture for Hawk Eye challenge clips.
/// Instantiated per challenge (NOT a singleton).
@Observable
final class VideoCaptureManager: NSObject, @unchecked Sendable {

    // MARK: - Published State

    var capturedVideoURL: URL?
    var isRecording: Bool = false
    var recordingDuration: TimeInterval = 0

    // MARK: - Private

    private var captureSession: AVCaptureSession?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var recordingTimer: Timer?
    private let maxDuration: TimeInterval = 10.0

    // MARK: - Recording

    /// Configures AVCaptureSession with back camera and starts recording to a temp file.
    func startRecording() {
        guard !isRecording else { return }

        let session = AVCaptureSession()
        session.sessionPreset = .hd1280x720

        // Video input from back camera
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput) else {
            return
        }
        session.addInput(videoInput)

        // Movie file output
        let output = AVCaptureMovieFileOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        captureSession = session
        movieOutput = output

        // Start session on background queue
        let localSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            localSession.startRunning()
        }

        // Start recording to temp file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        output.startRecording(to: tempURL, recordingDelegate: self)
        isRecording = true
        recordingDuration = 0

        // Timer to update duration and auto-stop at max
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.recordingDuration += 0.1
                if self.recordingDuration >= self.maxDuration {
                    self.stopRecording()
                }
            }
        }
        recordingTimer = timer
    }

    /// Stops the current recording session.
    func stopRecording() {
        guard isRecording else { return }
        recordingTimer?.invalidate()
        recordingTimer = nil
        movieOutput?.stopRecording()
        isRecording = false

        let localSession = captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            localSession?.stopRunning()
        }
    }

    /// Removes the temp video file from disk.
    func cleanup() {
        if let url = capturedVideoURL {
            try? FileManager.default.removeItem(at: url)
            capturedVideoURL = nil
        }
        recordingDuration = 0
    }

    // MARK: - Session Access (for preview layer)

    /// The active capture session, available for camera preview layers.
    var session: AVCaptureSession? {
        captureSession
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension VideoCaptureManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: (any Error)?
    ) {
        Task { @MainActor in
            if error == nil {
                self.capturedVideoURL = outputFileURL
            }
        }
    }
}
