@preconcurrency import AVFoundation
import Foundation

/// Manages AVFoundation video capture for Hawk Eye challenge clips.
/// Uses delegate-based frame capture (AVCaptureVideoDataOutput) with
/// automatic format selection for the highest available FPS at 720p.
/// Instantiated per challenge (NOT a singleton).
@Observable
final class VideoCaptureManager: NSObject, @unchecked Sendable {

    // MARK: - Published State

    var capturedVideoURL: URL?
    var isRecording: Bool = false
    var recordingDuration: TimeInterval = 0

    /// Active capture frame rate (e.g. 240, 120, 60, or 30).
    var currentFPS: Double = 0

    /// Highest FPS the device supports at 720p resolution.
    var maxAvailableFPS: Double = 0

    // MARK: - Private

    private var captureSession: AVCaptureSession?
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private let circularBuffer = CircularFrameBuffer(capacity: 10.0)
    private let captureQueue = DispatchQueue(label: "com.badmintoneye.capture", qos: .userInteractive)
    private var recordingTimer: Timer?
    private let maxDuration: TimeInterval = 10.0

    // MARK: - Recording

    /// Configures AVCaptureSession with back camera at the highest available
    /// FPS and starts delegate-based frame capture into the circular buffer.
    func startRecording() {
        guard !isRecording else { return }

        let session = AVCaptureSession()
        // Do NOT set sessionPreset — activeFormat controls resolution and FPS

        // Video input from back camera
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              session.canAddInput(videoInput) else {
            return
        }
        session.addInput(videoInput)

        // Delegate-based video data output
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        captureSession = session
        videoDataOutput = output

        // Select highest FPS format at 720p
        configureHighFPSFormat(for: videoDevice)

        // Start session on background queue
        let localSession = session
        DispatchQueue.global(qos: .userInitiated).async {
            localSession.startRunning()
        }

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

    /// Stops the capture session. The circular buffer is NOT cleared here
    /// so that a challenge trigger can still flush it to disk.
    func stopRecording() {
        guard isRecording else { return }
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false

        let localSession = captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            localSession?.stopRunning()
        }
    }

    /// Flushes the circular buffer to an HEVC .mp4 on disk and sets
    /// `capturedVideoURL` to the result.
    /// - Returns: URL of the written video file.
    func saveBufferToDisk() async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        let url = try await circularBuffer.flush(
            to: tempURL,
            codec: .hevc,
            width: 1280,
            height: 720,
            fps: currentFPS > 0 ? currentFPS : 30
        )

        await MainActor.run {
            self.capturedVideoURL = url
        }

        return url
    }

    /// Removes the temp video file from disk and clears the circular buffer.
    func cleanup() {
        if let url = capturedVideoURL {
            try? FileManager.default.removeItem(at: url)
            capturedVideoURL = nil
        }
        recordingDuration = 0
        circularBuffer.clear()
    }

    // MARK: - Session Access (for preview layer)

    /// The active capture session, available for camera preview layers.
    var session: AVCaptureSession? {
        captureSession
    }

    // MARK: - Format Selection

    /// Enumerates device formats to find the highest FPS at ~720p and
    /// configures the device accordingly. Prefers 240 > 120 > 60 > 30.
    private func configureHighFPSFormat(for device: AVCaptureDevice) {
        var bestFormat: AVCaptureDevice.Format?
        var bestFPS: Double = 0

        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let width = Int(dimensions.width)
            let height = Int(dimensions.height)

            // Filter: at least 1280x720 but prefer 720p (skip 1080p+ to save bandwidth)
            guard width >= 1280, height >= 720, height <= 750 else { continue }

            // Find max FPS in this format's supported ranges
            for range in format.videoSupportedFrameRateRanges {
                let maxFPS = range.maxFrameRate
                if maxFPS > bestFPS {
                    bestFPS = maxFPS
                    bestFormat = format
                }
            }
        }

        // If no 720p-specific format found, try any format with high FPS
        if bestFormat == nil {
            for format in device.formats {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let width = Int(dimensions.width)
                let height = Int(dimensions.height)

                guard width >= 1280, height >= 720 else { continue }

                for range in format.videoSupportedFrameRateRanges {
                    let maxFPS = range.maxFrameRate
                    if maxFPS > bestFPS {
                        bestFPS = maxFPS
                        bestFormat = format
                    }
                }
            }
        }

        guard let chosenFormat = bestFormat, bestFPS > 0 else {
            // Fallback: leave default (30fps)
            currentFPS = 30
            maxAvailableFPS = 30
            return
        }

        do {
            try device.lockForConfiguration()
            device.activeFormat = chosenFormat
            let frameDuration = CMTime(value: 1, timescale: Int32(bestFPS))
            device.activeVideoMinFrameDuration = frameDuration
            device.activeVideoMaxFrameDuration = frameDuration
            device.unlockForConfiguration()

            currentFPS = bestFPS
            maxAvailableFPS = bestFPS
        } catch {
            // Configuration failed — use whatever default the device has
            currentFPS = 30
            maxAvailableFPS = 30
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension VideoCaptureManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        circularBuffer.append(sampleBuffer)
    }
}
