import Foundation
import TranslationEngine

/// Owns the running `TranslationPipeline` for the current translation session and forwards its
/// events to the overlay (FR-001 through FR-006, FR-009). Started with User Story 1's system-audio
/// source only; extended for microphone + concurrent sources in User Story 2, and for
/// start/stop/source-loss handling in User Story 3.
@MainActor
public final class TranslationSessionController: ObservableObject {
    @Published public private(set) var isRunning: Bool = false
    /// Set when a source disappears mid-session (call ended, device disconnected — FR-014)
    /// rather than the user explicitly pressing stop. `nil` otherwise.
    @Published public private(set) var sourceLostMessage: String?
    /// Which language pair the next session will use. Fixed once a session is running — changing
    /// the ASR locale or translation language pack mid-stream isn't supported by either
    /// underlying provider.
    @Published public private(set) var direction: TranslationDirection = .englishToRussian

    public let overlayViewModel: OverlayViewModel

    /// Invoked for every translated event, in addition to updating the overlay — used by
    /// `SessionRecorder` (T037) to build the persisted transcript without this controller
    /// needing to know about storage.
    public var onEvent: ((TranslatedSegmentEvent) -> Void)?
    /// Invoked once a session ends, whether by explicit stop or source loss (FR-014) — used by
    /// `SessionRecorder` to finalize and save the transcript.
    public var onSessionEnded: (() -> Void)?

    private var pipeline: TranslationPipeline?
    private var eventTask: Task<Void, Never>?
    private var stoppedByUser = false
    /// Only set for multi-source sessions (FR-007) — filters out a segment that's just the
    /// microphone acoustically picking up the same speech already captured via system audio (or
    /// vice versa), which otherwise shows as two near-identical translated lines side by side
    /// (confirmed by user report + screenshot: "like" → "Как" appearing under both "Системный
    /// звук" and "Микрофон" moments apart).
    private var duplicateFilter: CrossSourceDuplicateFilter?

    public init(overlayViewModel: OverlayViewModel = OverlayViewModel()) {
        self.overlayViewModel = overlayViewModel
    }

    /// Picks the language pair for the next session (no-op while a session is already running).
    public func setDirection(_ direction: TranslationDirection) {
        guard !isRunning else { return }
        self.direction = direction
    }

    /// Starts a session listening to system audio only (User Story 1's independent test).
    public func startSystemAudioSession() throws {
        try start(sources: [.systemAudio])
    }

    /// Starts a session listening to the microphone only (User Story 2's independent test).
    public func startMicrophoneSession() throws {
        try start(sources: [.microphone])
    }

    /// Starts a session listening to both sources simultaneously (FR-007). Segments from each
    /// source stay attributed to it (never mixed, MultiSourceContractTests) and the overlay
    /// labels each line by source once more than one is active.
    public func startCombinedSession() throws {
        try start(sources: [.systemAudio, .microphone])
    }

    /// Starts a session with an arbitrary, non-empty set of audio sources (FR-001, FR-007).
    public func start(sources sourceTypes: Set<AudioSourceType>) throws {
        guard !isRunning else { return }
        precondition(!sourceTypes.isEmpty, "At least one audio source is required (FR-001, FR-007)")

        let sources: [AudioCaptureSource] = sourceTypes.map { sourceType in
            switch sourceType {
            case .systemAudio:
                let source = SystemAudioSource()
                source.onLevel = { [weak self] level in
                    Task { @MainActor in self?.overlayViewModel.audioLevel = level }
                }
                return source
            case .microphone:
                let source = MicrophoneSource()
                source.onLevel = { [weak self] level in
                    Task { @MainActor in self?.overlayViewModel.audioLevel = level }
                }
                return source
            }
        }
        let pipeline = TranslationPipeline(
            sources: sources,
            asr: makeASRProvider(),
            translation: makeTranslationProvider()
        )
        self.pipeline = pipeline
        overlayViewModel.reset()
        overlayViewModel.direction = direction
        overlayViewModel.showsSourceLabels = sourceTypes.count > 1
        sourceLostMessage = nil
        stoppedByUser = false
        duplicateFilter = sourceTypes.count > 1 ? CrossSourceDuplicateFilter() : nil

        pipeline.onError = { [weak self] error in
            Task { @MainActor in
                self?.overlayViewModel.reportError("\(error)")
            }
        }

        let stream = try pipeline.start()
        isRunning = true

        eventTask = Task { [weak self] in
            for await event in stream {
                // Speech recognition is locked to English (`SpeechAnalyzerASRProvider`); when the
                // interlocutor speaks a different language, its best-effort transcription is
                // often just punctuation with no actual letters, and translating that yields more
                // of the same — a stray "." in the overlay/history with nothing meaningful behind
                // it (confirmed by manual testing). Skipping it here also keeps it out of the
                // saved session transcript, not just the overlay.
                guard event.originalText.rangeOfCharacter(from: .letters) != nil else { continue }
                if self?.duplicateFilter?.shouldSuppress(event) == true { continue }
                self?.overlayViewModel.apply(event)
                self?.onEvent?(event)
            }
            guard let self else { return }
            // FR-014: if the stream ended on its own (not via stop()), a source was lost.
            if !self.stoppedByUser {
                self.sourceLostMessage = "Источник звука пропал во время сессии (например, завершился звонок). Перевод остановлен."
            }
            self.isRunning = false
            self.onSessionEnded?()
        }
    }

