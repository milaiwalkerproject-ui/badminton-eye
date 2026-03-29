import UIKit
import ScoringEngine

/// Renders match data into shareable formats: a court-themed UIImage and a printable PDF.
struct ScorecardRenderer {

    // MARK: - Image Rendering (600x400 court-themed card)

    static func renderImage(for match: PersistedMatch) -> UIImage? {
        let size = CGSize(width: 600, height: 400)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let cgCtx = ctx.cgContext

            // Court-themed green background
            UIColor(red: 0.106, green: 0.369, blue: 0.125, alpha: 1.0).setFill() // #1B5E20
            let bgPath = UIBezierPath(roundedRect: rect, cornerRadius: 20)
            bgPath.fill()

            // Court line pattern: two white horizontal lines at 1/3 and 2/3 height
            UIColor.white.withAlphaComponent(0.2).setStroke()
            cgCtx.setLineWidth(1.5)
            for fraction in [1.0 / 3.0, 2.0 / 3.0] {
                let y = size.height * fraction
                cgCtx.move(to: CGPoint(x: 30, y: y))
                cgCtx.addLine(to: CGPoint(x: size.width - 30, y: y))
            }
            cgCtx.strokePath()

            // Top: "Badminton Eye" branding
            let brandAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let brandText = "Badminton Eye" as NSString
            let brandSize = brandText.size(withAttributes: brandAttrs)
            brandText.draw(
                at: CGPoint(x: (size.width - brandSize.width) / 2, y: 16),
                withAttributes: brandAttrs
            )

            // Player names
            let names = playerNamesForImage(match)
            let isWinnerA = match.winnerSide == "sideA"
            let isWinnerB = match.winnerSide == "sideB"

            let nameFont = UIFont.systemFont(ofSize: 22, weight: .bold)
            let vsFont = UIFont.systemFont(ofSize: 16, weight: .regular)

            let winnerUnderline: [NSAttributedString.Key: Any] = [
                .font: nameFont,
                .foregroundColor: UIColor.white,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
            let normalName: [NSAttributedString.Key: Any] = [
                .font: nameFont,
                .foregroundColor: UIColor.white
            ]
            let vsAttrs: [NSAttributedString.Key: Any] = [
                .font: vsFont,
                .foregroundColor: UIColor.white.withAlphaComponent(0.7)
            ]

            let nameAAttrs = isWinnerA ? winnerUnderline : normalName
            let nameBAttrs = isWinnerB ? winnerUnderline : normalName

            let nameA = names.teamA as NSString
            let nameB = names.teamB as NSString
            let vsStr = "vs" as NSString

            let centerY: CGFloat = 140
            let nameASize = nameA.size(withAttributes: nameAAttrs)
            let vsSize = vsStr.size(withAttributes: vsAttrs)
            let nameBSize = nameB.size(withAttributes: nameBAttrs)

            let totalWidth = nameASize.width + 16 + vsSize.width + 16 + nameBSize.width
            var x = (size.width - totalWidth) / 2

            nameA.draw(at: CGPoint(x: x, y: centerY), withAttributes: nameAAttrs)
            x += nameASize.width + 16
            vsStr.draw(at: CGPoint(x: x, y: centerY + 4), withAttributes: vsAttrs)
            x += vsSize.width + 16
            nameB.draw(at: CGPoint(x: x, y: centerY), withAttributes: nameBAttrs)

            // Scores row
            let scores = gameScoresForDisplay(match)
            let scoreStr = scores.map { "\($0.a)-\($0.b)" }.joined(separator: ", ") as NSString
            let scoreAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .medium),
                .foregroundColor: UIColor.white
            ]
            let scoreSize = scoreStr.size(withAttributes: scoreAttrs)
            scoreStr.draw(
                at: CGPoint(x: (size.width - scoreSize.width) / 2, y: centerY + 50),
                withAttributes: scoreAttrs
            )

