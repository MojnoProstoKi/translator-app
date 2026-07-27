import Foundation
import XCTest

@testable import TranslationEngine

/// Contract test for User Story 2 (FR-007): when microphone and system audio are both active,
/// their segments MUST NOT be mixed with one another — each event stays attributed to the
/// source it came from. In-memory fakes (permitted for contract/unit tests, Principle IV).
final class MultiSourceContractTests: XCTestCase {
    func testConcurrentSourcesDoNotMixSegments() async throws {
        let micSegmentId = UUID()
        let systemSegmentId = UUID()
        let startedAt = Date()

        let micSource = FakeAudioCaptureSource(sourceType: .microphone, bufferCount: 2)
        let systemSource = FakeAudioCaptureSource(sourceType: .systemAudio, bufferCount: 2)

        let asr = MultiSourceFakeASRProvider(scripts: [
            .microphone: [
                [RecognizedSegmentUpdate(segmentId: micSegmentId, sourceType: .microphone, text: "Can you hear me", isFinal: false, startedAt: startedAt)],
                [RecognizedSegmentUpdate(segmentId: micSegmentId, sourceType: .microphone, text: "Can you hear me clearly?", isFinal: true, startedAt: startedAt)],
            ],
            .systemAudio: [
                [RecognizedSegmentUpdate(segmentId: systemSegmentId, sourceType: .systemAudio, text: "Let's schedule the meeting", isFinal: false, startedAt: startedAt)],
                [RecognizedSegmentUpdate(segmentId: systemSegmentId, sourceType: .systemAudio, text: "Let's schedule the meeting for Tuesday.", isFinal: true, startedAt: startedAt)],
            ],
        ])
        let translation = FakeTranslationProvider()
        let pipeline = TranslationPipeline(sources: [micSource, systemSource], asr: asr, translation: translation)

        var events: [TranslatedSegmentEvent] = []
        for await event in try pipeline.start() {
            events.append(event)
        }

        let micEvents = events.filter { $0.sourceType == .microphone }
        let systemEvents = events.filter { $0.sourceType == .systemAudio }

        XCTAssertEqual(micEvents.count, 2)
        XCTAssertEqual(systemEvents.count, 2)
        XCTAssertTrue(micEvents.allSatisfy { $0.segmentId == micSegmentId })
        XCTAssertTrue(systemEvents.allSatisfy { $0.segmentId == systemSegmentId })
        XCTAssertTrue(micEvents.allSatisfy { $0.originalText.contains("hear me") })
        XCTAssertTrue(systemEvents.allSatisfy { $0.originalText.contains("meeting") })
    }
}

/// Like `FakeASRProvider`, but scripts vary per `AudioSourceType` so two concurrent sources can
/// be driven independently through one shared provider instance (as `TranslationPipeline` does).
final class MultiSourceFakeASRProvider: ASRProvider, @unchecked Sendable {
    private let scripts: [AudioSourceType: [[RecognizedSegmentUpdate]]]

    init(scripts: [AudioSourceType: [[RecognizedSegmentUpdate]]]) {
        self.scripts = scripts
    }

    func recognize(_ buffers: AsyncStream<AudioBuffer>, sourceType: AudioSourceType) -> AsyncStream<RecognizedSegmentUpdate> {
        let script = scripts[sourceType] ?? []
        return AsyncStream { continuation in
            Task {
                var index = 0
                for await _ in buffers {
                    if index < script.count {
                        for update in script[index] {
                            continuation.yield(update)
                        }
                        index += 1
                    }
                }
                continuation.finish()
            }
        }
    }
}
