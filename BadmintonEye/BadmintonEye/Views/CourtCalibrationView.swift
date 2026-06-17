import SwiftUI
@preconcurrency import AVFoundation
import SwiftData

// MARK: - Camera Preview (UIViewRepresentable)

/// A `UIView` whose backing layer *is* the `AVCaptureVideoPreviewLayer`.
///
/// Using `layerClass` (instead of adding the preview layer as a sublayer) is
/// the key to a visible preview: the backing layer is created and laid out by
/// UIKit, so it automatically tracks the view's bounds. There is no separate
/// sublayer left at `.zero` when the view is sized after `updateUIView` runs —
/// which is exactly what produced the black-but-running-camera symptom.
final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // Safe: `layerClass` guarantees the backing layer's type.
        layer as! AVCaptureVideoPreviewLayer
    }

    var session: AVCaptureSession? {
        get { previewLayer.session }
        set { previewLayer.session = newValue }
    }
}

/// Wraps `AVCaptureVideoPreviewLayer` in a SwiftUI view, attaching the *running*
/// capture session so frames are rendered on screen.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// Called once with the backing preview layer so the calibration view can
    /// convert detected capture-device points into on-screen points
    /// (rotation- and gravity-aware) via `layerPointConverted(fromCaptureDevicePoint:)`.
    var onMakeLayer: ((AVCaptureVideoPreviewLayer) -> Void)? = nil

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.session = session
        onMakeLayer?(view.previewLayer)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Re-point at the live session if SwiftUI recreates the representable
        // with a different instance; layout/sizing is handled by UIKit.
        if uiView.session !== session {
            uiView.session = session
        }
    }
}

// MARK: - Preview-layer holder

/// Reference box that carries the `AVCaptureVideoPreviewLayer` out of the
/// `UIViewRepresentable` so SwiftUI code can call `layerPointConverted(...)`.
/// Held as `@State` so it survives view-body recreation.
final class PreviewLayerBox {
    var layer: AVCaptureVideoPreviewLayer?
}

// MARK: - Frame grabber

/// Keeps the most recent camera frame from an `AVCaptureVideoDataOutput` so a
/// one-shot court detection can run on demand. Thread-safe: the delegate
/// callback fires on a capture queue while `latestFrame()` is read on the main
/// actor.
final class CourtFrameGrabber: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lock.lock(); latest = buffer; lock.unlock()
    }

    func latestFrame() -> CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        return latest
    }
}

// MARK: - Court Calibration View

/// Full-screen camera overlay where user taps 4 court corners to calibrate.
/// On confirm, hands back an unsaved `CalibrationProfile` via `onConfirm`;
/// the caller decides whether to insert it into a model context and on which
/// match it lives. Calling `dismiss()` without confirming returns nothing.
struct CourtCalibrationView: View {
    @Environment(\.dismiss) private var dismiss

    /// Caller receives the populated (but not yet inserted) profile.
    var onConfirm: (CalibrationProfile) -> Void

    @State private var captureSession = AVCaptureSession()
    @State private var corners: [CGPoint] = []
    @State private var venueName: String = ""
    @State private var isSessionRunning = false
    @State private var permissionDenied = false
    @State private var cameraUnavailable = false
    @State private var viewSize: CGSize = .zero

    // Auto-detect (Option 5) state.
    @State private var localization = LocalizationManager.shared
    @State private var previewLayerBox = PreviewLayerBox()
    @State private var frameGrabber = CourtFrameGrabber()
    @State private var courtDetector: CourtDetecting = VisionCourtDetector()
    @State private var isDetecting = false
    @State private var detectionMessage: String?

    private let cornerLabels = ["Top-Left", "Top-Right", "Bottom-Right", "Bottom-Left"]

    private func localized(_ key: String) -> String { localization.localized(key) }

