import Foundation
import TranslationEngine
import XCTest

@testable import RealtimeTranslator

/// Tests what the overlay's collapsed one-line strip shows (`OverlayViewModel.compactText`).
@MainActor
final class OverlayCompactModeTests: XCTestCase {
    private func event(_ id: UUID, original: String, translated: String, isFinal: Bool) -> TranslatedSegmentEvent {
        TranslatedSegmentEvent(
            segmentId: id,
            sourceType: .systemAudio,
            originalText: original,
            translatedText: translated,
            isFinal: isFinal,
            latency: 0
        )
    }

    func testToggleFlipsCompactMode() {
        let viewModel = OverlayViewModel()
        XCTAssertFalse(viewModel.isCompact)
        viewModel.toggleCompact()
        XCTAssertTrue(viewModel.isCompact)
        viewModel.toggleCompact()
        XCTAssertFalse(viewModel.isCompact)
    }

    func testCompactTextIsNilBeforeAnyTranslation() {
        XCTAssertNil(OverlayViewModel().compactText)
    }

    func testCompactTextShowsNewestTranslationIncludingPartial() {
        let viewModel = OverlayViewModel()
        viewModel.apply(event(UUID(), original: "Hello", translated: "Привет", isFinal: true))
        viewModel.apply(event(UUID(), original: "We should", translated: "Нам стоит", isFinal: false))

        XCTAssertEqual(viewModel.compactText, "Нам стоит")
    }

    func testCompactTextSkipsNewestLineWhoseTranslationHasNotArrivedYet() {
        let viewModel = OverlayViewModel()
        viewModel.apply(event(UUID(), original: "Hello", translated: "Привет", isFinal: true))
        viewModel.apply(event(UUID(), original: "We", translated: "", isFinal: false))

        XCTAssertEqual(viewModel.compactText, "Привет")
    }

    func testCompactTextPrefersErrorBanner() {
        let viewModel = OverlayViewModel()
        viewModel.apply(event(UUID(), original: "Hello", translated: "Привет", isFinal: true))
        viewModel.reportError("Языковой пакет не установлен")

        XCTAssertEqual(viewModel.compactText, "Языковой пакет не установлен")
    }
}
