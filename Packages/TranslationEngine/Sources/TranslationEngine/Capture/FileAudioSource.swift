import AVFAudio
import Foundation

/// An `AudioCaptureSource` that streams a pre-recorded WAV file in chunks, as if it were live
/// audio. Used by `translate-cli` (contracts/translate-cli.md) and by integration tests that
/// exercise the real ASR/translation pipeline against fixtures (Packages/TranslationEngine/Tests
/// /Fixtures — see FIXTURES_REFERENCE.md) without requiring a live microphone or system-audio
/// permission grant for the *capture* step.
public final class FileAudioSource: AudioCaptureSource, @unchecked Sendable {
    public let sourceType: AudioSourceType
    private let fileURL: URL
    private let chunkDuration: TimeInterval

    public var permissionState: PermissionState { get async { .granted } }

    public init(fileURL: URL, sourceType: AudioSourceType = .systemAudio, chunkDuration: TimeInterval = 0.1) {
        self.fileURL = fileURL
        self.sourceType = sourceType
        self.chunkDuration = chunkDuration
    }

    public func requestPermission() async -> PermissionState { .granted }

    public func start() throws -> AsyncStream<AudioBuffer> {
        let audioFile = try AVAudioFile(forReading: fileURL)
        let format = audioFile.processingFormat
        let framesPerChunk = AVAudioFrameCount(max(1, format.sampleRate * chunkDuration))
        let sampleRate = format.sampleRate

        return AsyncStream { continuation in
            Task {
                while true {
                    guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesPerChunk) else { break }
                    do {
                        try audioFile.read(into: pcmBuffer, frameCount: framesPerChunk)
                    } catch {
                        break
                    }
                    if pcmBuffer.frameLength == 0 { break }
                    if let buffer = pcmBuffer.toAudioBuffer(sampleRate: sampleRate) {
                        continuation.yield(buffer)
                    }
                }
                continuation.finish()
            }
        }
    }

    public func stop() {}
}

extension AVAudioPCMBuffer {
    /// Converts to the engine-agnostic `AudioBuffer` (Int16 PCM). Shared by `FileAudioSource`
    /// and `MicrophoneSource`.
    func toAudioBuffer(sampleRate: Double) -> AudioBuffer? {
        let frameCount = Int(frameLength)
        guard frameCount > 0 else { return nil }

        var samples = [Int16](repeating: 0, count: frameCount)
        if let int16Data = int16ChannelData {
            samples.withUnsafeMutableBufferPointer { destination in
                destination.baseAddress?.update(from: int16Data[0], count: frameCount)
            }
        } else if let floatData = floatChannelData {
            for index in 0..<frameCount {
                let clamped = max(-1.0, min(1.0, floatData[0][index]))
                samples[index] = Int16(clamped * Float(Int16.max))
            }
        } else {
            return nil
        }

        return AudioBuffer(samples: samples, sampleRate: sampleRate, capturedAt: Date())
    }
}
