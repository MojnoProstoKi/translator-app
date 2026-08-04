import Foundation
import TranslationEngine

/// Builds the persisted `TranslationSession`/`SpeechSegment` domain model from
/// `TranslatedSegmentEvent`s as they stream in, and saves a `SessionTranscript` when the session
/// ends (FR-012, FR-016). Only finalized segments are ever persisted — audio is never involved
/// (FR-011), matching `SessionTranscript`'s precondition.
@MainActor
public final class SessionRecorder {
    private var store: SessionTranscriptStore
    private var session: TranslationSession?

    public init(store: SessionTranscriptStore) {
        self.store = store
    }

    /// Points future `endSession()` saves at a different store (e.g. the user picked a new
    /// sessions folder) without affecting the in-progress session, if any.
    public func updateStore(_ store: SessionTranscriptStore) {
        self.store = store
    }

    public func beginSession(sources: Set<AudioSourceType>) {
        session = TranslationSession(startedAt: Date(), audioSources: sources)
    }

    /// The active session's start time, if any — lets callers suggest a default name
    /// (`SessionTranscript.defaultTitle(startedAt:)`) before the session is finalized/saved.
    public var activeSessionStartedAt: Date? { session?.startedAt }

    /// Whether the active session has anything worth naming and saving — mirrors the
    /// finalized-only filter `endSession()` applies, so callers can skip prompting for a name
    /// when there's nothing to persist (e.g. a session stopped before any speech finalized).
    public var hasFinalizedSegments: Bool {
        session?.segments.contains { $0.state == .finalized } ?? false
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

    /// Drops the current session without persisting anything — used when the user declines to
    /// save a just-ended session from the naming prompt (FR-012).
    public func discardSession() {
        session = nil
    }

    /// Ends the current session and persists its finalized segments as a `SessionTranscript`
    /// (FR-012). Segments that never reached `.finalized` (e.g. an utterance cut off mid-stream
    /// by a hard stop) are dropped, per `SessionTranscript`'s finalized-only precondition.
    @discardableResult
    public func endSession(title: String) throws -> SessionTranscript? {
        guard var session else { return nil }
        session.status = .stopped
        session.endedAt = Date()
        session.segments = session.segments.filter { $0.state == .finalized }
        self.session = nil

        guard !session.segments.isEmpty else { return nil }
        let transcript = SessionTranscript(session: session, title: title)
        try store.save(transcript)
        return transcript
    }
}
