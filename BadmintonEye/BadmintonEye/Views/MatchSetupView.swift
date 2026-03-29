import SwiftUI
import SwiftData
import ScoringEngine

struct MatchSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedFormat: MatchFormat = .singles
    @State private var playerAName: String = ""
    @State private var playerBName: String = ""
    @State private var playerA2Name: String = ""
    @State private var playerB2Name: String = ""
    @State private var navigateToMatch = false
    @State private var matchState: MatchState?

    private var isDoubles: Bool {
        selectedFormat == .doubles || selectedFormat == .mixed
    }

    var body: some View {
        Form {
            Section("Match Format") {
                Picker("Format", selection: $selectedFormat) {
                    Text("Singles").tag(MatchFormat.singles)
                    Text("Doubles").tag(MatchFormat.doubles)
                    Text("Mixed").tag(MatchFormat.mixed)
                }
                .pickerStyle(.segmented)
            }

            Section("Team A") {
                TextField(
                    isDoubles ? "Player 1A" : "Player 1",
                    text: $playerAName
                )
                .textContentType(.name)

                if isDoubles {
                    TextField("Player 1B", text: $playerA2Name)
                        .textContentType(.name)
                }
            }

            Section("Team B") {
                TextField(
                    isDoubles ? "Player 2A" : "Player 2",
                    text: $playerBName
                )
                .textContentType(.name)

                if isDoubles {
                    TextField("Player 2B", text: $playerB2Name)
                        .textContentType(.name)
                }
            }

            Section {
                Button(action: startMatch) {
                    Text("Start Match")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Badminton Eye")
        .navigationDestination(isPresented: $navigateToMatch) {
            if let state = matchState {
                LiveMatchView(
                    viewModel: LiveMatchViewModel(
                        state: state,
                        modelContext: modelContext
                    ),
                    onMatchEnd: {
                        navigateToMatch = false
                        matchState = nil
                    }
                )
                .navigationBarBackButtonHidden(true)
            }
        }
    }

    private func startMatch() {
        let state: MatchState
        switch selectedFormat {
        case .singles:
            state = MatchState.newSinglesMatch(
                teamAName: playerAName.isEmpty ? nil : playerAName,
                teamBName: playerBName.isEmpty ? nil : playerBName
            )
        case .doubles:
            let aNames = [
                playerAName.isEmpty ? "Player A1" : playerAName,
                playerA2Name.isEmpty ? "Player A2" : playerA2Name,
            ]
            let bNames = [
                playerBName.isEmpty ? "Player B1" : playerBName,
                playerB2Name.isEmpty ? "Player B2" : playerB2Name,
            ]
            state = MatchState.newDoublesMatch(
                teamANames: aNames,
                teamBNames: bNames
            )
        case .mixed:
            let aNames = [
                playerAName.isEmpty ? "Player A1" : playerAName,
                playerA2Name.isEmpty ? "Player A2" : playerA2Name,
            ]
            let bNames = [
                playerBName.isEmpty ? "Player B1" : playerBName,
                playerB2Name.isEmpty ? "Player B2" : playerB2Name,
            ]
            state = MatchState.newMixedMatch(
                teamANames: aNames,
                teamBNames: bNames
            )
        }
        matchState = state
        navigateToMatch = true
    }
}
