import SwiftUI
import ScoringEngine

struct LiveMatchView: View {
    @State var viewModel: LiveMatchViewModel
    var onMatchEnd: (() -> Void)?
    @State private var showAbandonAlert = false
    @State private var showChallengeSheet = false
    @State private var showPaywall = false
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
        ZStack {
            // Half-screen tap zones
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Side A tap zone (A11Y-02)
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
                    .contentShape(Rectangle())
                    .frame(
                        width: geometry.size.width / 2,
                        height: geometry.size.height
                    )
                    .accessibilityLabel("Score point for \(viewModel.state.teamANames.first ?? "Team A")")
                    .accessibilityHint("Double-tap to add a point")

                    // Side B tap zone (A11Y-02)
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
                    .contentShape(Rectangle())
                    .frame(
                        width: geometry.size.width / 2,
                        height: geometry.size.height
                    )
                    .accessibilityLabel("Score point for \(viewModel.state.teamBNames.first ?? "Team B")")
                    .accessibilityHint("Double-tap to add a point")
                }
            }
            .ignoresSafeArea()

            // Top HUD — unified glass pill centered, with floating
            // icon buttons on either side.
            VStack {
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
                .padding(.horizontal, BE.Space.m)
                .padding(.top, BE.Space.s)

                Spacer()
            }

            // Game end overlay
            if viewModel.showGameEndOverlay {
                GameEndOverlay(viewModel: viewModel)
            }
        }
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
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .onChange(of: currentTotalScore) { _, _ in
            startChallengeCountdown()
        }
        .onAppear {
            // Start countdown on first appearance if match is in progress
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

    /// Resets the challenge countdown to 10 seconds after each point.
    /// Uses structured concurrency instead of Timer to avoid main-thread
    /// timer callbacks that can delay SwiftUI layout passes.
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
