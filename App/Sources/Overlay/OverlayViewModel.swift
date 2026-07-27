import Foundation
import SwiftUI
import TranslationEngine

/// One line of translated text as shown in the overlay. Distinct from `SpeechSegment` (the
/// persisted domain model) — this is purely ephemeral UI state, bounded in size since the
/// overlay only ever needs to show the last few lines, not the full session history (FR-016
/// history lives in `SessionTranscriptStore`/`SessionHistoryView`, not here).
public struct OverlayLine: Identifiable, Equatable {
    public let id: UUID
    public var sourceType: AudioSourceType
    /// Recognized English text (shown alongside the translation so the user can tell apart
    /// "recognition isn't working" from "translation isn't working" — requested explicitly
    /// after debugging a case where only a translation artifact was visible).
    public var originalText: String
    public var translatedText: String
    public var isFinal: Bool
}

/// Drives `OverlayView`'s content as `TranslatedSegmentEvent`s stream in from a
/// `TranslationPipeline` (FR-004, FR-005: incremental, then finalized, translation text).
@MainActor
public final class OverlayViewModel: ObservableObject {
    @Published public private(set) var lines: [OverlayLine] = []
    /// Whether more than one audio source is active — the view shows a source label per line
    /// only when this is true (US2: FR-007 concurrent sources shouldn't be visually mixed up).
    @Published public var showsSourceLabels: Bool = false
    /// Transient consent-reminder banner text (FR-015). Set/cleared by
    /// `ConsentReminderPresenter`; `nil` when no reminder is currently shown.
    @Published public var consentBannerText: String?
    /// Shown while the session is starting, before the first event or error arrives (asset
    /// checks/downloads for Speech/Translation can take a few seconds) — requested explicitly
    /// so the user isn't left guessing whether anything is happening.
    @Published public var isPreparing: Bool = false
    /// A persistent (not auto-dismissing) error banner — e.g. "language pack not installed".
    /// Distinct from `consentBannerText`, which is informational and always auto-clears.
    @Published public var errorBannerText: String?
    /// Total `TranslatedSegmentEvent`s received this session — shown as a small always-visible
    /// counter so it's immediately obvious whether the pipeline is producing *anything* at all,
    /// without needing Console/log inspection to tell "zero events" apart from "events with
    /// empty text".
    @Published public private(set) var eventCount: Int = 0
    /// Live captured-audio peak level (0...1), driven by `SystemAudioSource`/`MicrophoneSource`'s
    /// `onLevel` — powers the equalizer-style meter so the user can see *when* to speak/play
    /// audio instead of guessing (requested explicitly).
    @Published public var audioLevel: Float = 0

    private let maxVisibleLines: Int

    public init(maxVisibleLines: Int = 4) {
        self.maxVisibleLines = maxVisibleLines
    }

    /// Applies one pipeline event: updates the line for its segment if present, otherwise
    /// appends a new one, then trims to `maxVisibleLines` (oldest finalized lines drop first).
    public func apply(_ event: TranslatedSegmentEvent) {
        isPreparing = false
        eventCount += 1
        if let index = lines.firstIndex(where: { $0.id == event.segmentId }) {
            lines[index].originalText = event.originalText
            lines[index].translatedText = event.translatedText
            lines[index].isFinal = event.isFinal
        } else {
            lines.append(
                OverlayLine(
                    id: event.segmentId,
                    sourceType: event.sourceType,
                    originalText: event.originalText,
                    translatedText: event.translatedText,
                    isFinal: event.isFinal
                )
            )
        }
        if lines.count > maxVisibleLines {
            lines.removeFirst(lines.count - maxVisibleLines)
        }
    }

    public func reportError(_ message: String) {
        isPreparing = false
        errorBannerText = message
    }

    public func reset() {
        lines.removeAll()
        errorBannerText = nil
        isPreparing = true
        eventCount = 0
        audioLevel = 0
    }
}
