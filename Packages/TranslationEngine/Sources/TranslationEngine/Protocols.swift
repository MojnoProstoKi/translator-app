import Foundation

/// Public API surface of `TranslationEngine` — see
/// specs/001-realtime-speech-translation/contracts/translation-engine-api.md.
///
/// Provider-specific logic (Apple Speech / Translation frameworks, Core Audio Taps, etc.) is
/// isolated behind these protocols so it can be swapped without changing calling code
/// (Constitution → Additional Constraints: provider isolation).

/// A concrete source of audio the engine can capture from (microphone or system audio).
public protocol AudioCaptureSource: Sendable {
    var sourceType: AudioSourceType { get }
    var permissionState: PermissionState { get async }

    /// Requests the macOS permission for this source, returning the resulting state (FR-010).
    func requestPermission() async -> PermissionState

    /// Starts capturing audio, returning a stream of buffers. Throws if permission is not
    /// granted or the source is otherwise unavailable.
    func start() throws -> AsyncStream<AudioBuffer>

    /// Stops capturing audio for this source (FR-008).
    func stop()
}

/// An update to a `SpeechSegment`'s recognized (English) text, emitted as it is refined
/// (FR-004, FR-005).
public struct RecognizedSegmentUpdate: Sendable {
    public let segmentId: UUID
    public let sourceType: AudioSourceType
    public let text: String
    public let isFinal: Bool
    public let startedAt: Date

    public init(segmentId: UUID, sourceType: AudioSourceType, text: String, isFinal: Bool, startedAt: Date) {
        self.segmentId = segmentId
        self.sourceType = sourceType
        self.text = text
        self.isFinal = isFinal
        self.startedAt = startedAt
    }
}

/// On-device speech recognition provider (e.g. `SpeechAnalyzer`/`SpeechTranscriber`).
///
/// MUST NOT perform any network I/O (FR-006).
public protocol ASRProvider: Sendable {
    /// Consumes buffers of one audio source and emits recognized segment updates.
    ///
    /// Implementations MUST NOT emit a new segment while the input stream contains no
    /// detectable speech (silence/background noise only) — FR-013.
    func recognize(_ buffers: AsyncStream<AudioBuffer>, sourceType: AudioSourceType) -> AsyncStream<RecognizedSegmentUpdate>
}

/// On-device translation provider (e.g. Apple `TranslationSession`, English → Russian).
///
/// MUST NOT perform any network I/O (FR-006).
public protocol TranslationProvider: Sendable {
    func translate(_ text: String, isFinal: Bool) async throws -> String
}

/// A translated update to a `SpeechSegment`, combining the recognized text with its Russian
/// translation (FR-003, FR-004, FR-005).
public struct TranslatedSegmentEvent: Sendable, Codable {
    public let segmentId: UUID
    public let sourceType: AudioSourceType
    public let originalText: String
    public let translatedText: String
    public let isFinal: Bool
    /// Time elapsed between `RecognizedSegmentUpdate.startedAt` and this event (SC-001).
    public let latency: TimeInterval

    public init(
        segmentId: UUID,
        sourceType: AudioSourceType,
        originalText: String,
        translatedText: String,
        isFinal: Bool,
        latency: TimeInterval
    ) {
        self.segmentId = segmentId
        self.sourceType = sourceType
        self.originalText = originalText
        self.translatedText = translatedText
        self.isFinal = isFinal
        self.latency = latency
    }
}

/// Persists and retrieves per-session transcripts (FR-012, FR-016). One file per session;
/// audio is never persisted (FR-011).
public protocol SessionTranscriptStore: Sendable {
    func save(_ transcript: SessionTranscript) throws
    func listSessions() throws -> [SessionTranscriptSummary]
    func delete(sessionId: UUID) throws
}
