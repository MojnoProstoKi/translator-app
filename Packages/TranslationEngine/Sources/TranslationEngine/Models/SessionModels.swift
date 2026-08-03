import Foundation

/// A translation session: the period from starting to stopping listening on one or more
/// audio sources (data-model.md → TranslationSession).
public struct TranslationSession: Codable, Sendable, Identifiable {
    public let id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var audioSources: Set<AudioSourceType>
    public var status: SessionStatus
    public var segments: [SpeechSegment]

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        audioSources: Set<AudioSourceType>,
        status: SessionStatus = .active,
        segments: [SpeechSegment] = []
    ) {
        precondition(!audioSources.isEmpty, "A session MUST have at least one audio source (FR-001, FR-007)")
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.audioSources = audioSources
        self.status = status
        self.segments = segments
    }
}

/// A continuous, recognized chunk of the interlocutor's English speech (data-model.md → SpeechSegment).
public struct SpeechSegment: Codable, Sendable, Identifiable {
    public let id: UUID
    public let sessionId: UUID
    public let sourceType: AudioSourceType
    public let startedAt: Date
    public private(set) var state: SegmentState
    public private(set) var recognizedText: String
    public private(set) var translation: SegmentTranslation

    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        sourceType: AudioSourceType,
        startedAt: Date,
        state: SegmentState = .recognizing,
        recognizedText: String = "",
        translation: SegmentTranslation = SegmentTranslation(text: "", isFinal: false, updatedAt: Date())
    ) {
        self.id = id
        self.sessionId = sessionId
        self.sourceType = sourceType
        self.startedAt = startedAt
        self.state = state
        self.recognizedText = recognizedText
        self.translation = translation
    }

    /// Applies an updated recognized/translated text to this segment.
    ///
    /// - Precondition: the segment MUST NOT already be `.finalized` (FR-005: once finalized,
    ///   text is immutable).
    public mutating func apply(recognizedText: String, translatedText: String, isFinal: Bool, at date: Date) {
        precondition(state != .finalized, "Cannot update a finalized SpeechSegment (FR-005)")
        self.recognizedText = recognizedText
        self.translation = SegmentTranslation(text: translatedText, isFinal: isFinal, updatedAt: date)
        self.state = isFinal ? .finalized : .partiallyTranslated
    }
}

/// The Russian-language translation attached to a `SpeechSegment` (data-model.md → SegmentTranslation).
public struct SegmentTranslation: Codable, Sendable {
    public var text: String
    public var isFinal: Bool
    public var updatedAt: Date

    public init(text: String, isFinal: Bool, updatedAt: Date) {
        self.text = text
        self.isFinal = isFinal
        self.updatedAt = updatedAt
    }
}

/// A finalized speech segment as persisted in a `SessionTranscript` — deliberately leaner than
/// the live `SpeechSegment` (data-model.md → SessionTranscript). Once finalized, `sessionId`
/// duplicates the transcript's own id, `sourceType`/`startedAt` are already covered by the
/// transcript's own `audioSources`/`startedAt`, and `state`/`translation.isFinal` are always
/// `.finalized`/`true` — none of that carries information a person reading the saved file back
/// actually needs, so only the recognized English text and its Russian translation remain.
public struct TranscriptSegment: Codable, Sendable, Identifiable {
    public let id: UUID
    public let originalText: String
    public let translatedText: String

    public init(id: UUID, originalText: String, translatedText: String) {
        self.id = id
        self.originalText = originalText
        self.translatedText = translatedText
    }
}

/// Persistent, per-session record of finalized speech segments and their translations
/// (data-model.md → SessionTranscript). Deliberately contains no audio (FR-011).
public struct SessionTranscript: Codable, Sendable {
    public let sessionId: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let audioSources: Set<AudioSourceType>
    public let finalizedSegments: [TranscriptSegment]
    public let title: String

    public init(session: TranslationSession, title: String) {
        precondition(
            session.segments.allSatisfy { $0.state == .finalized },
            "SessionTranscript MUST only contain finalized segments"
        )
        self.sessionId = session.id
        self.startedAt = session.startedAt
        self.endedAt = session.endedAt
        self.audioSources = session.audioSources
        self.finalizedSegments = session.segments.map {
            TranscriptSegment(id: $0.id, originalText: $0.recognizedText, translatedText: $0.translation.text)
        }
        self.title = title
    }

    /// The name suggested when saving a session, and the fallback used when reading back a
    /// session saved before this field existed (no `title` key in its JSON).
    public static func defaultTitle(startedAt: Date) -> String {
        startedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId, startedAt, endedAt, audioSources, finalizedSegments, title
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(UUID.self, forKey: .sessionId)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        audioSources = try container.decode(Set<AudioSourceType>.self, forKey: .audioSources)
        finalizedSegments = try container.decode([TranscriptSegment].self, forKey: .finalizedSegments)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? Self.defaultTitle(startedAt: startedAt)
    }
}

/// Lightweight projection of `SessionTranscript` used to list past sessions (FR-016) without
/// loading each transcript's full segment list (data-model.md → SessionTranscriptSummary).
public struct SessionTranscriptSummary: Codable, Sendable, Identifiable {
    public var id: UUID { sessionId }
    public let sessionId: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let sourceTypes: Set<AudioSourceType>
    public let title: String

    public init(sessionId: UUID, startedAt: Date, endedAt: Date?, sourceTypes: Set<AudioSourceType>, title: String) {
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sourceTypes = sourceTypes
        self.title = title
    }

    public init(transcript: SessionTranscript) {
        self.init(
            sessionId: transcript.sessionId,
            startedAt: transcript.startedAt,
            endedAt: transcript.endedAt,
            sourceTypes: transcript.audioSources,
            title: transcript.title
        )
    }
}
