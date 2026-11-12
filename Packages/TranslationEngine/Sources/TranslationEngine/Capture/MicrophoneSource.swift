import AVFoundation
import Foundation

/// `AudioCaptureSource` that captures the device microphone via `AVAudioEngine` (research.md
/// §4) — used for in-person conversations where the interlocutor's speech reaches the user's
/// Mac through its microphone rather than a call app's system audio output (User Story 2).
///
/// ⚠️ Verification status: compiles against the real SDK; runtime capture has not been
/// exercised end-to-end in this session (requires a live, interactively-granted microphone
/// permission — see SystemAudioSource.swift for the same caveat).
public final class MicrophoneSource: AudioCaptureSource, @unchecked Sendable {
    public let sourceType: AudioSourceType = .microphone

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var permission: PermissionState = .notRequested

    public var permissionState: PermissionState {
        get async { lock.withLock { permission } }
    }

    /// Reports the current captured audio's peak level (0...1) at UI-refresh rate — drives the
    /// live level meter (see SystemAudioSource.swift's `onLevel` for the same mechanism).
    public var onLevel: (@Sendable (Float) -> Void)?
    private var lastLevelReportedAt = Date.distantPast

    /// Apple's voice processing (acoustic echo cancellation, the same one FaceTime uses): subtracts
    /// what the Mac is playing through its speakers from the mic signal, so the interlocutor's
    /// voice from a call doesn't get recognized a second time as "microphone". Only worth it when
    /// system audio is captured at the same time — it also colours the mic sound a little.
    private let voiceProcessing: Bool

    public init(voiceProcessing: Bool = false) {
        self.voiceProcessing = voiceProcessing
    }

    private func enableVoiceProcessingIfRequested(on inputNode: AVAudioInputNode) {
        guard voiceProcessing else { return }
        do {
            try inputNode.setVoiceProcessingEnabled(true)
            // By default voice processing turns every other app's audio down while the mic is
            // open — that would make the call itself quieter. Keep that to the minimum.
            inputNode.voiceProcessingOtherAudioDuckingConfiguration = AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
                enableAdvancedDucking: false,
                duckingLevel: .min
            )
            EngineLog.info("MicrophoneSource: voice processing enabled, format \(inputNode.outputFormat(forBus: 0))")
        } catch {
            // Not fatal: fall back to the raw mic; the text-based duplicate filter still applies.
            EngineLog.error("MicrophoneSource: could not enable voice processing: \(error)")
        }
    }

    public func requestPermission() async -> PermissionState {
        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        let state: PermissionState = granted ? .granted : .denied
        lock.withLock { permission = state }
        return state
    }

    public func start() throws -> AsyncStream<AudioBuffer> {
        let inputNode = engine.inputNode
        enableVoiceProcessingIfRequested(on: inputNode)
        // Read after enabling voice processing — it changes the input node's format.
        let format = inputNode.outputFormat(forBus: 0)

        return AsyncStream { continuation in
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.reportLevelIfDue(for: buffer)
                if let audioBuffer = buffer.toAudioBuffer(sampleRate: format.sampleRate) {
                    continuation.yield(audioBuffer)
                }
            }

            do {
                engine.prepare()
                try engine.start()
            } catch {
                EngineLog.error("MicrophoneSource failed to start engine: \(error)")
                inputNode.removeTap(onBus: 0)
                continuation.finish()
                return
            }

            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
        }
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func reportLevelIfDue(for buffer: AVAudioPCMBuffer) {
        guard onLevel != nil, let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var peak: Float = 0
        for index in 0..<frameLength {
            peak = max(peak, abs(channelData[0][index]))
        }

        let shouldReport: Bool = lock.withLock {
            let now = Date()
            guard now.timeIntervalSince(lastLevelReportedAt) >= 0.06 else { return false }
            lastLevelReportedAt = now
            return true
        }
        if shouldReport {
            onLevel?(peak)
        }
    }
}
