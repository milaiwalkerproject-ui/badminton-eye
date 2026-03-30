import PhotosUI
import SwiftUI

/// Allows users to import a second camera angle for higher-confidence Hawk Eye analysis.
/// Each angle is analyzed independently, then results are fused.
struct MultiAngleAnalysisView: View {
    let primaryResult: HawkEyeResult
    let calibration: CalibrationProfile

    @State private var selectedItem: PhotosPickerItem?
    @State private var secondAngleURL: URL?
    @State private var secondPipeline = HawkEyePipeline()
    @State private var fusedResult: HawkEyeResult?
    @State private var isAnalyzing = false

    var body: some View {
        VStack(spacing: 20) {
            // Primary angle result
            resultCard(
                title: "Angle 1 (Primary)",
                result: primaryResult
            )

            // Second angle section
            if let fused = fusedResult {
                resultCard(
                    title: "Angle 2",
                    result: secondPipeline.result ?? primaryResult
                )

                Divider()

                // Fused result
                VStack(spacing: 8) {
                    Label("Multi-Angle Result", systemImage: "camera.on.rectangle.fill")
                        .font(.headline)

                    resultCard(
                        title: "Fused (\(Int(fused.confidence * 100))% confidence)",
                        result: fused
                    )
                }
            } else if isAnalyzing {
                ProgressView("Analyzing second angle...")
                    .padding()
            } else {
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    Label("Add Second Angle", systemImage: "plus.camera")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(style: StrokeStyle(lineWidth: 2, dash: [8]))
                                .foregroundStyle(.secondary)
                        )
                }
                .onChange(of: selectedItem) { _, newItem in
                    Task { await handleVideoSelection(newItem) }
                }
            }
        }
        .padding()
    }

    // MARK: - Result Card

    @ViewBuilder
    private func resultCard(title: String, result: HawkEyeResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Circle()
                    .fill(colorForResult(result.landingResult))
                    .frame(width: 12, height: 12)

                Text(result.landingResult.rawValue.uppercased())
                    .font(.headline)

                Spacer()

                Text("\(Int(result.confidence * 100))%")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
        )
    }

    private func colorForResult(_ result: LandingResult) -> Color {
        switch result {
        case .inBounds: return .green
        case .outOfBounds: return .red
        case .uncertain: return .yellow
        }
    }

    // MARK: - Video Handling

    @MainActor
    private func handleVideoSelection(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        // Export video to temporary URL
        guard let videoData = try? await item.loadTransferable(type: Data.self) else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("angle2_\(UUID().uuidString).mp4")
        try? videoData.write(to: tempURL)

        secondAngleURL = tempURL
        isAnalyzing = true

        // Run independent analysis
        await secondPipeline.analyze(videoURL: tempURL, calibration: calibration)

        // Fuse results
        if let secondResult = secondPipeline.result {
            fusedResult = ResultFusionService.fuse([primaryResult, secondResult])
        }

        isAnalyzing = false
    }
}
