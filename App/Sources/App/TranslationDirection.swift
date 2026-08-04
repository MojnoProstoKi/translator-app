import Foundation

/// Which speech gets recognized and which language it's translated into. Chosen from the menu
/// before a session starts — fixed for that session's lifetime, since the ASR locale and the
/// on-device translation language pack can't change once `SpeechAnalyzerASRProvider`/
/// `AppleTranslationProvider` are constructed.
public enum TranslationDirection: String, CaseIterable {
    case englishToRussian
    case russianToEnglish

    public var menuTitle: String {
        switch self {
        case .englishToRussian: return "Английский → Русский"
        case .russianToEnglish: return "Русский → Английский"
        }
    }

    /// Abbreviation shown next to the recognized (original) line in the overlay.
    public var originalLanguageLabel: String {
        switch self {
        case .englishToRussian: return "EN"
        case .russianToEnglish: return "RU"
        }
    }

    /// Abbreviation shown next to the translated line in the overlay.
    public var translatedLanguageLabel: String {
        switch self {
        case .englishToRussian: return "RU"
        case .russianToEnglish: return "EN"
        }
    }

    var speechLocale: Locale {
        switch self {
        case .englishToRussian: return Locale(identifier: "en-US")
        case .russianToEnglish: return Locale(identifier: "ru-RU")
        }
    }

    var sourceLanguage: Locale.Language {
        switch self {
        case .englishToRussian: return Locale.Language(languageCode: .english)
        case .russianToEnglish: return Locale.Language(languageCode: .russian)
        }
    }

    var targetLanguage: Locale.Language {
        switch self {
        case .englishToRussian: return Locale.Language(languageCode: .russian)
        case .russianToEnglish: return Locale.Language(languageCode: .english)
        }
    }

    /// Only English→Russian has a curated IT-jargon glossary (`ITGlossary`) right now — applying
    /// the same term list backwards would need its own reversed, separately-curated list, not
    /// just running it in reverse.
    var appliesGlossary: Bool {
        self == .englishToRussian
    }
}
