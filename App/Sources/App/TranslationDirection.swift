import Foundation
import TranslationEngine

/// Which speech gets recognized and which language it's translated into. Chosen from the menu
/// before a session starts — fixed for that session's lifetime, since the ASR locale and the
/// on-device translation language pack can't change once `SpeechAnalyzerASRProvider`/
/// `AppleTranslationProvider` are constructed.
public enum TranslationDirection: String, CaseIterable {
    case englishToRussian
    case englishToUkrainian

    public var menuTitle: String {
        switch self {
        case .englishToRussian: return "Английский → Русский"
        case .englishToUkrainian: return "Английский → Украинский"
        }
    }

    /// Abbreviation shown next to the recognized (original) line in the overlay.
    public var originalLanguageLabel: String {
        switch self {
        case .englishToRussian, .englishToUkrainian: return "EN"
        }
    }

    /// Abbreviation shown next to the translated line in the overlay.
    public var translatedLanguageLabel: String {
        switch self {
        case .englishToRussian: return "RU"
        case .englishToUkrainian: return "UA"
        }
    }

    // Both directions recognize English speech — Apple's on-device `SpeechAnalyzer` has no
    // Russian or Ukrainian support at all (`SpeechTranscriber.supportedLocales` doesn't list
    // either, confirmed by direct check), unlike the *translation* language packs, which do cover
    // both. A same-source-language design keeps every direction actually functional instead of
    // silently failing to recognize speech the way `.russianToEnglish` used to (removed).
    var speechLocale: Locale {
        Locale(identifier: "en-US")
    }

    var sourceLanguage: Locale.Language {
        Locale.Language(languageCode: .english)
    }

    var targetLanguage: Locale.Language {
        switch self {
        case .englishToRussian: return Locale.Language(languageCode: .russian)
        case .englishToUkrainian: return Locale.Language(languageCode: .ukrainian)
        }
    }

    /// Each direction has its own curated IT-jargon glossary (`ITGlossary`) — the Russian one's
    /// terms are Russian phrases, so they don't carry over to a Ukrainian target, and vice versa.
    var glossary: [String: String] {
        switch self {
        case .englishToRussian: return ITGlossary.englishToRussian
        case .englishToUkrainian: return ITGlossary.englishToUkrainian
        }
    }
}
