import Foundation

/// Orchestrates capture → recognition → translation for one or more audio sources, emitting a
/// single merged stream of `TranslatedSegmentEvent`s (contracts/translation-engine-api.md).
///
/// Each source is recognized and translated concurrently on its own task, so that segments from
/// different sources (FR-007: microphone + system audio simultaneously) are never interleaved or
/// mixed with one another (they only share the final destination stream).
public final class TranslationPipeline: @unchecked Sendable {
    private let sources: [AudioCaptureSource]
    private let asr: ASRProvider
    private let translation: TranslationProvider

    private let lock = NSLock()
    private var runnerTask: Task<Void, Never>?

    /// Called whenever recognition or translation fails for a segment (e.g. a missing on-device
    /// language pack). Previously such failures were silently dropped (`try?` + `continue`),
    /// which made "still preparing" indistinguishable from "broken" from the UI's perspective.
    public var onError: (@Sendable (Error) -> Void)?

    public init(sources: [AudioCaptureSource], asr: ASRProvider, translation: TranslationProvider) {
        precondition(!sources.isEmpty, "TranslationPipeline requires at least one AudioCaptureSource (FR-001, FR-007)")
        self.sources = sources
        self.asr = asr
        self.translation = translation
    }

    /// Starts capturing all configured sources and returns the merged translated-event stream.
    ///
    /// - Throws: whatever the underlying `AudioCaptureSource.start()` throws (e.g. permission
    ///   not granted).
    public func start() throws -> AsyncStream<TranslatedSegmentEvent> {
        let asr = self.asr
        let translation = self.translation
        let onError = self.onError

        // Start every source up front so a failure here surfaces before any work begins.
        let audioStreams: [(AudioSourceType, AsyncStream<AudioBuffer>)] = try sources.map { source in
            (source.sourceType, try source.start())
        }

        let (stream, continuation) = AsyncStream<TranslatedSegmentEvent>.makeStream()

        let runner = Task {
            await withTaskGroup(of: Void.self) { group in
                for (sourceType, buffers) in audioStreams {
                    group.addTask {
                        let updates = asr.recognize(buffers, sourceType: sourceType)
                        for await update in updates {
                            if Task.isCancelled { break }
                            // FR-013: silence/no-speech never reaches this point, since a
                            // conforming ASRProvider does not emit updates for it.
                            let translatedText: String
                            do {
                                translatedText = try await translation.translate(update.text, isFinal: update.isFinal)
                            } catch {
                                // Previously swallowed via `try?` with no logging — made a
                                // failing TranslationProvider (e.g. language pack not installed)
                                // indistinguishable from "still listening". Always log failures.
                                EngineLog.error("Translation failed for segment \(update.segmentId): \(error)")
                                onError?(error)
                                continue
                            }
                            let event = TranslatedSegmentEvent(
                                segmentId: update.segmentId,
                                sourceType: update.sourceType,
                                originalText: update.text,
                                translatedText: translatedText,
                                isFinal: update.isFinal,
                                latency: Date().timeIntervalSince(update.startedAt)
                            )
                            // Observability (Constitution Principle V): metadata only at
                            // INFO+; full text only at DEBUG (Additional Constraints).
                            EngineLog.segmentMetadata(
                                source: event.sourceType,
                                provider: String(describing: type(of: asr)),
                                latencySeconds: event.latency,
                                isFinal: event.isFinal,
                                textLength: event.originalText.count
                            )
                            EngineLog.debugText(original: event.originalText, translated: event.translatedText)
                            continuation.yield(event)
                        }
                    }
                }
            }
            continuation.finish()
        }

        lock.lock()
        runnerTask = runner
        lock.unlock()

        continuation.onTermination = { [weak self] _ in
            self?.stopSourcesOnly()
        }

        return stream
    }

    /// Stops all sources and cancels in-flight recognition/translation work (FR-008).
    public func stop() {
        lock.lock()
        let task = runnerTask
        runnerTask = nil
        lock.unlock()
        task?.cancel()
        stopSourcesOnly()
    }

    private func stopSourcesOnly() {
        for source in sources {
            source.stop()
        }
    }
}
