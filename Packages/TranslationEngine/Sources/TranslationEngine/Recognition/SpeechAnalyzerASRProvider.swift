@preconcurrency import AVFAudio
import Foundation
import Speech

/// `ASRProvider` adapter over Apple's on-device `SpeechAnalyzer`/`SpeechTranscriber`
/// (research.md §1). Requires macOS 26+.
///
/// One `SpeechAnalyzer` + `SpeechTranscriber` pair is created per call to `recognize`, matching
/// one `AudioCaptureSource`'s lifetime. `SpeechTranscriber.Preset.progressiveTranscription` is
/// used specifically because it reports incremental (volatile) results before finalization,
/// which is what FR-004/FR-005 require.
@available(macOS 26.0, *)
public final class SpeechAnalyzerASRProvider: ASRProvider, @unchecked Sendable {
    private let locale: Locale

    /// - Parameter locale: the interlocutor's speech locale to recognize (spec.md: fixed to
    ///   English for this feature — see Assumptions).
    public init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
    }

    public func recognize(_ buffers: AsyncStream<AudioBuffer>, sourceType: AudioSourceType) -> AsyncStream<RecognizedSegmentUpdate> {
        let locale = self.locale
        return AsyncStream { continuation in
            let task = Task {
                do {
                    let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)

                    // Locales must be explicitly reserved before a module using them can be run
                    // ("Cannot use modules with unallocated locales" — confirmed via manual
                    // testing), and the on-device asset must be installed, downloading it if
                    // necessary. Both are one-time, per-locale steps enforced by the Speech
                    // framework itself, not a network call this app makes on every request.
                    let status = await AssetInventory.status(forModules: [transcriber])
                    if status != .installed {
                        EngineLog.error("SpeechAnalyzerASRProvider: asset status for \(locale.identifier) = \(status); requesting install")
                        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                            try await request.downloadAndInstall()
                        }
                    }
                    _ = try await AssetInventory.reserve(locale: locale)

                    let analyzer = SpeechAnalyzer(modules: [transcriber])
                    guard let audioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                        EngineLog.error("SpeechAnalyzerASRProvider: no compatible audio format for locale \(locale.identifier)")
                        continuation.finish()
                        return
                    }

                    let (inputSequence, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()

                    // Feed every captured AudioBuffer into the analyzer as an AnalyzerInput.
                    // The AVAudioConverter is created once and reused across the whole capture
                    // (not per buffer!) — recreating it ~100x/sec was expensive enough to make
                    // the pipeline fall behind real-time and never catch up within a session.
                    let feedTask = Task {
                        let converterBox = AudioConverterBox()
                        for await buffer in buffers {
                            if let pcmBuffer = buffer.makePCMBuffer(matching: audioFormat, reusing: converterBox) {
                                inputContinuation.yield(AnalyzerInput(buffer: pcmBuffer))
                            }
                        }
                        inputContinuation.finish()
                    }

                    // Consume results concurrently with feeding input.
                    async let analysis: Void = analyzer.start(inputSequence: inputSequence)

                    var currentSegmentId = UUID()
                    var currentSegmentStartedAt: Date?

                    // data-model.md's finalization policy for SpeechSegment: finalize on the
                    // ASR's own utterance boundary OR after this maximum duration, whichever
                    // comes first — documented during /speckit-analyze remediation but never
                    // actually wired up until now. Without it, a segment during continuous,
                    // uninterrupted speech (a call/video with no clean pause) never finalizes:
                    // confirmed by manual testing — a session ran 2+ minutes past a segment's
                    // last partial update with no further progress ever surfaced.
                    let maxSegmentDuration: TimeInterval = 15

                    for try await result in transcriber.results {
                        let now = Date()
                        if currentSegmentStartedAt == nil {
                            currentSegmentStartedAt = now
                        }
                        let startedAt = currentSegmentStartedAt ?? now
                        let text = String(result.text.characters)
                        let forcedFinal = now.timeIntervalSince(startedAt) >= maxSegmentDuration
                        let isFinal = result.isFinal || forcedFinal
                        if forcedFinal && !result.isFinal {
                            EngineLog.error("SpeechAnalyzerASRProvider: forcing segment finalization after \(maxSegmentDuration)s")
                        }
                        continuation.yield(
                            RecognizedSegmentUpdate(
                                segmentId: currentSegmentId,
                                sourceType: sourceType,
                                text: text,
                                isFinal: isFinal,
                                startedAt: startedAt
                            )
                        )
                        if isFinal {
                            currentSegmentId = UUID()
                            currentSegmentStartedAt = nil
                        }
                    }

                    _ = try await analysis
                    feedTask.cancel()
                } catch {
                    EngineLog.error("SpeechAnalyzerASRProvider failed: \(error)")
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Caches an `AVAudioConverter` across many buffers from the same source, rebuilding it only if
/// the incoming sample rate actually changes (it shouldn't, mid-capture, but sources aren't
/// contractually guaranteed constant). A class (not a struct/inout tuple) so it can be captured
/// by reference in the feed loop without re-threading state through every call.
private final class AudioConverterBox {
    var sourceFormat: AVAudioFormat?
    var converter: AVAudioConverter?
}

extension AudioBuffer {
    /// Converts this engine-agnostic buffer into an `AVAudioPCMBuffer` in the analyzer's
    /// preferred format. `AudioBuffer.samples` are engine-side Int16 PCM (see CoreTypes.swift).
    /// Reuses `box`'s cached `AVAudioConverter` across calls instead of constructing a new one
    /// per buffer, which is expensive enough (tens of times per second) to make the recognizer
    /// fall behind real-time.
    fileprivate func makePCMBuffer(matching format: AVAudioFormat, reusing box: AudioConverterBox) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
            let sourceFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: true
            ),
            let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count))
        else { return nil }

        sourceBuffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { pointer in
            sourceBuffer.int16ChannelData?[0].update(from: pointer.baseAddress!, count: samples.count)
        }

        guard sourceFormat != format else { return sourceBuffer }

        if box.sourceFormat != sourceFormat || box.converter == nil {
            box.sourceFormat = sourceFormat
            box.converter = AVAudioConverter(from: sourceFormat, to: format)
        }
        guard let converter = box.converter else { return nil }

        let ratio = format.sampleRate / sourceFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(sourceBuffer.frameLength) * ratio) + 16
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputCapacity) else { return nil }

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, inputStatus in
            inputStatus.pointee = .haveData
            return sourceBuffer
        }
        if let error {
            EngineLog.error("AudioBuffer conversion failed: \(error)")
            return nil
        }
        return outputBuffer
    }
}
