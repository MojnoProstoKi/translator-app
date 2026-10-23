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
    /// Which language pair the current session is using — lets `OverlayView` label the
    /// recognized/translated lines correctly regardless of direction.
    @Published public var direction: TranslationDirection = .englishToRussian
    /// Transient consent-reminder banner text (FR-015). Set/cleared by
    /// `ConsentReminderPresenter`; `nil` when no reminder is currently shown.
    @Published public var consentBannerText: String?
    /// A persistent (not auto-dismissing) error banner — e.g. "language pack not installed".
    /// Distinct from `consentBannerText`, which is informational and always auto-clears.
    @Published public var errorBannerText: String?
    /// Live captured-audio peak level (0...1), driven by `SystemAudioSource`/`MicrophoneSource`'s
    /// `onLevel` — powers the equalizer-style meter so the user can see *when* to speak/play
    /// audio instead of guessing (requested explicitly).
    @Published public var audioLevel: Float = 0
    /// Whether the overlay is collapsed into a one-line strip showing only the newest
    /// translation. Purely visual — the session keeps running and recording either way.
    /// `OverlayWindowController` observes this to resize the panel.
    @Published public var isCompact: Bool = false

    /// What the compact strip shows: the error if there is one, otherwise the newest line's
    /// translation (partial or final), or `nil` while nothing has been translated yet.
    public var compactText: String? {
        if let errorBannerText { return errorBannerText }
        return lines.last(where: { !$0.translatedText.isEmpty })?.translatedText
    }

    private let maxVisibleLines: Int

    /// 50 (not the old fixed-at-4 limit) now that `OverlayView`'s transcript scrolls — this is
    /// just a sane bound on a single session's in-memory history, not a "visible at once" cap.
    public init(maxVisibleLines: Int = 50) {
        self.maxVisibleLines = maxVisibleLines
    }

    /// Applies one pipeline event: updates the line for its segment if present, otherwise
    /// appends a new one, then trims to `maxVisibleLines` (oldest finalized lines drop first).
    public func apply(_ event: TranslatedSegmentEvent) {
        // A prior segment's failure (`reportError`) must not permanently hide the transcript once
        // translation recovers — any event reaching here proves it has (confirmed by manual
        // testing: without this, the overlay got stuck on a stale error even though translation
        // was working again for every segment after the one that failed).
        errorBannerText = nil
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

    public func toggleCompact() {
        isCompact.toggle()
    }

    public func reportError(_ message: String) {
        errorBannerText = message
    }

    public func reset() {
        lines.removeAll()
        errorBannerText = nil
        audioLevel = 0
    }
}
