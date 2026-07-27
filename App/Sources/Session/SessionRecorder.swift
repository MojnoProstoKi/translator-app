import Foundation
import TranslationEngine

/// Builds the persisted `TranslationSession`/`SpeechSegment` domain model from
/// `TranslatedSegmentEvent`s as they stream in, and saves a `SessionTranscript` when the session
/// ends (FR-012, FR-016). Only finalized segments are ever persisted — audio is never involved
/// (FR-011), matching `SessionTranscript`'s precondition.
@MainActor
public final class SessionRecorder {
    private let store: SessionTranscriptStore
    private var session: TranslationSession?

    public init(store: SessionTranscriptStore) {
        self.store = store
    }

    public func beginSession(sources: Set<AudioSourceType>) {
        session = TranslationSession(startedAt: Date(), audioSources: sources)
    }

    public func apply(_ event: TranslatedSegmentEvent) {
        guard var session else { return }
        if let index = session.segments.firstIndex(where: { $0.id == event.segmentId }) {
            session.segments[index].apply(
                recognizedText: event.originalText,
                translatedText: event.translatedText,
                isFinal: event.isFinal,
                at: Date()
            )
        } else {
            var segment = SpeechSegment(sessionId: session.id, sourceType: event.sourceType, startedAt: Date())
            segment.apply(recognizedText: event.originalText, translatedText: event.translatedText, isFinal: event.isFinal, at: Date())
            session.segments.append(segment)
        }
        self.session = session
    }

    /// Ends the current session and persists its finalized segments as a `SessionTranscript`
    /// (FR-012). Segments that never reached `.finalized` (e.g. an utterance cut off mid-stream
    /// by a hard stop) are dropped, per `SessionTranscript`'s finalized-only precondition.
    @discardableResult
    public func endSession() throws -> SessionTranscript? {
        guard var session else { return nil }
        session.status = .stopped
        session.endedAt = Date()
        session.segments = session.segments.filter { $0.state == .finalized }
        self.session = nil

        guard !session.segments.isEmpty else { return nil }
        let transcript = SessionTranscript(session: session)
        try store.save(transcript)
        return transcript
    }
}
