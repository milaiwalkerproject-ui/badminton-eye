// VoiceAnnouncement.swift — BWF scoring format for voice announcements

extension MatchState {
    /// BWF voice announcement string for the current score (no team name).
    ///
    /// Format: "{servingScore}-{opponentScore}, serving"
    /// The serving player's score is always stated first, followed by the
    /// opponent's score, then ", serving" — matching standard BWF court protocol.
    ///
    /// Examples:
    ///   • sideA serves, score A:15 B:0  → "15-0, serving"
    ///   • sideB serves, score A:0 B:15  → "15-0, serving"
    ///   • sideA serves, score A:20 B:20 → "20-20, serving"
    public var voiceAnnouncementText: String {
        let server = currentServer.side
        let servingScore: Int
        let opponentScore: Int
        switch server {
        case .sideA:
            servingScore = currentGame.scoreA
            opponentScore = currentGame.scoreB
        case .sideB:
            servingScore = currentGame.scoreB
            opponentScore = currentGame.scoreA
        }
        return "\(servingScore)-\(opponentScore), serving"
    }

    /// BWF voice announcement string including the server's team name.
    ///
    /// Format: "{servingScore} - {opponentScore}, {serverName} to serve"
    /// The server's score is always stated first — matches BWF court protocol.
    /// Uses `teamANames.first` / `teamBNames.first` as the server label.
    ///
    /// Examples:
    ///   • sideA serves, A:15 B:0,  teamA = ["Lee"]     → "15 - 0, Lee to serve"
    ///   • sideB serves, A:5 B:10,  teamB = ["Chen"]    → "10 - 5, Chen to serve"
    ///   • sideA serves, A:20 B:20, teamA = ["Player 1"] → "20 - 20, Player 1 to serve"
    public var voiceAnnouncementTextWithServer: String {
        let server = currentServer.side
        let servingScore: Int
        let opponentScore: Int
        let serverName: String

        switch server {
        case .sideA:
            servingScore = currentGame.scoreA
            opponentScore = currentGame.scoreB
            serverName = teamANames.first ?? "Side A"
        case .sideB:
            servingScore = currentGame.scoreB
            opponentScore = currentGame.scoreA
            serverName = teamBNames.first ?? "Side B"
        }

        return "\(servingScore) - \(opponentScore), \(serverName) to serve"
    }
}
