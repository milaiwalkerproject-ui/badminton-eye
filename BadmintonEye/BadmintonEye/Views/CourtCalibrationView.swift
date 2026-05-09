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
///
/// Phase S3 update: after the 4th tap we synchronously run
/// `CourtDetector.calibrateAndRefine(...)` to compute the full
/// :class:`CourtCalibration` (12 keypoints + world↔image homography pair),
/// then render `CourtOverlayView` over the camera preview so the user can
/// visually confirm the projected court lines line up with the physical
/// court before tapping Confirm. On Confirm we persist via the new
/// `CalibrationProfile.apply(calibration:venueName:)` so the full
/// calibration round-trips, not just the 4 taps.
///
/// We pass `pixelBuffer: nil` to `calibrateAndRefine` for now — the
/// `CameraPreviewView` here uses `AVCaptureVideoPreviewLayer` directly and
/// does not own a `AVCaptureVideoDataOutput`. Wiring contour-snap
/// refinement requires plumbing a `CMSampleBufferDelegate` through the
/// preview layer; that is queued for the next heartbeat.
struct CourtCalibrationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var captureSession = AVCaptureSession()
    @State private var corners: [CGPoint] = []
    @State private var venueName: String = ""
    @State private var isSessionRunning = false
    @State private var viewSize: CGSize = .zero

    /// The full calibration computed from the 4 tap corners. Set after the
    /// 4th tap and cleared by "Recalibrate". When non-nil, the green court
    /// overlay is drawn on top of the camera preview.
    @State private var previewCalibration: CourtCalibration?

    /// Human-readable error displayed if `CourtDetector.calibrate(...)` fails
    /// (e.g. degenerate tap geometry that the 4-pt homography solver
    /// rejects).
    @State private var calibrationError: String?

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

            // Court line overlay (after 4 taps + successful calibration)
            if let calibration = previewCalibration {
                CourtOverlayView(
                    calibration: calibration,
                    viewSize: viewSize,
                    style: .confirm
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            // Corner dots overlay (the user's raw taps)
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
                .allowsHitTesting(false)
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
                    .multilineTextAlignment(.center)

                if let calibrationError {
                    Text(calibrationError)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.red.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(.top, 8)
                }

                Spacer()

                // Bottom controls (after 4 taps)
                if corners.count == 4 {
                    VStack(spacing: 12) {
                        if let calibration = previewCalibration {
                            Text(qualityLabel(rms: calibration.rmsReprojectionErrorPx))
                                .font(.caption2)
                                .foregroundStyle(.white)
                        }

                        TextField("Venue name", text: $venueName)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal, 40)

                        HStack(spacing: 20) {
                            Button("Recalibrate") {
                                resetCalibration()
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)

                            Button("Confirm") {
                                saveCalibration()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(
                                venueName.trimmingCharacters(in: .whitespaces).isEmpty
                                || previewCalibration == nil
                            )
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
        .onChange(of: viewSize) { oldSize, newSize in
            // If the view resizes meaningfully *after* the user has already
            // tapped corners (e.g. orientation change), the stored taps are
            // in the old coordinate system — silently recomputing would
            // project the overlay to the wrong place. Clear instead and
            // surface a recalibrate prompt.
            guard !corners.isEmpty else { return }
            let dW = abs(newSize.width - oldSize.width)
            let dH = abs(newSize.height - oldSize.height)
            // Allow tiny size jitter (~1pt) without resetting.
            if dW > 1.5 || dH > 1.5 {
                resetCalibration()
                calibrationError =
                    "View size changed (likely rotation). Re-tap court corners."
            }
        }
    }

    // MARK: - Instruction Text

    private var instructionText: String {
        if corners.count < 4 {
            let next = cornerLabels[corners.count]
            return "Tap court corner \(corners.count + 1)/4: \(next)"
        }
        if previewCalibration != nil {
            return "Confirm overlay matches the court, then enter venue name."
        }
        return "Enter venue name and confirm."
    }

    /// Human-friendly summary of how tight the 4-pt fit was.
    private func qualityLabel(rms: Double) -> String {
        if rms < 1e-6 {
            return "Calibration fit: exact (4-tap solve)"
        }
        return String(format: "Calibration fit: RMS %.2f px", rms)
    }

    // MARK: - Tap Handling

    private func handleTap(at location: CGPoint) {
        guard corners.count < 4 else { return }
        corners.append(location)
        if corners.count == 4 {
            computePreviewCalibration()
        }
    }

    private func resetCalibration() {
        corners.removeAll()
        previewCalibration = nil
        calibrationError = nil
    }

    // MARK: - Calibration Computation

    /// Synchronously compute the projected 12-keypoint calibration from the
    /// 4 tap corners. Surfaced into the UI via `previewCalibration`.
    ///
    /// The view-tap order — Top-Left, Top-Right, Bottom-Right, Bottom-Left —
    /// matches `CourtModel.calibrationTapOrder` exactly:
    ///   [back-left, back-right, short-service-right, short-service-left]
    /// so we hand the raw `corners` array straight to `calibrateAndRefine`
    /// without reordering.
    private func computePreviewCalibration() {
        guard corners.count == 4 else { return }
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        do {
            // pixelBuffer: nil → falls back to tap-only baseline calibration.
            // Hooking the contour-snap refinement requires a CMSampleBuffer
            // delegate on the preview pipeline; deferred to next heartbeat.
            let calibration = try CourtDetector.calibrateAndRefine(
                fromCornerTapsImagePx: corners,
                imageSize: viewSize,
                pixelBuffer: nil
            )
            previewCalibration = calibration
            calibrationError = nil
        } catch {
            previewCalibration = nil
            calibrationError = "Calibration failed: \(error). Re-tap the corners."
        }
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
        let trimmed = venueName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let profile = CalibrationProfile()
        if let calibration = previewCalibration {
            // v2 path — store full 12 keypoints + homography pair.
            profile.apply(calibration: calibration, venueName: trimmed)
        } else {
            // Defensive v1 fallback. In the live UI Confirm is disabled
            // when previewCalibration is nil, so this branch is only
            // hit by future callers that bypass the new gating.
            profile.venueName = trimmed
            profile.setCorners(corners, imageSize: viewSize)
        }
        modelContext.insert(profile)
        try? modelContext.save()
        stopSession()
        dismiss()
    }
}
