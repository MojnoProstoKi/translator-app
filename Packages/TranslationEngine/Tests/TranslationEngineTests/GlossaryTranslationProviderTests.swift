import XCTest

@testable import TranslationEngine

/// Unit tests for `GlossaryTranslationProvider`'s protect/restore substitution, using a fake
/// wrapped `TranslationProvider` — never touches the real Apple translator.
final class GlossaryTranslationProviderTests: XCTestCase {
    func testKnownTermIsOverriddenRegardlessOfWrappedTranslation() async throws {
        let wrapped = RecordingTranslationProvider { _ in "какой-то перевод" }
        let provider = GlossaryTranslationProvider(
            wrapping: wrapped,
            glossary: ["pull request": "пул-реквест"]
        )

        let result = try await provider.translate("Can you review my pull request?", isFinal: true)

        XCTAssertEqual(result, "какой-то перевод")
        XCTAssertTrue(wrapped.lastReceivedText?.contains("pull request") == false)
    }

    func testTranslationIsRestoredIntoWrappedOutput() async throws {
        let wrapped = RecordingTranslationProvider { text in "перевод: \(text)" }
        let provider = GlossaryTranslationProvider(
            wrapping: wrapped,
            glossary: ["backend": "бэкенд"]
        )

        let result = try await provider.translate("the backend is down", isFinal: true)

        XCTAssertTrue(result.contains("бэкенд"), "expected glossary term in result, got: \(result)")
        XCTAssertFalse(result.contains("backend"), "English term should have been replaced, got: \(result)")
    }

    func testMatchingIsCaseInsensitiveAndWordBoundaried() async throws {
        let wrapped = RecordingTranslationProvider { _ in "ok" }
        let provider = GlossaryTranslationProvider(
            wrapping: wrapped,
            glossary: ["api": "API"]
        )

        _ = try await provider.translate("Call the API now", isFinal: true)
        XCTAssertEqual(wrapped.lastReceivedText, "Call the ⟦0⟧ now")

        _ = try await provider.translate("rapid growth", isFinal: true)
        XCTAssertEqual(
            wrapped.lastReceivedText, "rapid growth",
            "'api' inside 'rapid' must not match as a whole word"
        )
    }

    func testTextWithoutGlossaryTermsPassesThroughUnchanged() async throws {
        let wrapped = RecordingTranslationProvider { text in "translated: \(text)" }
        let provider = GlossaryTranslationProvider(wrapping: wrapped, glossary: ["backend": "бэкенд"])

        let result = try await provider.translate("hello there", isFinal: false)

        XCTAssertEqual(result, "translated: hello there")
        XCTAssertEqual(wrapped.lastReceivedText, "hello there")
    }

    func testLongerTermWinsOverShorterOverlappingOne() async throws {
        let wrapped = RecordingTranslationProvider { text in text }
        let provider = GlossaryTranslationProvider(
            wrapping: wrapped,
            glossary: ["merge": "мёрж", "merge conflict": "конфликт мёржа"]
        )

        let result = try await provider.translate("fix the merge conflict", isFinal: true)

        XCTAssertEqual(result, "fix the конфликт мёржа")
    }
}

private final class RecordingTranslationProvider: TranslationProvider, @unchecked Sendable {
    private let respond: (String) -> String
    private(set) var lastReceivedText: String?

    init(respond: @escaping (String) -> String) {
        self.respond = respond
    }

    func translate(_ text: String, isFinal: Bool) async throws -> String {
        lastReceivedText = text
        return respond(text)
    }
}