    var body: some View {
        ZStack {
            // Camera preview
            if isSessionRunning {
                CameraPreviewView(session: captureSession, onMakeLayer: { previewLayerBox.layer = $0 })
                    .ignoresSafeArea()
                    .overlay(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear { viewSize = geo.size }
                                .onChange(of: geo.size) { _, newSize in viewSize = newSize }
                                .contentShape(Rectangle())
                                .onTapGesture { location in
                                    handleTap(at: location)
                                }
                        }
                    )
            } else if permissionDenied {
                cameraDeniedView
            } else if cameraUnavailable {
                cameraUnavailableView
            } else {
                Color.black.ignoresSafeArea()
                ProgressView("Starting camera...")
                    .foregroundStyle(.white)
            }

            // Corner dots overlay
            ForEach(Array(corners.enumerated()), id: \.offset) { index, point in
                ZStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 20, height: 20)
                    Text("\(index + 1)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                }
                .position(point)
            }

            // Instructions and controls
            VStack {
                // Instruction banner
                Text(instructionText)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.top, 60)

                // Auto-detect (Option 5): let Vision find the court instead of
                // tapping all four corners. Only offered until 4 corners exist.
                if corners.count < 4 {
                    VStack(spacing: 8) {
                        Button {
                            autoDetectCourt()
                        } label: {
                            Label(
                                isDetecting
                                    ? localized("calibration.autoDetect.detecting")
                                    : localized("calibration.autoDetect.button"),
                                systemImage: "viewfinder.circle.fill"
                            )
                            .font(.subheadline.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(isDetecting)

                        if let detectionMessage {
                            Text(detectionMessage)
                                .font(.footnote)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .padding(.horizontal, 24)
                        }
                    }
                    .padding(.top, 10)
                }

                Spacer()

                // Bottom controls (after 4 taps)
                if corners.count == 4 {
                    VStack(spacing: 12) {
                        TextField("Venue name", text: $venueName)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal, 40)

                        HStack(spacing: 20) {
                            Button("Recalibrate") {
                                corners.removeAll()
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)

                            Button("Confirm") {
                                saveCalibration()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(venueName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }

            // Close button
            VStack {
                HStack {
                    Button {
                        stopSession()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }
        }
        .onAppear { startSession() }
        .onDisappear { stopSession() }
    }

    // MARK: - Instruction Text

    private var instructionText: String {
        if corners.count < 4 {
            let next = cornerLabels[corners.count]
            return "Tap court corner \(corners.count + 1)/4: \(next)"
        }
        return "All corners marked. Enter venue name and confirm."
    }

    // MARK: - Tap Handling

    private func handleTap(at location: CGPoint) {
        guard corners.count < 4 else { return }
        corners.append(location)
    }

    // MARK: - Auto-detect (Option 5)

    /// Runs the on-device court detector on the most recent camera frame and,
    /// on success, fills in all four corners (same order as the manual taps) so
    /// the user can Confirm or Recalibrate. Degrades gracefully when the camera
    /// isn't ready yet or no court is found — the manual tap flow always works.
    private func autoDetectCourt() {
        guard !isDetecting else { return }
        guard let buffer = frameGrabber.latestFrame(), let layer = previewLayerBox.layer else {
            detectionMessage = localized("calibration.autoDetect.noFrame")
            return
        }
        isDetecting = true
        detectionMessage = nil
        let detector = courtDetector
        Task {
            let detected = await detector.detectCourt(in: buffer)
            await MainActor.run {
                isDetecting = false
                guard let detected else {
                    detectionMessage = localized("calibration.autoDetect.notFound")
                    return
                }
                // Map normalized capture-device points → on-screen points via
                // the preview layer (handles rotation + aspect-fill cropping),
                // matching where a manual tap would have landed.
                corners = detected.corners.map {
                    layer.layerPointConverted(fromCaptureDevicePoint: $0)
                }
                detectionMessage = nil
            }
        }
    }

    // MARK: - Permission / unavailable states

    private var cameraDeniedView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "video.slash.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.white.opacity(0.8))
                Text("Camera Access Needed")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("Calibration needs the camera to see the court. Enable camera access for Badminton Eye in Settings.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 40)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var cameraUnavailableView: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.white.opacity(0.8))
                Text("Camera Unavailable")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("No back camera is available on this device.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 40)
            }
        }
    }

    // MARK: - Camera Session

    /// Requests camera authorisation (showing the system prompt on first run)
    /// and only then configures + starts the session. Without this gate the
    /// session was started with an input that never delivered frames on a
    /// `.notDetermined`/`.denied` device, leaving a permanently black preview.
    private func startSession() {
        guard !isSessionRunning, !permissionDenied else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        configureAndStart()
                    } else {
                        permissionDenied = true
                    }
                }
            }
        default:
            permissionDenied = true
        }
    }

    /// Configures the capture device and starts the session off the main
    /// thread. `addInput`/`canAddInput` touch the device and can be slow, so
    /// they run on a background queue; only the resulting flags hop back to
    /// the main actor to drive the SwiftUI preview.
    private func configureAndStart() {
        guard !isSessionRunning else { return }
        let session = captureSession
        let grabber = frameGrabber
        DispatchQueue.global(qos: .userInitiated).async {
            session.beginConfiguration()
            session.sessionPreset = .hd1280x720

            guard session.inputs.isEmpty,
                  let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                session.commitConfiguration()
                Task { @MainActor in cameraUnavailable = true }
                return
            }
            session.addInput(input)

            // Tap frames for the one-shot court auto-detector. The preview
            // connection is unaffected; this output only feeds Vision.
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(
                grabber, queue: DispatchQueue(label: "court.frame.grabber")
            )
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }

            session.commitConfiguration()

            session.startRunning()
            Task { @MainActor in
                isSessionRunning = true
            }
        }
    }

    private func stopSession() {
        let session = captureSession
        isSessionRunning = false
        DispatchQueue.global(qos: .userInitiated).async {
            if session.isRunning { session.stopRunning() }
        }
    }

    // MARK: - Save

    private func saveCalibration() {
        let profile = CalibrationProfile()
        profile.venueName = venueName.trimmingCharacters(in: .whitespaces)
        profile.setCorners(corners, imageSize: viewSize)
        stopSession()
        onConfirm(profile)
        dismiss()
    }
}
