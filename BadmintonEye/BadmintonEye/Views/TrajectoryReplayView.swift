import SwiftUI
import AVKit

/// Dramatic Hawk Eye result display with animated 2D court overlay,
/// trajectory path, color-coded landing spot visualization, and
/// optional slow-motion video replay for high-FPS footage.
struct TrajectoryReplayView: View {
    let result: HawkEyeResult
    var videoURL: URL? = nil
    var captureFPS: Double = 30
    @Environment(\.dismiss) private var dismiss

    // Animation state
    @State private var trimEnd: CGFloat = 0
    @State private var showLanding = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var titleOpacity: Double = 0

    // Video playback state
    @State private var isSlowMotion: Bool = false
    @State private var player: AVPlayer?

    // Court proportions: 13.4m x 6.1m
    private let courtAspect: CGFloat = 13.4 / 6.1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                // Title
                Text("HAWK EYE REVIEW")
                    .font(.system(.title2, design: .monospaced).bold())
                    .foregroundStyle(.white)
                    .opacity(titleOpacity)
                    .padding(.top, 40)

                // Video replay (if available)
                if videoURL != nil, let player {
                    VideoPlayer(player: player)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 20)

                    // Slow-motion toggle (only for high-FPS footage)
                    if captureFPS >= 120 {
                        Button {
                            isSlowMotion.toggle()
                            let rate: Float = isSlowMotion ? Float(30.0 / captureFPS) : 1.0
                            player.rate = rate
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isSlowMotion ? "tortoise.fill" : "hare.fill")
                                Text(isSlowMotion ? "Slow-Mo (\(Int(captureFPS / 30))x slower)" : "Normal Speed")
                                    .font(.subheadline.bold())
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(isSlowMotion ? Color.blue : Color.white.opacity(0.15))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                        }
                    }
                }

                // Court with trajectory
                courtView
                    .padding(.horizontal, 20)

                // Result text
                resultInfoView
                    .opacity(showLanding ? 1 : 0)

                Spacer()

                // Done button
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.15))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            startAnimationSequence()
            if let url = videoURL {
                player = AVPlayer(url: url)
                player?.play()
            }
        }
    }

    // MARK: - Court View

    private var courtView: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = width / courtAspect

            ZStack {
                // Court surface
                courtShape(width: width, height: height)

                // Trajectory path
                trajectoryPath(width: width, height: height)

                // Landing spot
                if showLanding {
                    landingSpot(width: width, height: height)
                }
            }
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(courtAspect, contentMode: .fit)
    }

    // MARK: - Court Shape

    private func courtShape(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // Court surface (green)
            context.fill(
                Path(CGRect(x: 0, y: 0, width: w, height: h)),
                with: .color(.green.opacity(0.3))
            )

            let lineWidth: CGFloat = 1.5
            let lineColor = Color.white

            // Outer doubles boundary
            context.stroke(
                Path(CGRect(x: 0, y: 0, width: w, height: h)),
                with: .color(lineColor),
                lineWidth: lineWidth * 2
            )

            // Singles sidelines (x: 0.155 and 0.845)
            let singlesLeft = w * 0.155
            let singlesRight = w * 0.845
            var singlesPath = Path()
            singlesPath.move(to: CGPoint(x: singlesLeft, y: 0))
            singlesPath.addLine(to: CGPoint(x: singlesLeft, y: h))
            singlesPath.move(to: CGPoint(x: singlesRight, y: 0))
            singlesPath.addLine(to: CGPoint(x: singlesRight, y: h))
            context.stroke(singlesPath, with: .color(lineColor), lineWidth: lineWidth)

            // Net line at center
            var netPath = Path()
            netPath.move(to: CGPoint(x: 0, y: h * 0.5))
            netPath.addLine(to: CGPoint(x: w, y: h * 0.5))
            context.stroke(netPath, with: .color(lineColor), lineWidth: lineWidth * 2)

            // Short service lines (approximately 1.98m from net = 0.148 of court length)
            let shortServiceNear = h * (0.5 - 0.148)
            let shortServiceFar = h * (0.5 + 0.148)
            var servicePath = Path()
            servicePath.move(to: CGPoint(x: singlesLeft, y: shortServiceNear))
            servicePath.addLine(to: CGPoint(x: singlesRight, y: shortServiceNear))
            servicePath.move(to: CGPoint(x: singlesLeft, y: shortServiceFar))
            servicePath.addLine(to: CGPoint(x: singlesRight, y: shortServiceFar))
            context.stroke(servicePath, with: .color(lineColor), lineWidth: lineWidth)

            // Long service line for doubles (0.72m from baseline = 0.054 of court length)
            let longServiceNear = h * 0.054
            let longServiceFar = h * (1.0 - 0.054)
            var longPath = Path()
            longPath.move(to: CGPoint(x: singlesLeft, y: longServiceNear))
            longPath.addLine(to: CGPoint(x: singlesRight, y: longServiceNear))
            longPath.move(to: CGPoint(x: singlesLeft, y: longServiceFar))
            longPath.addLine(to: CGPoint(x: singlesRight, y: longServiceFar))
            context.stroke(longPath, with: .color(lineColor), lineWidth: lineWidth)

            // Center line (between short service lines)
            let centerX = w * 0.5
            var centerPath = Path()
            centerPath.move(to: CGPoint(x: centerX, y: shortServiceNear))
            centerPath.addLine(to: CGPoint(x: centerX, y: shortServiceFar))
            context.stroke(centerPath, with: .color(lineColor), lineWidth: lineWidth)
        }
        .frame(width: width, height: height)
    }

    // MARK: - Trajectory Path

    private func trajectoryPath(width: CGFloat, height: CGFloat) -> some View {
        Path { path in
            let points = result.trajectoryPoints
            guard !points.isEmpty else { return }

            let first = points[0]
            path.move(to: CGPoint(x: first.x * width, y: first.y * height))

            for i in 1..<points.count {
                path.addLine(to: CGPoint(
                    x: points[i].x * width,
                    y: points[i].y * height
                ))
            }
        }
        .trim(from: 0, to: trimEnd)
        .stroke(
            .white,
            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 4])
        )
        .frame(width: width, height: height)
    }

    // MARK: - Landing Spot

    private func landingSpot(width: CGFloat, height: CGFloat) -> some View {
        let x = result.landingPoint.x * width
        let y = result.landingPoint.y * height
        // Larger circle = less confident = bigger uncertainty zone
        let baseSize: CGFloat = 16
        let uncertaintySize = baseSize + (1.0 - result.confidence) * 20

        return ZStack {
            // Pulsing ring
            Circle()
                .stroke(landingColor.opacity(0.5), lineWidth: 3)
                .frame(width: uncertaintySize * 1.8, height: uncertaintySize * 1.8)
                .scaleEffect(pulseScale)

            // Filled circle
            Circle()
                .fill(landingColor)
                .frame(width: uncertaintySize, height: uncertaintySize)

            // Inner white dot
            Circle()
                .fill(.white)
                .frame(width: 4, height: 4)
        }
        .position(x: x, y: y)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Result Info

    private var resultInfoView: some View {
        VStack(spacing: 12) {
            // Large result text
            Text(resultText)
                .font(.system(size: 44, weight: .black, design: .monospaced))
                .foregroundStyle(landingColor)

            // Confidence
            HStack(spacing: 8) {
                Text("\(Int(result.confidence * 100))% Confidence")
                    .font(.title3.bold())
                    .foregroundStyle(landingColor)

                // Low confidence badge
                if result.confidence < 0.5 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                        Text("Low Confidence")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red)
                    .clipShape(Capsule())
                }
            }

            // Margin from line (multiply normalized margin by 610cm court width)
            let marginCM = result.marginFromLine * 610
            Text("Distance from line: \(String(format: "%.1f", marginCM))cm")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Helpers

    private var landingColor: Color {
        switch result.landingResult {
        case .inBounds: return .green
        case .outOfBounds: return .red
        case .uncertain: return .yellow
        }
    }

    private var resultText: String {
        switch result.landingResult {
        case .inBounds: return "IN"
        case .outOfBounds: return "OUT"
        case .uncertain: return "INCONCLUSIVE"
        }
    }

    // MARK: - Animation Sequence

    private func startAnimationSequence() {
        // Title fade in
        withAnimation(.easeIn(duration: 0.5)) {
            titleOpacity = 1.0
        }

        // Trajectory animation starts after 0.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 1.5)) {
                trimEnd = 1.0
            }
        }

        // Landing spot appears after trajectory completes (2.0s total)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                showLanding = true
            }

            // Start pulsing animation
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseScale = 1.3
            }
        }
    }
}
