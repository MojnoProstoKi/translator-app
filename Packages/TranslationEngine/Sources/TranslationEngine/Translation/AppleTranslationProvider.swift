import Foundation
import Translation

/// Thrown when the on-device language pack required for translation is not installed and the
/// caller has no SwiftUI context available to prompt for download (research.md §2;
/// contracts/translate-cli.md exit code 3).
public struct LanguagePackNotInstalledError: Error, CustomStringConvertible {
    public let source: Locale.Language
    public let target: Locale.Language

    public var description: String {
        "Языковой пакет \(source.minimalIdentifier)→\(target.minimalIdentifier) не установлен на устройстве. "
            + "Установите его в Системных настройках → Основные → Язык и регион → Языки перевода, "
            + "затем перезапустите перевод."
    }
}

/// `TranslationProvider` adapter over Apple's on-device `Translation` framework
/// (research.md §2). English → Russian is fixed per spec.md Assumptions.
///
/// Note: this engine's own domain model also defines a `TranslationSession` type
/// (data-model.md → TranslationSession, a translation *session* in our domain sense). Apple's
/// framework type of the same name is therefore always referenced fully-qualified as
/// `Translation.TranslationSession` in this file to avoid ambiguity.
@available(macOS 26.0, *)
public final class AppleTranslationProvider: TranslationProvider, @unchecked Sendable {
    private let sourceLanguage: Locale.Language
    private let targetLanguage: Locale.Language

    private let lock = NSLock()
    private var cachedSession: Translation.TranslationSession?
    // Caches a setup failure (e.g. missing language pack) for this provider's lifetime so every
    // subsequent segment doesn't repeat the same slow, doomed-to-fail availability/prepare XPC
    // round-trip — confirmed in testing to otherwise re-run on every single translate() call.
    private var cachedFailure: Error?

    public init(
        source: Locale.Language = Locale.Language(languageCode: .english),
        target: Locale.Language = Locale.Language(languageCode: .russian)
    ) {
        self.sourceLanguage = source
        self.targetLanguage = target
    }

    public func translate(_ text: String, isFinal: Bool) async throws -> String {
        let session = try await resolvedSession()
        let response = try await session.translate(text)
        return response.targetText
    }

    private func resolvedSession() async throws -> Translation.TranslationSession {
        if let existing = lock.withLock({ cachedSession }) {
            return existing
        }
        if let failure = lock.withLock({ cachedFailure }) {
            throw failure
        }

        do {
            let availability = LanguageAvailability()
            let status = await availability.status(from: sourceLanguage, to: targetLanguage)
            guard status != .unsupported else {
                throw TranslationError.unsupportedLanguagePairing
            }

            let session = Translation.TranslationSession(installedSource: sourceLanguage, target: targetLanguage)
            if status != .installed {
                // Triggers the on-device asset download. Outside a SwiftUI `.translationTask`
                // context there is no automatic user-facing progress UI; the GUI app surfaces
                // one via TranslationPipeline.onError, and `translate-cli` reports exit code 3
                // if this throws `.notInstalled` (contracts/translate-cli.md).
                do {
                    try await session.prepareTranslation()
                } catch is TranslationError {
                    throw LanguagePackNotInstalledError(source: sourceLanguage, target: targetLanguage)
                }
            }

            lock.withLock { cachedSession = session }
            return session
        } catch {
            lock.withLock { cachedFailure = error }
            throw error
        }
    }
}
