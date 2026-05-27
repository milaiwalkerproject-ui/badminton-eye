import SwiftUI
@preconcurrency import AVFoundation
import SwiftData

// MARK: - Camera Preview (UIViewRepresentable)

/// Wraps AVCaptureVideoPreviewLayer in a UIView for SwiftUI.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
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

    private let cornerLabels = ["Top-Left", "Top-Right", "Bottom-Right", "Bottom-Left"]

    var body: some View {
        ZStack {
            // Camera preview
            if isSessionRunning {
                CameraPreviewView(session: captureSession)
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
