import SwiftUI
import ScoringEngine

struct LiveMatchView: View {
    @State var viewModel: LiveMatchViewModel
    var onMatchEnd: (() -> Void)?
    @State private var showAbandonAlert = false
    @State private var showChallengeSheet = false
    @State private var showPaywall = false
    @State private var showRallySuggestion = false
    @State private var challengeCountdown: Int = 0
    /// Cancellation token for the challenge countdown task.
    @State private var challengeCountdownTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    @State private var localization = LocalizationManager.shared

    private var subscriptionManager: SubscriptionManager { SubscriptionManager.shared }

    private var completedGameScores: String {
        viewModel.state.games.map { game in
            "\(game.scoreA)-\(game.scoreB)"
        }.joined(separator: " | ")
    }

    /// Total score in current game, used to detect point changes.
    private var currentTotalScore: Int {
        viewModel.state.currentGame.scoreA + viewModel.state.currentGame.scoreB
    }

    /// VoiceOver label for the game info area (A11Y-04).
    private var gameInfoAccessibilityLabel: String {
        var label = "Game \(viewModel.state.currentGame.gameNumber)"
        if !viewModel.state.games.isEmpty {
            label += ", previous scores: \(completedGameScores)"
        }
        return label
    }

    var body: some View {
        GeometryReader { proxy in
            // Landscape: camera takes the canvas, score floats on top.
            // Portrait: score panels on top, camera middle, controls bottom.
            if proxy.size.width > proxy.size.height {
                landscapeLayout(in: proxy.size)
            } else {
                portraitLayout(in: proxy.size)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .alert("End Match?", isPresented: $showAbandonAlert) {
            Button("Cancel", role: .cancel) {}
            Button("End Match", role: .destructive) {
                viewModel.abandonMatch()
            }
        } message: {
            Text("The match will be recorded as abandoned.")
        }
        .sheet(isPresented: $showChallengeSheet) {
            ChallengeVideoView()
        }
        .sheet(isPresented: $showRallySuggestion) {
            RallySuggestionSheet(
                teamANames: viewModel.state.teamANames,
                teamBNames: viewModel.state.teamBNames,
                suggestor: viewModel.rallySuggestor,
                autoApply: { viewModel.shouldAutoApplyLastResult() }
            ) { resolvedSide in
                if let side = resolvedSide {
                    viewModel.scorePoint(for: side)
                }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .onChange(of: currentTotalScore) { _, _ in
            startChallengeCountdown()
        }
        .onAppear {
            if viewModel.state.matchPhase == .inProgress && currentTotalScore > 0 {
                startChallengeCountdown()
            }
            // Defer camera start until after the navigation transition
            // so the previous view (calibration or setup) has fully
            // released any session it owned. 250ms is comfortably past
            // the default push animation and below any user-perceptible
            // delay.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                viewModel.startContinuousCapture()
            }
        }
        .onDisappear {
            challengeCountdownTask?.cancel()
            viewModel.stopContinuousCapture()
        }
        .navigationDestination(
            isPresented: Binding(
                get: { viewModel.state.matchPhase == .complete },
                set: { _ in }
            )
        ) {
            MatchEndView(state: viewModel.state, onNewMatch: onMatchEnd)
        }
        .navigationDestination(
            isPresented: Binding(
                get: { viewModel.state.matchPhase == .abandoned },
                set: { _ in }
            )
        ) {
            MatchEndView(state: viewModel.state, onNewMatch: onMatchEnd)
        }
    }

    // MARK: - Portrait layout
    //
    // Apple-Sports inspired stack:
    //   1. Floating top HUD (undo · game pill · challenge · close)
    //   2. Unified scoreboard card — both teams in one rounded card with
    //      gradient backdrops per side; tapping a side scores a point.
    //   3. Hero camera viewfinder filling the rest of the screen.
    //   4. Rally Ended primary action pinned over the camera at the bottom.
    @ViewBuilder
    private func portraitLayout(in size: CGSize) -> some View {
        ZStack {
            // Dark canvas reads as cinematic and prevents stark white
            // banding between the colorful scoreboard and the camera.
            Color.black.ignoresSafeArea()

            VStack(spacing: BE.Space.m) {
                topHUD
                    .padding(.horizontal, BE.Space.m)
                    .padding(.top, BE.Space.s)

                scoreboardCard
                    .padding(.horizontal, BE.Space.m)

                // Hero camera viewfinder fills the remaining space.
                cameraTile
                    .padding(.horizontal, BE.Space.m)
                    .padding(.bottom, BE.Space.m)
            }

            // Rally Ended floats over the camera, horizontally centered,
            // clear of the home indicator.
            if viewModel.state.matchPhase == .inProgress {
                VStack {
                    Spacer()
                    rallyEndedButton
                        .padding(.bottom, BE.Space.l + BE.Space.s)
                }
                .frame(maxWidth: .infinity)
            }

            if viewModel.showGameEndOverlay {
                GameEndOverlay(viewModel: viewModel)
            }
        }
    }

    // MARK: - Scoreboard card (portrait)

    private var scoreboardCard: some View {
        let server = viewModel.state.currentServer.side
        let court = viewModel.state.serviceCourt
        return HStack(spacing: 0) {
            scoreboardSide(
                isA: true,
                score: viewModel.state.currentGame.scoreA,
                name: viewModel.state.teamANames.first ?? "Team A",
                isServing: server == .sideA,
                serviceCourt: server == .sideA ? court : nil,
                gradient: BE.TeamA.gradient
            )
            scoreboardSide(
                isA: false,
                score: viewModel.state.currentGame.scoreB,
                name: viewModel.state.teamBNames.first ?? "Team B",
                isServing: server == .sideB,
                serviceCourt: server == .sideB ? court : nil,
                gradient: BE.TeamB.gradient
            )
        }
        .frame(height: 140)
        .clipShape(BE.card(22))
        .overlay(BE.card(22).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
    }

    private func scoreboardSide(
        isA: Bool,
        score: Int,
        name: String,
        isServing: Bool,
        serviceCourt: Court?,
        gradient: LinearGradient
    ) -> some View {
        Button {
            viewModel.scorePoint(for: isA ? .sideA : .sideB)
        } label: {
            ZStack {
                gradient
                LinearGradient(
                    colors: [Color.white.opacity(0.16), .clear],
                    startPoint: .top, endPoint: .center
                )
                .blendMode(.plusLighter)

                VStack(spacing: 6) {
                    // Name row — reserved-width slots for the serving pip
                    // and L/R chip so the name stays in the same X position
                    // regardless of which side is serving. Slots animate
                    // content in/out without nudging the name.
                    HStack(spacing: 5) {
                        ZStack {
                            if isServing {
                                Circle()
                                    .fill(BE.serveAccent)
                                    .frame(width: 7, height: 7)
                                    .shadow(color: BE.serveAccent.opacity(0.7), radius: 5)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .frame(width: 7, height: 7)

                        Text(name)
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)

                        ZStack {
                            if let serviceCourt {
                                Text(serviceCourt == .right ? "R" : "L")
                                    .font(.system(.caption2, design: .rounded).weight(.bold))
                                    .foregroundStyle(.black)
                                    .frame(width: 18, height: 18)
                                    .background(BE.serveAccent, in: Circle())
                                    .shadow(color: BE.serveAccent.opacity(0.5), radius: 4, y: 1)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .frame(width: 18, height: 18)
                    }
                    .animation(BE.ease, value: isServing)
                    .animation(BE.ease, value: serviceCourt)

                    Text("\(score)")
                        .font(.system(size: 72, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                        .contentTransition(.numericText(value: Double(score)))
                        .animation(BE.pop, value: score)
                }
                .padding(.vertical, BE.Space.s)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Score point for \(name)")
        .accessibilityValue("\(score)\(isServing ? ", serving from \(serviceCourt == .right ? "right" : "left") court" : "")")
    }

    // MARK: - Camera preview gate

    /// Renders the camera preview only when the recorder has finished
    /// configuring its session. Until then, shows a black placeholder so
    /// we don't flash an internal-session preview that gets immediately
    /// replaced. The `.equatable()` modifier lets SwiftUI skip
    /// `updateUIView` on score-taps when the session is unchanged.
    @ViewBuilder
    private var cameraPreviewOrPlaceholder: some View {
        if let session = viewModel.liveCaptureSession {
            LiveCameraPreview(session: session)
                .equatable()
        } else {
            Color.black
        }
    }

    // MARK: - Camera tile

    private var cameraTile: some View {
        ZStack {
            cameraPreviewOrPlaceholder
                .clipShape(BE.card(20))

            VStack {
                HStack {
                    cameraBadge
                    Spacer()
                }
                .padding(BE.Space.m)
                Spacer()
            }
        }
        .overlay(BE.card(20).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Landscape layout
    //
    // Camera fills the canvas; score and HUD float on top.
    // Tap-to-score is still available via two invisible half-width
    // overlays so a hand resting on either side of the device scores
    // for that side.
    @ViewBuilder
    private func landscapeLayout(in size: CGSize) -> some View {
        ZStack {
            cameraPreviewOrPlaceholder
                .ignoresSafeArea()

            // Invisible half-screen tap zones — keep existing scoring
            // muscle memory.
            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.scorePoint(for: .sideA) }
                    .accessibilityLabel("Score point for \(viewModel.state.teamANames.first ?? "Team A")")
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.scorePoint(for: .sideB) }
                    .accessibilityLabel("Score point for \(viewModel.state.teamBNames.first ?? "Team B")")
            }
            .ignoresSafeArea()

            // Side icon buttons — padded into the safe area on both edges.
            VStack {
                HStack(alignment: .center, spacing: BE.Space.s) {
                    GlassIconButton(systemName: "arrow.uturn.backward", disabled: !viewModel.canUndo) {
                        viewModel.undo()
                    }
                    .accessibilityLabel("Undo last point")
                    Spacer(minLength: 0)
                    if viewModel.state.matchPhase == .inProgress {
                        challengeButton
                    }
                    GlassIconButton(systemName: "xmark") {
                        showAbandonAlert = true
                    }
                    .accessibilityLabel("End match")
                }
                .frame(height: 44)
                .padding(.horizontal, BE.Space.m)
                .padding(.top, BE.Space.s)

                Spacer()
            }

            // Score banner — pinned to the true top-center of the canvas,
            // independent of side icons' padding so they always share the
            // same vertical axis as the bottom Rally Ended bubble.
            VStack {
                scoreBanner
                    .padding(.top, BE.Space.s)
                Spacer()
            }

            // Rally Ended — true bottom-center of the canvas.
            if viewModel.state.matchPhase == .inProgress {
                VStack {
                    Spacer()
                    rallyEndedButton
                        .padding(.bottom, BE.Space.l)
                }
            }

            if viewModel.showGameEndOverlay {
                GameEndOverlay(viewModel: viewModel)
            }
        }
    }

    // MARK: - Shared subviews

    /// Top HUD. Uses a ZStack so the center game pill is anchored to the
    /// true horizontal center, regardless of how many icon buttons appear
    /// on each side. Left and right groups occupy the row but the pill
    /// floats above it. All elements share the same vertical centerline.
    private var topHUD: some View {
        ZStack {
            // Row: left group on the leading edge, right group trailing.
            HStack(alignment: .center, spacing: BE.Space.s) {
                GlassIconButton(systemName: "arrow.uturn.backward", disabled: !viewModel.canUndo) {
                    viewModel.undo()
                }
                .accessibilityLabel("Undo last point")
                .accessibilityHint(viewModel.canUndo ? "Double-tap to undo the last scored point" : "No points to undo")

                Spacer(minLength: 0)

                if viewModel.state.matchPhase == .inProgress {
                    challengeButton
                }

                GlassIconButton(systemName: "xmark") {
                    showAbandonAlert = true
                }
                .accessibilityLabel("End match")
                .accessibilityHint("Double-tap to abandon the current match")
            }

            // Center pill — true-centered, never pushed by side groups.
            GlassPill {
                VStack(spacing: 2) {
                    Text("\(localization.localized("match.game")) \(viewModel.state.currentGame.gameNumber)")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                    if !viewModel.state.games.isEmpty {
                        Text(completedGameScores)
                            .font(.system(.caption2, design: .rounded).weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(gameInfoAccessibilityLabel)
        }
        .frame(height: 44)
    }

    private var sideAScoreButton: some View {
        Button {
            viewModel.scorePoint(for: .sideA)
        } label: {
            ScorePanel(
                score: viewModel.state.currentGame.scoreA,
                teamName: viewModel.state.teamANames.first ?? "Team A",
                isServing: viewModel.state.currentServer.side == .sideA,
                serviceCourt: viewModel.state.currentServer.side == .sideA
                    ? viewModel.state.serviceCourt : nil,
                playerNames: viewModel.state.teamANames,
                gradient: BE.TeamA.gradient
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityLabel("Score point for \(viewModel.state.teamANames.first ?? "Team A")")
        .accessibilityHint("Double-tap to add a point")
    }

    private var sideBScoreButton: some View {
        Button {
            viewModel.scorePoint(for: .sideB)
        } label: {
            ScorePanel(
                score: viewModel.state.currentGame.scoreB,
                teamName: viewModel.state.teamBNames.first ?? "Team B",
                isServing: viewModel.state.currentServer.side == .sideB,
                serviceCourt: viewModel.state.currentServer.side == .sideB
                    ? viewModel.state.serviceCourt : nil,
                playerNames: viewModel.state.teamBNames,
                gradient: BE.TeamB.gradient
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityLabel("Score point for \(viewModel.state.teamBNames.first ?? "Team B")")
        .accessibilityHint("Double-tap to add a point")
    }

    /// Compact landscape-mode score banner: A-score · game · B-score.
    /// The serving side's score is followed by an L/R court chip.
    private var scoreBanner: some View {
        let server = viewModel.state.currentServer.side
        let court = viewModel.state.serviceCourt
        return GlassPill {
            HStack(spacing: BE.Space.m) {
                bannerScore(viewModel.state.currentGame.scoreA,
                            court: server == .sideA ? court : nil,
                            chipLeading: false)
                VStack(spacing: 2) {
                    Text("\(localization.localized("match.game")) \(viewModel.state.currentGame.gameNumber)")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    if !viewModel.state.games.isEmpty {
                        Text(completedGameScores)
                            .font(.system(.caption2, design: .rounded).weight(.medium))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                bannerScore(viewModel.state.currentGame.scoreB,
                            court: server == .sideB ? court : nil,
                            chipLeading: true)
            }
            .padding(.horizontal, BE.Space.s)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score \(viewModel.state.currentGame.scoreA) to \(viewModel.state.currentGame.scoreB), \(gameInfoAccessibilityLabel)")
    }

    /// Score numeral with reserved L/R chip slots on both sides. Only the
    /// serving side's chip is populated, but the slot is always present,
    /// so the banner's geometric center stays put regardless of which
    /// side is serving — keeps it on the same vertical axis as the
    /// Rally Ended bubble below.
    private func bannerScore(_ score: Int, court: Court?, chipLeading: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if chipLeading { chipSlot(court) }
            Text("\(score)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            if !chipLeading { chipSlot(court) }
        }
    }

    @ViewBuilder
    private func chipSlot(_ court: Court?) -> some View {
        ZStack {
            if let court {
                Text(court == .right ? "R" : "L")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(.black)
                    .frame(width: 16, height: 16)
                    .background(BE.serveAccent, in: Circle())
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 16, height: 16)
        .animation(BE.ease, value: court)
    }

    /// "REC" pill displayed over the camera tile so it's obvious the
    /// preview is live (not a still). Pure visual cue — there's no
    /// actual disk recording in this build.
    private var cameraBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)
                .shadow(color: Color.red.opacity(0.6), radius: 4)
            Text("LIVE")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .tracking(0.8)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
    }

    private var rallyEndedButton: some View {
        Button {
            showRallySuggestion = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                Text("Rally Ended")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 16)
            .background(
                Capsule(style: .continuous)
                    .fill(LinearGradient(
                        colors: [BE.serveAccent.opacity(0.95), Color.orange],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
            )
            .shadow(color: BE.serveAccent.opacity(0.45), radius: 18, y: 8)
        }
        .accessibilityHint("Auto-suggest the rally winner")
    }

    // MARK: - Challenge button

    @ViewBuilder
    private var challengeButton: some View {
        let active = subscriptionManager.isPremium && challengeCountdown > 0
        let locked = !subscriptionManager.isPremium

        Button {
            if subscriptionManager.isPremium {
                showChallengeSheet = true
            } else {
                showPaywall = true
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(locked ? .white.opacity(0.95) : BE.serveAccent)
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)

                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Color.black.opacity(0.65), in: Circle())
                        .offset(x: 2, y: -2)
                } else if challengeCountdown > 0 {
                    Text("\(challengeCountdown)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.black)
                        .frame(width: 16, height: 16)
                        .background(BE.serveAccent, in: Circle())
                        .offset(x: 2, y: -2)
                }
            }
        }
        .disabled(subscriptionManager.isPremium && !active)
        .opacity(subscriptionManager.isPremium ? (active ? 1.0 : 0.5) : 1.0)
        .animation(BE.ease, value: challengeCountdown)
    }

    // MARK: - Challenge Countdown

    private func startChallengeCountdown() {
        challengeCountdownTask?.cancel()
        challengeCountdown = 10

        challengeCountdownTask = Task { @MainActor in
            do {
                while challengeCountdown > 0 {
                    try await Task.sleep(for: .seconds(1))
                    challengeCountdown -= 1
                }
            } catch {
                // Task was cancelled (new point scored or view disappeared) — expected
            }
        }
    }
}
