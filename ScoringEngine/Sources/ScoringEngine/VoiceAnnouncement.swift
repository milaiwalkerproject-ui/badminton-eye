// VoiceAnnouncement.swift — BWF scoring format for voice announcements

extension MatchState {
    /// BWF voice announcement string for the current score.
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
}