    public func stop() {
        stoppedByUser = true
        let pipelineToStop = pipeline
        eventTask?.cancel()
        eventTask = nil
        pipeline = nil
        isRunning = false
        onSessionEnded?()

        // Core Audio teardown (AudioHardwareDestroyAggregateDevice/DestroyProcessTap etc.) can
        // involve slow IPC round-trips to coreaudiod. Running it inline here — on the main
        // actor, since this whole class is @MainActor — froze the menu/UI until it completed
        // (confirmed by manual testing: the app appeared to hang after clicking "Stop"). All UI
        // state above is already updated synchronously; the actual hardware tear-down can finish
        // whenever it finishes, off the main thread.
        Task.detached(priority: .userInitiated) {
            pipelineToStop?.stop()
        }
    }

    private func makeASRProvider() -> ASRProvider {
        if #available(macOS 26.0, *) {
            return SpeechAnalyzerASRProvider(locale: direction.speechLocale)
        }
        fatalError("RealtimeTranslator requires macOS 26 or later")
    }

    // Wrapped in `GlossaryTranslationProvider` (English→Russian only — see
    // `TranslationDirection.appliesGlossary`) so common IT jargon (pull request, backend,
    // deploy, …) comes through as what a Russian-speaking developer would actually say instead
    // of Apple's more literal/formal translation.
    private func makeTranslationProvider() -> TranslationProvider {
        if #available(macOS 26.0, *) {
            let apple = AppleTranslationProvider(source: direction.sourceLanguage, target: direction.targetLanguage)
            return direction.appliesGlossary ? GlossaryTranslationProvider(wrapping: apple) : apple
        }
        fatalError("RealtimeTranslator requires macOS 26 or later")
    }
}

/// Drops a segment from one source when its recognized (original-language) text closely matches
/// a segment already tracked from a *different* source within a short time window — the signature
/// of one source acoustically leaking into the other (e.g. a call's audio playing through
/// speakers and being picked up by the microphone too), rather than genuinely distinct concurrent
/// speech. Whichever source's matching segment is *first* seen for a given piece of speech is the
/// one kept on screen; the later-arriving duplicate is suppressed for its whole lifetime (it keeps
/// the same `segmentId` across its partial → final updates).
///
/// Deliberately text-based rather than audio-based (e.g. real echo cancellation): both sources are
/// already independently transcribed by the time this runs, and comparing the resulting short
/// phrases is far simpler than correlating raw audio between two differently-latent capture paths.
@MainActor
private final class CrossSourceDuplicateFilter {
    private struct TrackedSegment {
        let sourceType: AudioSourceType
        var normalizedText: String
        var lastSeen: Date
    }

    private let window: TimeInterval
    private let similarityThreshold: Double
    private var trackedBySegment: [UUID: TrackedSegment] = [:]
    private var suppressedSegments: Set<UUID> = []

    init(window: TimeInterval = 6, similarityThreshold: Double = 0.6) {
        self.window = window
        self.similarityThreshold = similarityThreshold
    }

    /// - Returns: `true` if `event` is a cross-source duplicate and should not be shown/recorded.
    func shouldSuppress(_ event: TranslatedSegmentEvent, now: Date = Date()) -> Bool {
        trackedBySegment = trackedBySegment.filter { now.timeIntervalSince($0.value.lastSeen) <= window }

        if suppressedSegments.contains(event.segmentId) {
            return true
        }

        let normalized = Self.normalize(event.originalText)
        if trackedBySegment[event.segmentId] != nil {
            // Already accepted and showing — keep updating it, but never re-evaluate (and
            // possibly retroactively hide) a line the user has already seen.
            trackedBySegment[event.segmentId]?.normalizedText = normalized
            trackedBySegment[event.segmentId]?.lastSeen = now
            return false
        }

        let isDuplicate = trackedBySegment.values.contains { tracked in
            tracked.sourceType != event.sourceType
                && Self.similarity(tracked.normalizedText, normalized) >= similarityThreshold
        }
        if isDuplicate {
            suppressedSegments.insert(event.segmentId)
            return true
        }

        trackedBySegment[event.segmentId] = TrackedSegment(
            sourceType: event.sourceType,
            normalizedText: normalized,
            lastSeen: now
        )
        return false
    }

    private static func normalize(_ text: String) -> String {
        let scalars = text.lowercased().unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    private static func similarity(_ a: String, _ b: String) -> Double {
        let wordsA = Set(a.split(separator: " "))
        let wordsB = Set(b.split(separator: " "))
        guard !wordsA.isEmpty, !wordsB.isEmpty else { return 0 }
        let union = wordsA.union(wordsB).count
        guard union > 0 else { return 0 }
        return Double(wordsA.intersection(wordsB).count) / Double(union)
    }
}
