import Foundation
import XCTest

@testable import TranslationEngine

/// Contract tests for `TranslationPipeline` (contracts/translation-engine-api.md).
///
/// Uses in-memory fake `ASRProvider`/`TranslationProvider`/`AudioCaptureSource` doubles — this
/// is a contract/unit test, where fakes are permitted (Constitution Principle IV forbids mocking
/// providers only in *integration* tests, which exercise the real on-device frameworks).
final class PipelineContractTests: XCTestCase {

    /// FR-004/FR-005: a segment MUST receive at least one non-final update followed by exactly
    /// one final update, and MUST NOT receive further updates after being finalized.
    func testPartialThenFinalLifecycle() async throws {
        let segmentId = UUID()
        let startedAt = Date()
        let source = FakeAudioCaptureSource(sourceType: .systemAudio, bufferCount: 3)
        let asr = FakeASRProvider(script: [
            [RecognizedSegmentUpdate(segmentId: segmentId, sourceType: .systemAudio, text: "Hello", isFinal: false, startedAt: startedAt)],
            [RecognizedSegmentUpdate(segmentId: segmentId, sourceType: .systemAudio, text: "Hello there", isFinal: false, startedAt: startedAt)],
            [RecognizedSegmentUpdate(segmentId: segmentId, sourceType: .systemAudio, text: "Hello there.", isFinal: true, startedAt: startedAt)],
        ])
        let translation = FakeTranslationProvider()
        let pipeline = TranslationPipeline(sources: [source], asr: asr, translation: translation)

        var events: [TranslatedSegmentEvent] = []
        for await event in try pipeline.start() {
            events.append(event)
        }

        let segmentEvents = events.filter { $0.segmentId == segmentId }
        XCTAssertEqual(segmentEvents.count, 3)
        XCTAssertTrue(segmentEvents.dropLast().allSatisfy { !$0.isFinal })
        XCTAssertEqual(segmentEvents.last?.isFinal, true)
        XCTAssertEqual(segmentEvents.last?.translatedText, translation.translation(for: "Hello there."))
    }

    /// FR-013: no speech in the input stream (simulated by an ASR provider that never emits)
    /// MUST NOT produce any `TranslatedSegmentEvent`.
    func testSilenceProducesNoEvents() async throws {
        let source = FakeAudioCaptureSource(sourceType: .microphone, bufferCount: 5)
        let asr = FakeASRProvider(script: [])
        let translation = FakeTranslationProvider()
        let pipeline = TranslationPipeline(sources: [source], asr: asr, translation: translation)

        var events: [TranslatedSegmentEvent] = []
        for await event in try pipeline.start() {
            events.append(event)
        }

        XCTAssertTrue(events.isEmpty)
    }
}

// MARK: - Fakes

final class FakeAudioCaptureSource: AudioCaptureSource, @unchecked Sendable {
    let sourceType: AudioSourceType
    private let bufferCount: Int
    var permissionState: PermissionState { get async { .granted } }

    init(sourceType: AudioSourceType, bufferCount: Int) {
        self.sourceType = sourceType
        self.bufferCount = bufferCount
    }

    func requestPermission() async -> PermissionState { .granted }

    func start() throws -> AsyncStream<AudioBuffer> {
        let count = bufferCount
        return AsyncStream { continuation in
            for _ in 0..<count {
                continuation.yield(AudioBuffer(samples: [], sampleRate: 16_000, capturedAt: Date()))
            }
            continuation.finish()
        }
    }

    func stop() {}
}

/// Emits one inner array of `RecognizedSegmentUpdate` per consumed `AudioBuffer`, ignoring
/// buffer contents (buffers are only used as a "tick" in these fakes).
final class FakeASRProvider: ASRProvider, @unchecked Sendable {
    private let script: [[RecognizedSegmentUpdate]]

    init(script: [[RecognizedSegmentUpdate]]) {
        self.script = script
    }

    func recognize(_ buffers: AsyncStream<AudioBuffer>, sourceType: AudioSourceType) -> AsyncStream<RecognizedSegmentUpdate> {
        let script = self.script
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

final class FakeTranslationProvider: TranslationProvider, @unchecked Sendable {
    func translation(for text: String) -> String { "RU:\(text)" }

    func translate(_ text: String, isFinal: Bool) async throws -> String {
        translation(for: text)
    }
}
