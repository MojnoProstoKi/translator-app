import Foundation

/// Wraps another `TranslationProvider` and protects known IT-jargon terms (`ITGlossary`) from
/// being mistranslated: matched terms are swapped for placeholder tokens before the text reaches
/// the wrapped provider, then swapped back for their glossary translation afterwards. The wrapped
/// provider never sees the original English term for a protected match, so it can't mistranslate
/// what it never receives.
///
/// `NSRegularExpression` is safe to share across concurrent `translate` calls once built (Apple
/// docs: read-only matching is thread-safe), hence `@unchecked Sendable`.
public final class GlossaryTranslationProvider: TranslationProvider, @unchecked Sendable {
    private let wrapped: any TranslationProvider
    private let glossary: [String: String]
    private let pattern: NSRegularExpression?

    public init(wrapping wrapped: any TranslationProvider, glossary: [String: String] = ITGlossary.englishToRussian) {
        self.wrapped = wrapped
        self.glossary = glossary
        self.pattern = Self.buildPattern(for: glossary.keys)
    }

    // Longest term first, so e.g. "pull request" matches before a shorter overlapping term
    // would. `\b` word boundaries keep multi-word terms from matching mid-word.
    private static func buildPattern(for terms: Dictionary<String, String>.Keys) -> NSRegularExpression? {
        guard !terms.isEmpty else { return nil }
        let alternation = terms
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        return try? NSRegularExpression(pattern: "\\b(?:\(alternation))\\b", options: [.caseInsensitive])
    }

    public func translate(_ text: String, isFinal: Bool) async throws -> String {
        guard let pattern else {
            return try await wrapped.translate(text, isFinal: isFinal)
        }

        var placeholders: [String: String] = [:]
        let protectedText = protect(text, pattern: pattern, placeholders: &placeholders)
        guard !placeholders.isEmpty else {
            return try await wrapped.translate(text, isFinal: isFinal)
        }

        let translated = try await wrapped.translate(protectedText, isFinal: isFinal)
        return restore(translated, placeholders: placeholders)
    }

    private func protect(_ text: String, pattern: NSRegularExpression, placeholders: inout [String: String]) -> String {
        let nsText = text as NSString
        let matches = pattern.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return text }

        var result = ""
        var lastEnd = 0
        for (index, match) in matches.enumerated() {
            let range = match.range
            result += nsText.substring(with: NSRange(location: lastEnd, length: range.location - lastEnd))
            let matchedTerm = nsText.substring(with: range).lowercased()
            let placeholder = "⟦\(index)⟧"
            placeholders[placeholder] = glossary[matchedTerm] ?? nsText.substring(with: range)
            result += placeholder
            lastEnd = range.location + range.length
        }
        result += nsText.substring(with: NSRange(location: lastEnd, length: nsText.length - lastEnd))
        return result
    }

    private func restore(_ text: String, placeholders: [String: String]) -> String {
        var result = text
        for (placeholder, russian) in placeholders {
            result = result.replacingOccurrences(of: placeholder, with: russian)
        }
        return result
    }
}
