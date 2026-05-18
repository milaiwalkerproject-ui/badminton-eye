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
                teamBNames: viewModel.state.teamBNames
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
        }
        .onDisappear {
            challengeCountdownTask?.cancel()
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
    // Stack top→bottom: top HUD, score row (tap-to-score), camera tile,
    // Rally Ended capsule. Camera tile is the visual focus but takes
    // ~36% of the vertical so the two score tap targets remain large
    // enough for fast scoring during a real match.
    @ViewBuilder
    private func portraitLayout(in size: CGSize) -> some View {
        let cameraHeight = size.height * 0.36

        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                topHUD
                    .padding(.horizontal, BE.Space.m)
                    .padding(.top, BE.Space.s)

                // Score tap zones — side-by-side, top portion of the screen.
                HStack(spacing: 0) {
                    sideAScoreButton
                    sideBScoreButton
                }
                .padding(.horizontal, BE.Space.s)
                .padding(.vertical, BE.Space.s)

                // Live camera tile.
                LiveCameraPreview()
                    .frame(height: cameraHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .overlay(alignment: .topLeading) {
                        cameraBadge
                            .padding(BE.Space.s)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                    .padding(.horizontal, BE.Space.m)

                Spacer(minLength: BE.Space.s)

                if viewModel.state.matchPhase == .inProgress {
                    rallyEndedButton
                        .padding(.bottom, BE.Space.m)
                }
            }

            if viewModel.showGameEndOverlay {
                GameEndOverlay(viewModel: viewModel)
            }
        }
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
            LiveCameraPreview()
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

            VStack {
                // Top: top-center score banner + side HUD icons.
                HStack(alignment: .center, spacing: BE.Space.s) {
                    GlassIconButton(systemName: "arrow.uturn.backward", disabled: !viewModel.canUndo) {
                        viewModel.undo()
                    }
                    .accessibilityLabel("Undo last point")
                    Spacer(minLength: 0)
                    scoreBanner
                    Spacer(minLength: 0)
                    if viewModel.state.matchPhase == .inProgress {
                        challengeButton
                    }
                    GlassIconButton(systemName: "xmark") {
                        showAbandonAlert = true
                    }
                    .accessibilityLabel("End match")
                }
                .padding(.horizontal, BE.Space.m)
                .padding(.top, BE.Space.s)

                Spacer()

                if viewModel.state.matchPhase == .inProgress {
                    rallyEndedButton
                        .padding(.bottom, BE.Space.m)
                }
            }

            if viewModel.showGameEndOverlay {
                GameEndOverlay(viewModel: viewModel)
            }
        }
    }

    // MARK: - Shared subviews

    private var topHUD: some View {
        HStack(alignment: .center, spacing: BE.Space.s) {
            GlassIconButton(systemName: "arrow.uturn.backward", disabled: !viewModel.canUndo) {
                viewModel.undo()
            }
            .accessibilityLabel("Undo last point")
            .accessibilityHint(viewModel.canUndo ? "Double-tap to undo the last scored point" : "No points to undo")

            Spacer(minLength: 0)

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
    private var scoreBanner: some View {
        GlassPill {
            HStack(spacing: BE.Space.m) {
                Text("\(viewModel.state.currentGame.scoreA)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
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
                Text("\(viewModel.state.currentGame.scoreB)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, BE.Space.s)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Score \(viewModel.state.currentGame.scoreA) to \(viewModel.state.currentGame.scoreB), \(gameInfoAccessibilityLabel)")
    }

    /// "REC" pill displayed over the camera tile so it's obvious the
    /// preview is live (not a still). Pure visual cue — there's no
    /// actual disk recording in this build.
    private var cameraBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            Text("LIVE")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.black.opacity(0.55), in: Capsule())
    }

    private var rallyEndedButton: some View {
        Button {
            showRallySuggestion = true
        } label: {
            Label("Rally Ended", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(.blue)
                .clipShape(Capsule())
                .shadow(radius: 4, y: 2)
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