            // Bottom-left: date
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d, yyyy"
            let dateStr = dateFormatter.string(from: match.startedAt) as NSString
            let dateAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: UIColor.white.withAlphaComponent(0.8)
            ]
            dateStr.draw(at: CGPoint(x: 24, y: size.height - 40), withAttributes: dateAttrs)

            // Bottom-right: format badge pill
            let badge = formatBadge(match) as NSString
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: UIColor.white
            ]
            let badgeSize = badge.size(withAttributes: badgeAttrs)
            let pillRect = CGRect(
                x: size.width - badgeSize.width - 40,
                y: size.height - 42,
                width: badgeSize.width + 16,
                height: badgeSize.height + 8
            )
            UIColor.white.withAlphaComponent(0.2).setFill()
            UIBezierPath(roundedRect: pillRect, cornerRadius: pillRect.height / 2).fill()
            badge.draw(
                at: CGPoint(x: pillRect.origin.x + 8, y: pillRect.origin.y + 4),
                withAttributes: badgeAttrs
            )

            // Bottom-center: watermark
            let watermarkAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: UIColor.white.withAlphaComponent(0.5)
            ]
            let watermark = "Badminton Eye" as NSString
            let wmSize = watermark.size(withAttributes: watermarkAttrs)
            watermark.draw(
                at: CGPoint(x: (size.width - wmSize.width) / 2, y: size.height - 28),
                withAttributes: watermarkAttrs
            )
        }
    }

    // MARK: - PDF Rendering (US Letter)

    static func renderPDF(for match: PersistedMatch) -> Data? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { ctx in
            ctx.beginPage()
            let cgCtx = ctx.cgContext
            let margin: CGFloat = 60
            let contentWidth = pageRect.width - margin * 2
            var y: CGFloat = 60

            // Title
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            let title = "Match Scorecard" as NSString
            let titleSize = title.size(withAttributes: titleAttrs)
            title.draw(at: CGPoint(x: (pageRect.width - titleSize.width) / 2, y: y), withAttributes: titleAttrs)
            y += titleSize.height + 8

            // Subtitle: date + format
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMMM d, yyyy 'at' h:mm a"
            let subtitleStr = "\(dateFormatter.string(from: match.startedAt))  ·  \(formatBadge(match))" as NSString
            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor.gray
            ]
            let subSize = subtitleStr.size(withAttributes: subtitleAttrs)
            subtitleStr.draw(at: CGPoint(x: (pageRect.width - subSize.width) / 2, y: y), withAttributes: subtitleAttrs)
            y += subSize.height + 20

            // Horizontal rule
            cgCtx.setStrokeColor(UIColor.gray.withAlphaComponent(0.4).cgColor)
            cgCtx.setLineWidth(1)
            cgCtx.move(to: CGPoint(x: margin, y: y))
            cgCtx.addLine(to: CGPoint(x: pageRect.width - margin, y: y))
            cgCtx.strokePath()
            y += 24

            // Player names
            let names = playerNamesForImage(match)
            let playerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: UIColor.black
            ]
            let vsAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor.darkGray
            ]
            let playersStr = "\(names.teamA)  vs  \(names.teamB)" as NSString
            let playersSize = playersStr.size(withAttributes: playerAttrs)
            playersStr.draw(at: CGPoint(x: (pageRect.width - playersSize.width) / 2, y: y), withAttributes: playerAttrs)
            y += playersSize.height + 30

            // Score table
            let scores = gameScoresForDisplay(match)
            let colWidth = contentWidth / 3
            let rowHeight: CGFloat = 36
            let tableX = margin

            // Table header
            let headerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: UIColor.darkGray
            ]
            let cellAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: UIColor.black
            ]

            drawTableCell("", at: CGPoint(x: tableX, y: y), width: colWidth, attrs: headerAttrs)
            drawTableCell(names.teamA, at: CGPoint(x: tableX + colWidth, y: y), width: colWidth, attrs: headerAttrs)
            drawTableCell(names.teamB, at: CGPoint(x: tableX + colWidth * 2, y: y), width: colWidth, attrs: headerAttrs)
            y += rowHeight

            // Header underline
            cgCtx.setStrokeColor(UIColor.black.cgColor)
            cgCtx.setLineWidth(1)
            cgCtx.move(to: CGPoint(x: tableX, y: y))
            cgCtx.addLine(to: CGPoint(x: tableX + contentWidth, y: y))
            cgCtx.strokePath()
            y += 4

            // Game rows
            for (i, score) in scores.enumerated() {
                drawTableCell("Game \(i + 1)", at: CGPoint(x: tableX, y: y), width: colWidth, attrs: cellAttrs)
                drawTableCell("\(score.a)", at: CGPoint(x: tableX + colWidth, y: y), width: colWidth, attrs: cellAttrs)
                drawTableCell("\(score.b)", at: CGPoint(x: tableX + colWidth * 2, y: y), width: colWidth, attrs: cellAttrs)

                y += rowHeight
                cgCtx.setStrokeColor(UIColor.gray.withAlphaComponent(0.3).cgColor)
                cgCtx.setLineWidth(0.5)
                cgCtx.move(to: CGPoint(x: tableX, y: y))
                cgCtx.addLine(to: CGPoint(x: tableX + contentWidth, y: y))
                cgCtx.strokePath()
                y += 4
            }

            // Winner row
            if let side = match.winnerSide {
                y += 8
                let winnerName = side == "sideA" ? names.teamA : names.teamB
                let winnerAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16, weight: .bold),
                    .foregroundColor: UIColor.black
                ]
                drawTableCell("Winner", at: CGPoint(x: tableX, y: y), width: colWidth, attrs: winnerAttrs)
                drawTableCell(winnerName, at: CGPoint(x: tableX + colWidth, y: y), width: colWidth * 2, attrs: winnerAttrs)
            }

            // Footer
            let footerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10, weight: .regular),
                .foregroundColor: UIColor.gray
            ]
            let shortDateFormatter = DateFormatter()
            shortDateFormatter.dateFormat = "MMM d, yyyy"
            let footerStr = "Generated by Badminton Eye  ·  \(shortDateFormatter.string(from: Date()))" as NSString
            let footerSize = footerStr.size(withAttributes: footerAttrs)
            footerStr.draw(
                at: CGPoint(x: (pageRect.width - footerSize.width) / 2, y: pageRect.height - 50),
                withAttributes: footerAttrs
            )
        }
    }

    // MARK: - Helpers

    private static func drawTableCell(_ text: String, at point: CGPoint, width: CGFloat, attrs: [NSAttributedString.Key: Any]) {
        let str = text as NSString
        let textSize = str.size(withAttributes: attrs)
        let centeredX = point.x + (width - textSize.width) / 2
        str.draw(at: CGPoint(x: centeredX, y: point.y), withAttributes: attrs)
    }

    private static func playerNamesForImage(_ match: PersistedMatch) -> (teamA: String, teamB: String) {
        let isDoubles = match.format == "doubles" || match.format == "mixed"
        if isDoubles {
            let teamA = [match.playerAName, match.playerA2Name]
                .compactMap { $0 }.joined(separator: " & ")
            let teamB = [match.playerBName, match.playerB2Name]
                .compactMap { $0 }.joined(separator: " & ")
            return (teamA.isEmpty ? "Team A" : teamA, teamB.isEmpty ? "Team B" : teamB)
        }
        return (match.playerAName ?? "Player 1", match.playerBName ?? "Player 2")
    }

    private static func formatBadge(_ match: PersistedMatch) -> String {
        switch match.format {
        case "doubles": return "Doubles"
        case "mixed": return "Mixed"
        default: return "Singles"
        }
    }

    /// Extracts game scores from decoded state if possible, falling back to persisted fields.
    private static func gameScoresForDisplay(_ match: PersistedMatch) -> [(a: Int, b: Int)] {
        // Try decoding stateJSON for full game data
        if let data = match.stateJSON,
           let state = try? JSONDecoder().decode(CodableMatchState.self, from: data) {
            return state.games.map { (a: $0.scoreA, b: $0.scoreB) }
        }

        // Fallback to persisted game scores
        var scores: [(a: Int, b: Int)] = [(a: match.game1ScoreA, b: match.game1ScoreB)]
        if let g2a = match.game2ScoreA, let g2b = match.game2ScoreB {
            scores.append((a: g2a, b: g2b))
        }
        if let g3a = match.game3ScoreA, let g3b = match.game3ScoreB {
            scores.append((a: g3a, b: g3b))
        }
        return scores
    }
}
