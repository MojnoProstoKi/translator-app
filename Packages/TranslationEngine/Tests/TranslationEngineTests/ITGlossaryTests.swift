import XCTest

@testable import TranslationEngine

/// Consistency checks between the per-direction curated glossaries in `ITGlossary`.
final class ITGlossaryTests: XCTestCase {
    func testUkrainianGlossaryCoversSameTermsAsRussian() {
        XCTAssertEqual(
            Set(ITGlossary.englishToUkrainian.keys),
            Set(ITGlossary.englishToRussian.keys)
        )
    }

    func testGlossaryKeysAreLowercased() {
        for key in ITGlossary.englishToRussian.keys.sorted() + ITGlossary.englishToUkrainian.keys.sorted() {
            XCTAssertEqual(key, key.lowercased(), "glossary key must be lowercased: \(key)")
        }
    }

    // Catches Russian spellings copy-pasted into the Ukrainian list — these letters don't exist
    // in the Ukrainian alphabet.
    func testUkrainianGlossaryHasNoRussianOnlyLetters() {
        let russianOnly = CharacterSet(charactersIn: "ыэёъЫЭЁЪ")
        for (term, translation) in ITGlossary.englishToUkrainian {
            XCTAssertNil(
                translation.rangeOfCharacter(from: russianOnly),
                "Ukrainian translation for '\(term)' contains Russian-only letters: \(translation)"
            )
        }
    }
}
