import SwiftUI
import UIKit
@preconcurrency import AVFoundation

/// Lightweight back-camera preview. No recording, no mic, no buffer —
/// just an `AVCaptureSession` with a video input feeding an
/// `AVCaptureVideoPreviewLayer`. Safe to embed inside a SwiftUI view
/// without the audio-session reroute, mic-feedback, or heap-pressure
/// problems we hit with `GameRecordingService`.
///
/// Phase D will reintroduce a separate `CircularFrameBuffer` tee for ML
/// inference; that lives in `GameRecordingService` and stays inert here
/// so this stays cheap.
struct LiveCameraPreview: UIViewRepresentable {

    /// Optional override for the preview's content fit. Defaults to
    /// `.resizeAspectFill` so the preview looks like a viewfinder.
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoGravity = videoGravity
        view.backgroundColor = .black
        Task { @MainActor in
            await view.startIfNeeded()
        }
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.videoGravity = videoGravity
    }

    static func dismantleUIView(_ uiView: PreviewUIView, coordinator: ()) {
        uiView.stopSession()
    }

    // MARK: - Backing UIView

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        private var previewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }

        private let session = AVCaptureSession()
        private let sessionQueue = DispatchQueue(
            label: "com.badmintoneye.LiveCameraPreview.session",
            qos: .userInitiated
        )
        private var didConfigure = false

        var videoGravity: AVLayerVideoGravity = .resizeAspectFill {
            didSet { previewLayer.videoGravity = videoGravity }
        }

        // MARK: Session lifecycle

        @MainActor
        func startIfNeeded() async {
            previewLayer.session = session
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
            startCapture()
        }

        private func startCapture() {
            sessionQueue.async { [weak self] in
                guard let self = self else { return }

                if !self.didConfigure {
                    self.configureSessionLocked()
                    self.didConfigure = true
                }

                if !self.session.isRunning {
                    self.session.startRunning()
                }
            }
        }

        nonisolated func stopSession() {
            sessionQueue.async { [weak self] in
                guard let self = self else { return }
                if self.session.isRunning {
                    self.session.stopRunning()
                }
            }
        }

        // MARK: Configuration

        private func configureSessionLocked() {
            session.beginConfiguration()
            session.sessionPreset = .hd1280x720

            // Back wide-angle camera. Fail silently if unavailable so the
            // preview just shows black instead of crashing — UI is robust
            // to that (parent provides its own black backdrop).
            if let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .back
            ), let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input) {
                session.addInput(input)
            }

            session.commitConfiguration()
        }
    }
}
