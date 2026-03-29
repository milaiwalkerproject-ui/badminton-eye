import SwiftUI
import SwiftData
import PhotosUI
import AVKit

/// Video capture/selection UI presented as sheet from the Challenge button.
struct ChallengeVideoView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var calibrations: [CalibrationProfile]

    @State private var videoCaptureManager = VideoCaptureManager()
    @State private var pipeline = HawkEyePipeline()
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var selectedVideoURL: URL?
    @State private var showCalibration = false
    @State private var showRecorder = false
    @State private var showResult = false
    @State private var showErrorAlert = false

    private var hasCalibration: Bool { !calibrations.isEmpty }

    var body: some View {
        NavigationStack {
            Group {
                if !hasCalibration {
                    calibrationRequiredView
                } else if let url = videoURL {
                    videoReviewView(url: url)
                } else if showRecorder {
                    recorderView
                } else {
                    videoSourcePickerView
                }
            }
            .navigationTitle("Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        videoCaptureManager.cleanup()
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showCalibration) {
                CourtCalibrationView()
            }
            .onChange(of: pipeline.isAnalyzing) { _, isAnalyzing in
                if isAnalyzing {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        analyzingTextOpacity = 0.3
                    }
                } else {
                    withAnimation(.default) {
                        analyzingTextOpacity = 1.0
                    }
                }
            }
        }
    }

    // MARK: - Video URL (recorded or selected)

    private var videoURL: URL? {
        videoCaptureManager.capturedVideoURL ?? selectedVideoURL
    }

    // MARK: - Calibration Required

    private var calibrationRequiredView: some View {
        VStack(spacing: 20) {
            Image(systemName: "viewfinder")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Court Calibration Required")
                .font(.title2.bold())

            Text("Before using Hawk Eye challenges, you need to calibrate the court boundaries by tapping the 4 corners.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            Button {
                showCalibration = true
            } label: {
                Label("Calibrate Court First", systemImage: "viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Video Source Picker

    private var videoSourcePickerView: some View {
        VStack(spacing: 24) {
            Image(systemName: "eye.trianglebadge.exclamationmark")
                .font(.system(size: 50))
                .foregroundStyle(.yellow)

            Text("Capture Challenge Video")
                .font(.title2.bold())

            Text("Record a short clip or select a video from your library to analyze the shuttle trajectory.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)

            VStack(spacing: 16) {
                Button {
                    showRecorder = true
                } label: {
                    Label("Record Clip", systemImage: "video.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                PhotosPicker(
                    selection: $selectedVideoItem,
                    matching: .videos
                ) {
                    Label("Select from Library", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .padding(.horizontal, 40)
        }
        .onChange(of: selectedVideoItem) { _, newItem in
            handleVideoSelection(newItem)
        }
    }

    // MARK: - Recorder View

    private var recorderView: some View {
        ZStack {
            // Camera preview
            if let session = videoCaptureManager.session, videoCaptureManager.isRecording || videoCaptureManager.capturedVideoURL == nil {
                CameraPreviewView(session: session)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            VStack {
                Spacer()

                // Duration counter
                if videoCaptureManager.isRecording {
                    Text(String(format: "%.1fs / 10.0s", videoCaptureManager.recordingDuration))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.6))
                        .clipShape(Capsule())

                    // Progress bar
                    ProgressView(value: videoCaptureManager.recordingDuration, total: 10.0)
                        .progressViewStyle(.linear)
                        .tint(.red)
                        .padding(.horizontal, 40)
                }

                // Record button
                HStack {
                    Button("Back") {
                        videoCaptureManager.stopRecording()
                        showRecorder = false
                    }
                    .foregroundStyle(.white)
                    .padding()

                    Spacer()

                    Button {
                        if videoCaptureManager.isRecording {
                            videoCaptureManager.stopRecording()
                        } else {
                            videoCaptureManager.startRecording()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(.white, lineWidth: 4)
                                .frame(width: 70, height: 70)
                            Circle()
                                .fill(videoCaptureManager.isRecording ? .white : .red)
                                .frame(
                                    width: videoCaptureManager.isRecording ? 30 : 58,
                                    height: videoCaptureManager.isRecording ? 30 : 58
                                )
                                .clipShape(
                                    RoundedRectangle(
                                        cornerRadius: videoCaptureManager.isRecording ? 6 : 29
                                    )
                                )
                        }
                    }

                    Spacer()

                    // Spacer to balance the Back button
                    Color.clear
                        .frame(width: 60, height: 44)
                        .padding()
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            // Auto-setup camera session for preview
            if !videoCaptureManager.isRecording && videoCaptureManager.capturedVideoURL == nil {
                videoCaptureManager.startRecording()
                // Small delay then stop to just set up the session for preview
                // Actually, start recording immediately as per UX plan
            }
        }
    }

    // MARK: - Video Review

    private func videoReviewView(url: URL) -> some View {
        ZStack {
            VStack(spacing: 20) {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                Text("Video captured successfully")
                    .font(.headline)

                Button {
                    guard let calibration = calibrations.first else { return }
                    Task {
                        await pipeline.analyze(videoURL: url, calibration: calibration)
                        if pipeline.result != nil {
                            showResult = true
                        }
                        if pipeline.errorMessage != nil {
                            showErrorAlert = true
                        }
                    }
                } label: {
                    Label("Analyze", systemImage: "eye.trianglebadge.exclamationmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .padding(.horizontal, 40)
                .disabled(pipeline.isAnalyzing)

                Button("Retake") {
                    videoCaptureManager.cleanup()
                    selectedVideoURL = nil
                    selectedVideoItem = nil
                    showRecorder = false
                }
                .foregroundStyle(.red)
                .disabled(pipeline.isAnalyzing)
            }

            // Analyzing overlay
            if pipeline.isAnalyzing {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    ProgressView(value: pipeline.progress)
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                        .tint(.yellow)

                    Text("Analyzing...")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .opacity(analyzingTextOpacity)

                    Text("\(Int(pipeline.progress * 100))%")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .fullScreenCover(isPresented: $showResult) {
            if let hawkEyeResult = pipeline.result {
                TrajectoryReplayView(result: hawkEyeResult)
            }
        }
        .alert("Analysis Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pipeline.errorMessage ?? "An unknown error occurred.")
        }
    }

    // Shimmer effect for analyzing text
    @State private var analyzingTextOpacity: Double = 1.0

    // MARK: - Photo Library Selection

    private func handleVideoSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mov")
                try? data.write(to: tempURL)
                await MainActor.run {
                    selectedVideoURL = tempURL
                }
            }
        }
    }
}
