import Foundation

/// A source of audio the engine can listen to (spec.md FR-001, FR-007).
public enum AudioSourceType: String, Codable, Hashable, Sendable {
    case microphone
    case systemAudio
}

/// macOS permission state for a given `AudioSourceType` (spec.md FR-010, FR-014).
public enum PermissionState: String, Codable, Hashable, Sendable {
    case notRequested
    case granted
    case denied
}

/// Lifecycle status of a `TranslationSession` (data-model.md).
public enum SessionStatus: String, Codable, Hashable, Sendable {
    case active
    case stopped
}

/// Lifecycle status of a `SpeechSegment` (data-model.md).
///
/// Transitions: `.recognizing -> .partiallyTranslated -> .finalized`, or directly
/// `.recognizing -> .finalized` for very short segments. Once `.finalized`, a segment's
/// `recognizedText` and `translation.text` MUST NOT change again (FR-005).
public enum SegmentState: String, Codable, Hashable, Sendable {
    case recognizing
    case partiallyTranslated
    case finalized
}

/// A chunk of raw audio samples handed from an `AudioCaptureSource` to an `ASRProvider`.
public struct AudioBuffer: Sendable {
    public let samples: [Int16]
    public let sampleRate: Double
    public let capturedAt: Date

    public init(samples: [Int16], sampleRate: Double, capturedAt: Date) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.capturedAt = capturedAt
    }
}
