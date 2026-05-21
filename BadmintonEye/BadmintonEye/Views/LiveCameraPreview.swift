import SwiftUI
import UIKit
@preconcurrency import AVFoundation

/// Back-camera preview. Two modes:
///
/// 1. **External session (preferred during a live match).** Pass the
///    `AVCaptureSession` owned by `GameRecordingService` so the preview
///    layer attaches to the *same* session that's feeding the frame
///    buffer. Running two sessions on the same camera causes severe lag
///    and one silently fails — never do it.
///
/// 2. **Internal session (fallback for setup / preview screens).** When
///    `session` is nil, the view spins up its own lightweight session
///    with a single video input. Used by `CourtCalibrationView` and
///    similar pre-match screens where no recorder exists yet.
struct LiveCameraPreview: UIViewRepresentable {

    /// Optional externally-owned session. When non-nil, the preview layer
    /// attaches to it and no internal session is created.
    var session: AVCaptureSession?

    /// Content fit. Defaults to `.resizeAspectFill` so the preview looks
    /// like a viewfinder.
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoGravity = videoGravity
        view.backgroundColor = .black
        if let session {
            view.attach(externalSession: session)
        } else {
            Task { @MainActor in
                await view.startInternalSession()
            }
        }
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.videoGravity = videoGravity
        if let session {
            uiView.attach(externalSession: session)
        }
    }

    static func dismantleUIView(_ uiView: PreviewUIView, coordinator: ()) {
        uiView.stopInternalSession()
    }

    // MARK: - Backing UIView

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        private var previewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }

        /// Internal session. Created lazily on first call to
        /// `startInternalSession()` and only used when no external
        /// session is supplied.
        private let internalSession = AVCaptureSession()
        private let sessionQueue = DispatchQueue(
            label: "com.badmintoneye.LiveCameraPreview.session",
            qos: .userInitiated
        )
        private var didConfigureInternal = false
        private var isUsingExternalSession = false

        var videoGravity: AVLayerVideoGravity = .resizeAspectFill {
            didSet { previewLayer.videoGravity = videoGravity }
        }

        // MARK: External session attach

        func attach(externalSession session: AVCaptureSession) {
            // Already attached to this exact session — nothing to do.
            if previewLayer.session === session { return }

            // If we previously had our own internal session, stop it
            // before swapping in the external one.
            if !isUsingExternalSession && didConfigureInternal {
                stopInternalSession()
            }

            isUsingExternalSession = true
            previewLayer.session = session
            previewLayer.videoGravity = videoGravity
            DispatchQueue.main.async { [weak self] in
                self?.applyCurrentRotation()
            }
        }

        // MARK: Internal session lifecycle (fallback)

        @MainActor
        func startInternalSession() async {
            // If an external session was attached in the meantime, do
            // nothing — the external owner controls the lifecycle.
            if isUsingExternalSession { return }

            previewLayer.session = internalSession
            previewLayer.videoGravity = videoGravity

            let granted: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                granted = true
            case .notDetermined:
                granted = await AVCaptureDevice.requestAccess(for: .video)
            default:
                granted = false
            }

            guard granted else { return }
            startInternalCapture()
        }

        private func startInternalCapture() {
            sessionQueue.async { [weak self] in
                guard let self = self else { return }
                if self.isUsingExternalSession { return }

                if !self.didConfigureInternal {
                    self.configureInternalSessionLocked()
                    self.didConfigureInternal = true
                }

                if !self.internalSession.isRunning {
                    self.internalSession.startRunning()
                }
            }
        }

        nonisolated func stopInternalSession() {
            sessionQueue.async { [weak self] in
                guard let self = self else { return }
                if self.internalSession.isRunning {
                    self.internalSession.stopRunning()
                }
            }
        }

        // MARK: Internal session config

        private func configureInternalSessionLocked() {
            internalSession.beginConfiguration()
            internalSession.sessionPreset = .hd1280x720

            if let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .back
            ), let input = try? AVCaptureDeviceInput(device: device),
                internalSession.canAddInput(input) {
                internalSession.addInput(input)
            }

            internalSession.commitConfiguration()

            DispatchQueue.main.async { [weak self] in
                self?.applyCurrentRotation()
            }
        }

        // MARK: - Rotation handling

        private func applyCurrentRotation() {
            guard let connection = previewLayer.connection else { return }
            let angle = currentInterfaceRotationAngle()
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }

        private func currentInterfaceRotationAngle() -> CGFloat {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
            switch scene?.interfaceOrientation ?? .portrait {
            case .portrait:           return 90
            case .portraitUpsideDown: return 270
            case .landscapeLeft:      return 180
            case .landscapeRight:     return 0
            default:                  return 90
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applyCurrentRotation()
        }
    }
}
