import AVFoundation
import Foundation
import ScoringEngine

/// Announces badminton scores aloud using AVSpeechSynthesizer after each rally point.
///
/// Announcement format (BWF protocol):
///   "{server score} - {receiver score}, {server name} to serve"
///
/// Usage:
///   ```swift
///   VoiceAnnouncementService.shared.announce(state: matchState)
///   // Pause during Hawk Eye challenge analysis:
///   VoiceAnnouncementService.shared.announce(state: matchState, isPaused: hawkEyePipeline.isAnalyzing)
///   ```
final class VoiceAnnouncementService: NSObject {

    // MARK: - Singleton

    static let shared = VoiceAnnouncementService()

    // MARK: - UserDefaults Key

    static let userDefaultsKey = "voiceAnnouncementsEnabled"

    // MARK: - Private State

    private let synthesizer = AVSpeechSynthesizer()

    // MARK: - Init

    override private init() {
        super.init()
    }

    // MARK: - Public API

    /// Whether voice announcements are enabled (reads UserDefaults).
    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.userDefaultsKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: Self.userDefaultsKey) }
    }

    /// Announce the current score from a ``MatchState``.
    ///
    /// - Parameters:
    ///   - state: The current ``MatchState`` — score and server are read from this.
    ///   - isPaused: Pass `true` to suppress the announcement (e.g. when a Hawk Eye
    ///     challenge is actively being analysed). Defaults to `false`.
    func announce(state: MatchState, isPaused: Bool = false) {
        guard isEnabled, !isPaused else { return }
        let text = state.voiceAnnouncementTextWithServer
        speak(text)
    }

    /// Announce an arbitrary text string (useful for game-end messages).
    ///
    /// - Parameters:
    ///   - text: The string to speak.
    ///   - isPaused: Pass `true` to suppress the announcement. Defaults to `false`.
    func announce(text: String, isPaused: Bool = false) {
        guard isEnabled, !isPaused else { return }
        speak(text)
    }

    /// Stop any announcement currently in progress.
    func stopCurrentAnnouncement() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    // MARK: - Private Helpers

    private func speak(_ text: String) {
        // Cancel any in-progress utterance so the new score is spoken immediately.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = preferredVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        synthesizer.speak(utterance)
    }

    /// Resolves the best `AVSpeechSynthesisVoice` for the current locale.
    ///
    /// Priority:
    /// 1. Voice matching `LocalizationManager.currentLanguage` (if available on this device).
    /// 2. Voice matching `Locale.current.language.languageCode`.
    /// 3. System default (nil — AVFoundation picks automatically).
    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        // Prefer a legacy in-app language override when one was explicitly
        // set; otherwise follow the system locale (which reflects iOS's
        // native per-app language setting — the in-app picker is gone).
        // LocalizationManager is main-actor-isolated; announcements fire from
        // main-actor view models, so consult it only when already on main and
        // fall back to the system locale otherwise (the old behavior whenever
        // the manager reference hadn't been captured yet).
        var customLanguage: String?
        if Thread.isMainThread {
            customLanguage = MainActor.assumeIsolated { () -> String? in
                let manager = LocalizationManager.shared
                return manager.hasCustomLanguage ? manager.currentLanguage.rawValue : nil
            }
        }
        let languageCode = customLanguage
            ?? Locale.current.language.languageCode?.identifier ?? "en"

        // AVSpeechSynthesisVoice.speechVoices() returns all installed voices.
        // Pick the first one whose language prefix matches.
        let voices = AVSpeechSynthesisVoice.speechVoices()
        if let exactMatch = voices.first(where: { $0.language == languageCode }) {
            return exactMatch
        }
        // Fall back to prefix match (e.g. "en" matches "en-US", "en-GB").
        let prefix = languageCode.split(separator: "-").first.map(String.init) ?? languageCode
        if let prefixMatch = voices.first(where: { $0.language.hasPrefix(prefix) }) {
            return prefixMatch
        }
        // Let AVFoundation choose the default.
        return nil
    }
}
