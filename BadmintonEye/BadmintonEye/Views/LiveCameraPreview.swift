import SwiftUI
import UIKit
@preconcurrency import AVFoundation

/// Back-camera preview that attaches its `AVCaptureVideoPreviewLayer` to
/// an externally-owned `AVCaptureSession` (the one
/// `GameRecordingService` opens during a live match). The preview never
/// creates its own session — callers that don't yet have a session
/// should render a placeholder until one is available.
///
/// `Equatable` so SwiftUI can skip `updateUIView` when the parent body
/// re-runs but the session reference hasn't changed (e.g. on every
/// score-tap). Wrap with `.equatable()` at the call site to opt in.
struct LiveCameraPreview: UIViewRepresentable, Equatable {

    let session: AVCaptureSession
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    nonisolated static func == (lhs: LiveCameraPreview, rhs: LiveCameraPreview) -> Bool {
        // `session` is main-actor-isolated (AVCaptureSession isn't Sendable),
        // and SwiftUI only diffs views on the main actor, so hop in dynamically.
        MainActor.assumeIsolated {
            lhs.session === rhs.session && lhs.videoGravity == rhs.videoGravity
        }
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        view.videoGravity = videoGravity
        view.attach(session: session)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.videoGravity = videoGravity
        uiView.attach(session: session)
    }

    // MARK: - Backing UIView

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        private var previewLayer: AVCaptureVideoPreviewLayer {
            // swiftlint:disable:next force_cast
            layer as! AVCaptureVideoPreviewLayer
        }

        var videoGravity: AVLayerVideoGravity = .resizeAspectFill {
            didSet { previewLayer.videoGravity = videoGravity }
        }

        func attach(session: AVCaptureSession) {
            if previewLayer.session === session { return }
            previewLayer.session = session
            previewLayer.videoGravity = videoGravity
            applyCurrentRotation()
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
