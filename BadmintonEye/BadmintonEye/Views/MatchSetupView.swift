import SwiftUI
import SwiftData
import ScoringEngine

struct MatchSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Player.name) private var existingPlayers: [Player]

    @State private var selectedFormat: MatchFormat = .singles
    @State private var playerAName: String = ""
    @State private var playerBName: String = ""
    @State private var playerA2Name: String = ""
    @State private var playerB2Name: String = ""
    @State private var navigateToMatch = false
    @State private var matchState: MatchState?

    // Picker sheet state
    @State private var showPickerFor: PickerTarget?

    private enum PickerTarget: Identifiable {
        case playerA, playerB, playerA2, playerB2
        var id: Int { hashValue }
    }

    private var isDoubles: Bool {
        selectedFormat == .doubles || selectedFormat == .mixed
    }

    private var excludeNames: [String] {
        [playerAName, playerBName, playerA2Name, playerB2Name]
            .filter { !$0.isEmpty }
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
                playerField(
                    placeholder: isDoubles ? "Player 1A" : "Player 1",
                    text: $playerAName,
                    target: .playerA
                )

                if isDoubles {
                    playerField(
                        placeholder: "Player 1B",
                        text: $playerA2Name,
                        target: .playerA2
                    )
                }
            }

            Section("Team B") {
                playerField(
                    placeholder: isDoubles ? "Player 2A" : "Player 2",
                    text: $playerBName,
                    target: .playerB
                )

                if isDoubles {
                    playerField(
                        placeholder: "Player 2B",
                        text: $playerB2Name,
                        target: .playerB2
                    )
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
        .sheet(item: $showPickerFor) { target in
            NavigationStack {
                PlayerPickerView(
                    selectedName: binding(for: target),
                    label: label(for: target),
                    excludeNames: excludeNames
                )
            }
        }
    }

    // MARK: - Player Field with Picker Button

    @ViewBuilder
    private func playerField(
        placeholder: String,
        text: Binding<String>,
        target: PickerTarget
    ) -> some View {
        HStack {
            TextField(placeholder, text: text)
                .textContentType(.name)

            Button {
                showPickerFor = target
            } label: {
                Image(systemName: "person.circle")
                    .foregroundStyle(.tint)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func binding(for target: PickerTarget) -> Binding<String> {
        switch target {
        case .playerA: return $playerAName
        case .playerB: return $playerBName
        case .playerA2: return $playerA2Name
        case .playerB2: return $playerB2Name
        }
    }

    private func label(for target: PickerTarget) -> String {
        switch target {
        case .playerA: return isDoubles ? "Player 1A" : "Player 1"
        case .playerB: return isDoubles ? "Player 2A" : "Player 2"
        case .playerA2: return "Player 1B"
        case .playerB2: return "Player 2B"
        }
    }

    private func startMatch() {
        // Auto-create Player records for new names
        autoCreatePlayers()

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

    /// Auto-creates Player records for any entered names not already in the database
    private func autoCreatePlayers() {
        let existingNames = Set(existingPlayers.map(\.name))
        let enteredNames: [String]

        if isDoubles {
            enteredNames = [playerAName, playerBName, playerA2Name, playerB2Name]
        } else {
            enteredNames = [playerAName, playerBName]
        }

        for name in enteredNames {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !existingNames.contains(trimmed) else { continue }
            let newPlayer = Player()
            newPlayer.name = trimmed
            modelContext.insert(newPlayer)
        }
    }
}
