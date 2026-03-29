import SwiftUI
import AVFoundation
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
struct CourtCalibrationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var captureSession = AVCaptureSession()
    @State private var corners: [CGPoint] = []
    @State private var venueName: String = ""
    @State private var isSessionRunning = false
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

    // MARK: - Camera Session

    private func startSession() {
        guard !isSessionRunning else { return }
        captureSession.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input) else {
            return
        }
        captureSession.addInput(input)

        let localSession = captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            localSession.startRunning()
            Task { @MainActor in
                isSessionRunning = true
            }
        }
    }

    private func stopSession() {
        guard isSessionRunning else { return }
        let localSession = captureSession
        DispatchQueue.global(qos: .userInitiated).async {
            localSession.stopRunning()
        }
        isSessionRunning = false
    }

    // MARK: - Save

    private func saveCalibration() {
        let profile = CalibrationProfile()
        profile.venueName = venueName.trimmingCharacters(in: .whitespaces)
        profile.setCorners(corners, imageSize: viewSize)
        modelContext.insert(profile)
        try? modelContext.save()
        stopSession()
        dismiss()
    }
}
