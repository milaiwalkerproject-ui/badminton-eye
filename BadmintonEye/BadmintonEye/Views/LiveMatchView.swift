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
                            backgroundColor: Color.blue.opacity(0.85)
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
                            backgroundColor: Color.red.opacity(0.85)
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

            // Top bar overlay
            VStack {
                HStack {
                    // Undo button (A11Y-03)
                    Button {
                        viewModel.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .disabled(!viewModel.canUndo)
                    .opacity(viewModel.canUndo ? 1.0 : 0.4)
                    .accessibilityLabel("Undo last point")
                    .accessibilityHint(viewModel.canUndo ? "Double-tap to undo the last scored point" : "No points to undo")

                    Spacer()

                    // Game info (A11Y-04)
                    VStack(spacing: 2) {
                        Text("\(localization.localized("match.game")) \(viewModel.state.currentGame.gameNumber)")
                            .font(.headline)
                            .foregroundStyle(.white)

                        if !viewModel.state.games.isEmpty {
                            Text(completedGameScores)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.3))
                                .clipShape(Capsule())
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(gameInfoAccessibilityLabel)

                    Spacer()

                    // Challenge button (visible only during inProgress match)
                    if viewModel.state.matchPhase == .inProgress {
                        Button {
                            if subscriptionManager.isPremium {
                                showChallengeSheet = true
                            } else {
                                showPaywall = true
                            }
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                VStack(spacing: 2) {
                                    ZStack(alignment: .bottomTrailing) {
                                        Image(systemName: "eye.trianglebadge.exclamationmark")
                                            .font(.title3)

                                        // Lock badge for non-premium users
                                        if !subscriptionManager.isPremium {
                                            Image(systemName: "lock.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.yellow)
                                                .offset(x: 4, y: 2)
                                        }
                                    }
                                    Text("Challenge")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.white)
                                .padding(10)
                                .background(.black.opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                // Countdown badge (only for premium)
                                if subscriptionManager.isPremium && challengeCountdown > 0 {
                                    Text("\(challengeCountdown)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.black)
                                        .frame(width: 18, height: 18)
                                        .background(Color.yellow)
                                        .clipShape(Circle())
                                        .offset(x: 4, y: -4)
                                }
                            }
                        }
                        .disabled(subscriptionManager.isPremium && challengeCountdown == 0)
                        .opacity(subscriptionManager.isPremium ? (challengeCountdown > 0 ? 1.0 : 0.4) : 1.0)
                    }

                    // End match button (A11Y-03)
                    Button {
                        showAbandonAlert = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("End match")
                    .accessibilityHint("Double-tap to abandon the current match")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

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
