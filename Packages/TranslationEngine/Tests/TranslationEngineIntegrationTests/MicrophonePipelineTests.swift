import Foundation
import XCTest

@testable import TranslationEngine

/// Integration test for User Story 2 (spec.md): the real on-device pipeline fed with
/// `sample-en-mic.wav` through the microphone code path (`FileAudioSource` standing in for
/// `MicrophoneSource`'s live capture — see SystemAudioPipelineTests.swift for the same rationale).
///
/// ⚠️ Same permission caveats as SystemAudioPipelineTests.swift — not run automatically; see
/// quickstart.md for manual verification steps.
@available(macOS 26.0, *)
final class MicrophonePipelineTests: XCTestCase {
    private func fixtureURL(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures")!
    }

    func testMicrophoneProducesTranslatedEvents() async throws {
        let source = FileAudioSource(fileURL: fixtureURL("sample-en-mic"), sourceType: .microphone)
        let pipeline = TranslationPipeline(
            sources: [source],
            asr: SpeechAnalyzerASRProvider(),
            translation: AppleTranslationProvider()
        )

        var events: [TranslatedSegmentEvent] = []
        for await event in try pipeline.start() {
            events.append(event)
        }

        XCTAssertFalse(events.isEmpty)
        XCTAssertTrue(events.allSatisfy { $0.sourceType == .microphone })
        XCTAssertTrue(events.contains { $0.isFinal })
    }
}
