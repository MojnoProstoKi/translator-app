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

    public init(overlayViewModel: OverlayViewModel = OverlayViewModel()) {
        self.overlayViewModel = overlayViewModel
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
        overlayViewModel.showsSourceLabels = sourceTypes.count > 1
        sourceLostMessage = nil
        stoppedByUser = false

        pipeline.onError = { [weak self] error in
            Task { @MainActor in
                self?.overlayViewModel.reportError("\(error)")
            }
        }

        let stream = try pipeline.start()
        isRunning = true

        eventTask = Task { [weak self] in
            for await event in stream {
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
            return SpeechAnalyzerASRProvider()
        }
        fatalError("RealtimeTranslator requires macOS 26 or later")
    }

    private func makeTranslationProvider() -> TranslationProvider {
        if #available(macOS 26.0, *) {
            return AppleTranslationProvider()
        }
        fatalError("RealtimeTranslator requires macOS 26 or later")
    }
}
