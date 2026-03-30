import UIKit

/// Thin wrapper around UIFeedbackGenerator for score-related haptics.
/// Reads the user's haptic toggle from UserDefaults.
@MainActor
final class HapticFeedbackService {

    static let shared = HapticFeedbackService()

    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let notificationGenerator = UINotificationFeedbackGenerator()

    private init() {
        impactGenerator.prepare()
        notificationGenerator.prepare()
    }

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "hapticFeedbackEnabled") as? Bool ?? true
    }

    /// Regular point scored.
    func playPointScored() {
        guard isEnabled else { return }
        impactGenerator.impactOccurred()
    }

    /// Game point or match point — stronger notification haptic.
    func playGamePoint() {
        guard isEnabled else { return }
        notificationGenerator.notificationOccurred(.warning)
    }

    /// Match complete — success haptic.
    func playMatchComplete() {
        guard isEnabled else { return }
        notificationGenerator.notificationOccurred(.success)
    }
}
