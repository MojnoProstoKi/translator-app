import Foundation
import XCTest

@testable import TranslationEngine

/// Integration test for User Story 1 (spec.md): the real on-device `SpeechAnalyzer` →
/// `AppleTranslationProvider` pipeline, fed with the `sample-en-call.wav` fixture through the
/// system-audio code path (`FileAudioSource` standing in for `SystemAudioSource`'s live capture,
/// so this test is deterministic and doesn't require a live call).
///
/// Per Constitution Principle IV, no provider is mocked here — both `SpeechAnalyzerASRProvider`
/// and `AppleTranslationProvider` are the real adapters exercised against the real macOS
/// frameworks.
///
/// ⚠️ Requires macOS 26+, the en→ru on-device language pack installed, and (on first run in a
/// given process/binary) an interactive grant of Speech Recognition authorization. It is **not**
/// run as part of CI (see .github/workflows/ci.yml) or automatically by this implementation
/// session — run manually with `swift test --filter TranslationEngineIntegrationTests` after
/// granting permissions. See quickstart.md.
@available(macOS 26.0, *)
final class SystemAudioPipelineTests: XCTestCase {
    private func fixtureURL(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures")!
    }

    /// SC-001: the first (partial) translated event for a segment MUST arrive within 3–5 seconds
    /// of the segment starting, and at least one event MUST be marked final.
    func testSystemAudioCallProducesPartialThenFinalTranslation() async throws {
        let source = FileAudioSource(fileURL: fixtureURL("sample-en-call"), sourceType: .systemAudio)
        let pipeline = TranslationPipeline(
            sources: [source],
            asr: SpeechAnalyzerASRProvider(),
            translation: AppleTranslationProvider()
        )

        var events: [TranslatedSegmentEvent] = []
        for await event in try pipeline.start() {
            events.append(event)
        }

        XCTAssertFalse(events.isEmpty, "Expected at least one translated event for the fixture speech")
        XCTAssertTrue(events.contains { $0.isFinal }, "Expected at least one finalized segment")
        if let firstEvent = events.first {
            XCTAssertLessThanOrEqual(firstEvent.latency, 5.0, "SC-001: first translation should appear within 5s")
        }
        for event in events {
            XCTAssertFalse(event.translatedText.isEmpty, "Every event should carry non-empty translated text")
        }
    }
}
