@preconcurrency import AVFoundation
import Foundation

/// Manages simultaneous dual-camera capture via AVCaptureMultiCamSession.
/// Primary camera runs at highest available multi-cam FPS (up to 120fps).
/// Secondary camera runs at 60fps for angle diversity.
/// Falls back to single-camera 240fps when multi-cam is unsupported or throttled.
@Observable
final class MultiCamCaptureManager: NSObject, @unchecked Sendable {

    // MARK: - State

    private(set) var isMultiCamAvailable: Bool = false
    private(set) var isDualCamActive: Bool = false
    private(set) var primaryFPS: Double = 0
    private(set) var secondaryFPS: Double = 0
    private(set) var thermalState: ProcessInfo.ThermalState = .nominal

    // MARK: - Buffers

    let primaryBuffer: CircularFrameBuffer
    let secondaryBuffer: CircularFrameBuffer

    // MARK: - Session

    private var multiCamSession: AVCaptureMultiCamSession?
    private let primaryQueue = DispatchQueue(label: "com.badmintoneye.multicam.primary")
    private let secondaryQueue = DispatchQueue(label: "com.badmintoneye.multicam.secondary")

    // MARK: - Init

    override init() {
        self.primaryBuffer = CircularFrameBuffer(capacity: 10.0)
        self.secondaryBuffer = CircularFrameBuffer(capacity: 10.0)
        super.init()
        primaryQueue.setSpecific(key: primaryQueueKey, value: true)

        isMultiCamAvailable = AVCaptureMultiCamSession.isMultiCamSupported

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }

    // MARK: - Configuration

    /// Configure and start dual-camera capture. Returns false if unsupported.
    func startDualCapture() -> Bool {
        guard isMultiCamAvailable else { return false }

        let session = AVCaptureMultiCamSession()

        // Primary: wide-angle back camera
        guard let wideDevice = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back
        ) else { return false }

        // Secondary: ultra-wide back camera
        guard let ultraWideDevice = AVCaptureDevice.default(
            .builtInUltraWideCamera, for: .video, position: .back
        ) else { return false }

        do {
            // Add inputs without automatic connections
            let wideInput = try AVCaptureDeviceInput(device: wideDevice)
            guard session.canAddInput(wideInput) else { return false }
            session.addInputWithNoConnections(wideInput)

            let ultraWideInput = try AVCaptureDeviceInput(device: ultraWideDevice)
            guard session.canAddInput(ultraWideInput) else { return false }
            session.addInputWithNoConnections(ultraWideInput)

            // Primary output
            let primaryOutput = AVCaptureVideoDataOutput()
            primaryOutput.setSampleBufferDelegate(self, queue: primaryQueue)
            primaryOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
            guard session.canAddOutput(primaryOutput) else { return false }
            session.addOutputWithNoConnections(primaryOutput)

            // Connect wide camera to primary output
            guard let widePort = wideInput.ports(for: .video, sourceDeviceType: .builtInWideAngleCamera, sourceDevicePosition: .back).first else { return false }
            let primaryConnection = AVCaptureConnection(inputPorts: [widePort], output: primaryOutput)
            guard session.canAddConnection(primaryConnection) else { return false }
            session.addConnection(primaryConnection)

            // Secondary output
            let secondaryOutput = AVCaptureVideoDataOutput()
            secondaryOutput.setSampleBufferDelegate(self, queue: secondaryQueue)
            secondaryOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
            guard session.canAddOutput(secondaryOutput) else { return false }
            session.addOutputWithNoConnections(secondaryOutput)

            // Connect ultra-wide to secondary output
            guard let ultraWidePort = ultraWideInput.ports(for: .video, sourceDeviceType: .builtInUltraWideCamera, sourceDevicePosition: .back).first else { return false }
            let secondaryConnection = AVCaptureConnection(inputPorts: [ultraWidePort], output: secondaryOutput)
            guard session.canAddConnection(secondaryConnection) else { return false }
            session.addConnection(secondaryConnection)

            // Configure FPS: asymmetric (primary 120fps, secondary 60fps)
            configureAsymmetricFPS(primary: wideDevice, secondary: ultraWideDevice)

            // Check hardware cost
            guard session.hardwareCost <= 1.0 else {
                // Too expensive for this device — fall back
                return false
            }

            multiCamSession = session
            session.startRunning()
            isDualCamActive = true

            primaryFPS = 1.0 / CMTimeGetSeconds(wideDevice.activeVideoMinFrameDuration)
            secondaryFPS = 1.0 / CMTimeGetSeconds(ultraWideDevice.activeVideoMinFrameDuration)

        } catch {
            return false
        }

        return true
    }

    /// Stop dual capture and clean up.
    func stopDualCapture() {
        multiCamSession?.stopRunning()
        multiCamSession = nil
        isDualCamActive = false
        primaryBuffer.clear()
        secondaryBuffer.clear()
    }

    // MARK: - FPS Configuration

    private func configureAsymmetricFPS(primary: AVCaptureDevice, secondary: AVCaptureDevice) {
        // Primary: highest multi-cam-compatible FPS (target 120)
        configureBestFPS(for: primary, target: 120)
        // Secondary: 60fps for angle diversity
        configureBestFPS(for: secondary, target: 60)
    }

    private func configureBestFPS(for device: AVCaptureDevice, target: Double) {
        var bestFormat: AVCaptureDevice.Format?
        var bestRange: AVFrameRateRange?

        for format in device.formats {
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.width >= 1280, dims.height >= 720 else { continue }

            for range in format.videoSupportedFrameRateRanges {
                if range.maxFrameRate >= target {
                    if bestRange == nil || range.maxFrameRate < bestRange!.maxFrameRate {
                        // Prefer the format that just meets our target (not overkill)
                        bestFormat = format
                        bestRange = range
                    }
                }
            }
        }

        guard let format = bestFormat, let range = bestRange else { return }

        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            let fps = min(range.maxFrameRate, target)
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.unlockForConfiguration()
        } catch {
            // Silently continue with default FPS
        }
    }

    // MARK: - Thermal Management

    @objc private func thermalStateChanged() {
        thermalState = ProcessInfo.processInfo.thermalState

        switch thermalState {
        case .serious:
            // Reduce secondary to 30fps
            if let session = multiCamSession {
                session.beginConfiguration()
                // Secondary camera will naturally throttle
                session.commitConfiguration()
            }
        case .critical:
            // Drop to single camera
            stopDualCapture()
        default:
            break
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension MultiCamCaptureManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Route to correct buffer based on dispatch queue
        if DispatchQueue.getSpecific(key: primaryQueueKey) != nil {
            primaryBuffer.append(sampleBuffer)
        } else {
            secondaryBuffer.append(sampleBuffer)
        }
    }
}

// MARK: - Queue identification

private let primaryQueueKey = DispatchSpecificKey<Bool>()
