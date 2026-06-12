import Foundation
import SwiftUI

/// Supported in-app languages, ordered by BWF badminton popularity.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case chinese = "zh-Hans"
    case japanese = "ja"
    case korean = "ko"
    case indonesian = "id"
    case malay = "ms"
    case hindi = "hi"
    case thai = "th"
    case danish = "da"

    var id: String { rawValue }

    /// Display name in the language's own script (native name).
    var nativeName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .indonesian: return "Bahasa Indonesia"
        case .malay: return "Bahasa Melayu"
        case .hindi: return "हिन्दी"
        case .thai: return "ไทย"
        case .danish: return "Dansk"
        }
    }

    /// Country flag emoji.
    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .chinese: return "🇨🇳"
        case .japanese: return "🇯🇵"
        case .korean: return "🇰🇷"
        case .indonesian: return "🇮🇩"
        case .malay: return "🇲🇾"
        case .hindi: return "🇮🇳"
        case .thai: return "🇹🇭"
        case .danish: return "🇩🇰"
        }
    }

    /// English label for the language.
    var englishName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "Chinese (Simplified)"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .indonesian: return "Indonesian"
        case .malay: return "Malay"
        case .hindi: return "Hindi"
        case .thai: return "Thai"
        case .danish: return "Danish"
        }
    }
}

/// Manages in-app language override. Uses @AppStorage for persistence.
/// When set, overrides the system locale for all localized strings.
@Observable
@MainActor
final class LocalizationManager {
    static let shared = LocalizationManager()

    var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "appLanguage")
            UserDefaults.standard.set([currentLanguage.rawValue], forKey: "AppleLanguages")
            // Invalidate the cached `.lproj` bundle so the next lookup resolves
            // the newly selected language.
            cachedBundle = nil
            cachedBundleLanguage = nil
        }
    }

    /// Cached resolved `.lproj` bundle for `currentLanguage`. Without this,
    /// every `localized(_:)` call did a `Bundle.main.path` + `Bundle(path:)`
    /// filesystem lookup — paid once per string on every view render,
    /// including the first paint of the Matches tab at launch.
    private var cachedBundle: Bundle?
    private var cachedBundleLanguage: AppLanguage?

    /// Whether user has explicitly chosen a language (vs system default).
    var hasCustomLanguage: Bool {
        UserDefaults.standard.string(forKey: "appLanguage") != nil
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "appLanguage"),
           let language = AppLanguage(rawValue: saved) {
            self.currentLanguage = language
        } else {
            self.currentLanguage = .english
        }
    }

    /// Reset to system default language.
    func resetToSystem() {
        UserDefaults.standard.removeObject(forKey: "appLanguage")
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        currentLanguage = .english
    }

    /// Get a localized string for the current language.
    /// Falls back to English if the key isn't translated.
    func localized(_ key: String) -> String {
        guard let bundle = languageBundle() else {
            return NSLocalizedString(key, comment: "")
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// Resolves (and caches) the `.lproj` bundle for the current language.
    ///
    /// Returns `nil` when the user never set a legacy in-app override, so
    /// `localized(_:)` falls through to `NSLocalizedString` and the system
    /// (including iOS's native per-app language setting) resolves the
    /// language. The in-app picker was removed from Settings; only a
    /// previously stored override still routes through an explicit bundle.
    private func languageBundle() -> Bundle? {
        guard hasCustomLanguage else { return nil }
        if cachedBundleLanguage == currentLanguage, let cachedBundle {
            return cachedBundle
        }
        guard let path = Bundle.main.path(forResource: currentLanguage.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return nil
        }
        cachedBundle = bundle
        cachedBundleLanguage = currentLanguage
        return bundle
    }
}
