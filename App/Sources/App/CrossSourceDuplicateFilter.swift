import Foundation
import TranslationEngine

/// Hides microphone segments that are really the interlocutor's voice coming out of the speakers
/// and leaking into the mic, while system audio is captured at the same time — the same phrase
/// would otherwise appear twice, once per source.
///
/// Rules:
/// - System audio is never suppressed: it is the clean copy of the call's audio, and the user's
///   own voice never ends up in it, so a matching pair is always the mic hearing the speakers.
/// - A mic segment is re-checked on **every** update, not only the first one. Its first partial
///   is often one or two words ("It"), and the old filter decided once on that and never looked
///   again, so the duplicate slipped through whenever the mic's recognition got ahead of or
///   behind system audio (depends on speaker volume, voice, room).
/// - When a system segment arrives after its mic copy is already on screen, the mic line is
///   retracted.
/// - A non-final mic segment that stops matching is shown again (it was the user's own speech
///   that happened to start with the same word); once a final mic segment matches, it stays hidden.
///
/// Text-based on purpose: both sources are already transcribed independently by the time this
/// runs, and comparing short phrases is much simpler than real acoustic echo cancellation.
@MainActor
final class CrossSourceDuplicateFilter {
    struct Decision: Equatable {
        /// Whether this event should be shown and recorded.
        var shows: Bool
        /// Segments that were already shown and must now be taken back (overlay and recording).
        var retractedSegmentIds: [UUID] = []
    }

    private struct Tracked {
        let sourceType: AudioSourceType
        var words: [String]
        var lastSeen: Date
        var isFinal: Bool
        var isShown: Bool
    }

    private let window: TimeInterval
    private let similarityThreshold: Double
    private var tracked: [UUID: Tracked] = [:]
    /// Mic segments confirmed as duplicates for good — later updates are dropped without checks.
    private var lockedDuplicates: Set<UUID> = []

    init(window: TimeInterval = 6, similarityThreshold: Double = 0.6) {
        self.window = window
        self.similarityThreshold = similarityThreshold
    }

    func process(_ event: TranslatedSegmentEvent, now: Date = Date()) -> Decision {
        tracked = tracked.filter { now.timeIntervalSince($0.value.lastSeen) <= window }
        if lockedDuplicates.contains(event.segmentId) {
            return Decision(shows: false)
        }

        let words = Self.words(event.originalText)
        let wasShown = tracked[event.segmentId]?.isShown ?? false
        var entry = Tracked(
            sourceType: event.sourceType,
            words: words,
            lastSeen: now,
            isFinal: event.isFinal,
            isShown: wasShown
        )

        switch event.sourceType {
        case .microphone:
            let matchesSystemAudio = tracked.contains { id, other in
                id != event.segmentId && other.sourceType == .systemAudio && isDuplicate(words, other.words)
            }
            if matchesSystemAudio {
                if event.isFinal {
                    lockedDuplicates.insert(event.segmentId)
                    tracked[event.segmentId] = nil
                } else {
                    entry.isShown = false
                    tracked[event.segmentId] = entry
                }
                return Decision(shows: false, retractedSegmentIds: wasShown ? [event.segmentId] : [])
            }
            entry.isShown = true
            tracked[event.segmentId] = entry
            return Decision(shows: true)

        case .systemAudio:
            entry.isShown = true
            tracked[event.segmentId] = entry
            var retracted: [UUID] = []
            for (id, other) in tracked where other.sourceType == .microphone && isDuplicate(other.words, words) {
                if other.isShown { retracted.append(id) }
                if other.isFinal {
                    lockedDuplicates.insert(id)
                    tracked[id] = nil
                } else {
                    tracked[id]?.isShown = false
                }
            }
            return Decision(shows: true, retractedSegmentIds: retracted)
        }
    }

    /// Overlap coefficient (shared words / words in the shorter phrase) rather than Jaccard, so a
    /// short partial that is a prefix of the other source's longer text still counts as a match.
    /// Phrases of one or two words must match completely, longer ones need at least two shared words.
    private func isDuplicate(_ a: [String], _ b: [String]) -> Bool {
        let setA = Set(a), setB = Set(b)
        let smaller = min(setA.count, setB.count)
        guard smaller > 0 else { return false }
        let shared = setA.intersection(setB).count
        if smaller <= 2 { return shared == smaller }
        return shared >= 2 && Double(shared) / Double(smaller) >= similarityThreshold
    }

    private static func words(_ text: String) -> [String] {
        let scalars = text.lowercased().unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars).split(separator: " ").map(String.init)
    }
}
