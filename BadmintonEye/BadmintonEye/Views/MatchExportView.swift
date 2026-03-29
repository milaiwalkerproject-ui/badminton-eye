import SwiftUI

/// Handles CSV generation and provides an export format picker for match data.
struct MatchExportView {

    // MARK: - CSV Generation (multiple matches)

    static func generateCSV(for matches: [PersistedMatch]) -> String {
        var lines: [String] = []
        lines.append("Date,Format,Player A,Player A2,Player B,Player B2,Game 1 A,Game 1 B,Game 2 A,Game 2 B,Game 3 A,Game 3 B,Winner")

        for match in matches {
            lines.append(csvRow(for: match))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - CSV Generation (single match)

    static func generateCSV(for match: PersistedMatch) -> String {
        var lines: [String] = []
        lines.append("Date,Format,Player A,Player A2,Player B,Player B2,Game 1 A,Game 1 B,Game 2 A,Game 2 B,Game 3 A,Game 3 B,Winner")
        lines.append(csvRow(for: match))
        return lines.joined(separator: "\n")
    }

    private static func csvRow(for match: PersistedMatch) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        let winner: String
        if let side = match.winnerSide {
            winner = side == "sideA" ? (match.playerAName ?? "Team A") : (match.playerBName ?? "Team B")
        } else {
            winner = ""
        }

        let fields: [String] = [
            dateFormatter.string(from: match.startedAt),
            match.format,
            escapeCSV(match.playerAName ?? ""),
            escapeCSV(match.playerA2Name ?? ""),
            escapeCSV(match.playerBName ?? ""),
            escapeCSV(match.playerB2Name ?? ""),
            "\(match.game1ScoreA)",
            "\(match.game1ScoreB)",
            match.game2ScoreA.map { "\($0)" } ?? "",
            match.game2ScoreB.map { "\($0)" } ?? "",
            match.game3ScoreA.map { "\($0)" } ?? "",
            match.game3ScoreB.map { "\($0)" } ?? "",
            escapeCSV(winner)
        ]
        return fields.joined(separator: ",")
    }

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}

// MARK: - Export Format Picker

struct ExportFormatPicker: View {
    let match: PersistedMatch
    @Binding var isPresented: Bool
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            List {
                Button {
                    shareImage()
                } label: {
                    Label("Share Scorecard Image", systemImage: "photo")
                }

                Button {
                    exportCSV()
                } label: {
                    Label("Export as CSV", systemImage: "tablecells")
                }

                Button {
                    exportPDF()
                } label: {
                    Label("Export as PDF", systemImage: "doc.richtext")
                }
            }
            .navigationTitle("Export Match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityViewController(items: shareItems)
        }
    }

    private func shareImage() {
        guard let image = ScorecardRenderer.renderImage(for: match) else { return }
        shareItems = [image]
        showShareSheet = true
    }

    private func exportCSV() {
        let csv = MatchExportView.generateCSV(for: match)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("match-export.csv")
        try? csv.write(to: tempURL, atomically: true, encoding: .utf8)
        shareItems = [tempURL]
        showShareSheet = true
    }

    private func exportPDF() {
        guard let data = ScorecardRenderer.renderPDF(for: match) else { return }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("match-scorecard.pdf")
        try? data.write(to: tempURL)
        shareItems = [tempURL]
        showShareSheet = true
    }
}

// MARK: - UIActivityViewController Wrapper

struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]
    var activities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: activities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
