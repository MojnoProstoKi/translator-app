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

/// Persistent, per-session record of finalized speech segments and their translations
/// (data-model.md → SessionTranscript). Deliberately contains no audio (FR-011).
public struct SessionTranscript: Codable, Sendable {
    public let sessionId: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let audioSources: Set<AudioSourceType>
    public let finalizedSegments: [SpeechSegment]

    public init(session: TranslationSession) {
        precondition(
            session.segments.allSatisfy { $0.state == .finalized },
            "SessionTranscript MUST only contain finalized segments"
        )
        self.sessionId = session.id
        self.startedAt = session.startedAt
        self.endedAt = session.endedAt
        self.audioSources = session.audioSources
        self.finalizedSegments = session.segments
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

    public init(sessionId: UUID, startedAt: Date, endedAt: Date?, sourceTypes: Set<AudioSourceType>) {
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sourceTypes = sourceTypes
    }

    public init(transcript: SessionTranscript) {
        self.init(
            sessionId: transcript.sessionId,
            startedAt: transcript.startedAt,
            endedAt: transcript.endedAt,
            sourceTypes: transcript.audioSources
        )
    }
}
