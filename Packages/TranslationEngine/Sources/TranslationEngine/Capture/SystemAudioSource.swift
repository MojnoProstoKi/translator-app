import AudioToolbox
import CoreAudio
import Foundation

/// `AudioCaptureSource` that captures all system audio output (e.g. a Zoom/Teams/Discord call
/// or a video) via Core Audio Taps — `AudioHardwareCreateProcessTap` (research.md §3).
///
/// Chosen over `ScreenCaptureKit` specifically because it only requires the narrower "System
/// Audio Recording" TCC permission (no screen-recording permission needed), matching FR-010's
/// requirement for a clear, minimal permission ask.
///
/// A process tap's `AudioObjectID` is **not** itself IO-capable
/// (`AudioDeviceCreateIOProcIDWithBlock` on it fails with `kAudioHardwareBadDeviceError`,
/// `'!dev'` — confirmed by manual testing). It must be wrapped in a private aggregate device
/// (`AudioHardwareCreateAggregateDevice` with the tap listed under `kAudioAggregateDeviceTapListKey`),
/// and IO is registered on the *aggregate's* AudioObjectID instead.
public final class SystemAudioSource: AudioCaptureSource, @unchecked Sendable {
    public let sourceType: AudioSourceType = .systemAudio

    private let lock = NSLock()
    private var tapObjectID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var ioProcID: AudioDeviceIOProcID?
    private var permission: PermissionState = .notRequested

    public var permissionState: PermissionState {
        get async { lock.withLock { permission } }
    }

    /// Reports the current captured audio's peak level (0...1) at UI-refresh rate — never the
    /// audio itself. Lets the app show a live level meter so the user can see *when* to speak,
    /// rather than guessing (requested explicitly after "not clear when to start talking").
    public var onLevel: (@Sendable (Float) -> Void)?

    public init() {}

    /// Core Audio Taps has no explicit "request permission" call distinct from first use: the
    /// system presents the "System Audio Recording" prompt the first time
    /// `AudioHardwareCreateProcessTap` is invoked by this process. We surface that as an
    /// explicit, awaitable step so callers (PermissionsManager, T032) can drive FR-010's
    /// explanatory-prompt requirement before actually starting capture.
    public func requestPermission() async -> PermissionState {
        do {
            let (probeTapID, _) = try Self.createTap()
            AudioHardwareDestroyProcessTap(probeTapID)
            lock.withLock { permission = .granted }
            return .granted
        } catch {
            lock.withLock { permission = .denied }
            return .denied
        }
    }

    public func start() throws -> AsyncStream<AudioBuffer> {
        let (tapID, tapUID) = try Self.createTap()
        let aggregateID: AudioObjectID
        do {
            aggregateID = try Self.createAggregateDevice(wrapping: tapUID)
        } catch {
            AudioHardwareDestroyProcessTap(tapID)
            throw error
        }
        lock.withLock {
            self.tapObjectID = tapID
            self.aggregateDeviceID = aggregateID
            self.permission = .granted
        }

        // The tap's actual sample rate depends on the current output device and is NOT
        // guaranteed to be 48kHz — reading it via kAudioTapPropertyFormat (rather than assuming
        // a fixed value) avoids silently mis-labeling buffers, which would cause the ASR
        // resampling step downstream to distort audio and never recognize any speech.
        let sampleRate = Self.queryTapFormat(tapID)?.mSampleRate ?? 48_000
        EngineLog.error("SystemAudioSource: tap sample rate = \(sampleRate) Hz")

        // Periodically logs the peak sample level of captured audio (never the audio itself) —
        // the only way to tell "the tap is capturing silence" apart from "the tap has real
        // audio but recognition/translation downstream is misbehaving" without relying on
        // Console entries that have proven unreliable to retrieve for this subsystem. Also
        // drives the live level meter via `onLevel`.
        let levelMonitor = AudioLevelMonitor(onLevel: onLevel)

        return AsyncStream { continuation in
            var procID: AudioDeviceIOProcID?
            let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, inInputData, _, _, _ in
                levelMonitor.observe(inInputData)
                guard let buffer = AudioBuffer.fromInterleavedFloat32(inInputData, sampleRate: sampleRate) else { return }
                continuation.yield(buffer)
            }
            guard status == noErr, let procID else {
                EngineLog.error("SystemAudioSource: AudioDeviceCreateIOProcIDWithBlock failed (\(status))")
                continuation.finish()
                return
            }
            self.lock.withLock { self.ioProcID = procID }
            let startStatus = AudioDeviceStart(aggregateID, procID)
            if startStatus != noErr {
                EngineLog.error("SystemAudioSource: AudioDeviceStart failed (\(startStatus))")
            }

            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
        }
    }

    public func stop() {
        lock.withLock {
            if let ioProcID {
                AudioDeviceStop(aggregateDeviceID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
                self.ioProcID = nil
            }
            if aggregateDeviceID != kAudioObjectUnknown {
                AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
                aggregateDeviceID = kAudioObjectUnknown
            }
            if tapObjectID != kAudioObjectUnknown {
                AudioHardwareDestroyProcessTap(tapObjectID)
                tapObjectID = kAudioObjectUnknown
            }
        }
    }

    private enum TapError: Error { case creationFailed(OSStatus) }

    /// Creates a private, global (all-processes) mono tap of system audio output, returning its
    /// AudioObjectID and the UID we assigned it (needed to reference it from the aggregate
    /// device description).
    ///
    /// Uses `CATapDescription`'s `monoGlobalTapButExcludeProcesses` convenience initializer —
    /// its exact Swift-bridged name (originally `NS_REFINED_FOR_SWIFT` in the Objective-C
    /// header, and not determinable from that header alone) was confirmed by inspecting the
    /// actual `usr/lib/swift/CoreAudio.swiftmodule` overlay interface shipped in the SDK. An
    /// earlier version of this method configured the same-looking state by hand instead
    /// (`isExclusive = true` on a bare `init()`) — that compiled and created a tap with no
    /// error, but manual testing showed it silently captured near-total silence instead of real
    /// system audio, so the dedicated initializer is not just cosmetic.
    private static func createTap() throws -> (AudioObjectID, String) {
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.name = "RealtimeTranslator System Audio Tap"
        let uid = UUID()
        description.uuid = uid
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tapID: AudioObjectID = kAudioObjectUnknown
        let status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { throw TapError.creationFailed(status) }
        return (tapID, uid.uuidString)
    }

    /// Wraps a tap (by UID) in a private aggregate device so it can be used with
    /// `AudioDeviceCreateIOProcIDWithBlock`/`AudioDeviceStart` — a bare tap AudioObjectID is not
    /// itself IO-capable.
    private static func createAggregateDevice(wrapping tapUID: String) throws -> AudioObjectID {
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "RealtimeTranslator System Audio Aggregate",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]
            ],
        ]

        var aggregateID: AudioObjectID = kAudioObjectUnknown
        let status = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID)
        guard status == noErr else { throw TapError.creationFailed(status) }
        return aggregateID
    }

    /// Reads the tap's actual current data format (`kAudioTapPropertyFormat`) — in particular
    /// its real sample rate, which depends on the system output device and must not be assumed.
    private static func queryTapFormat(_ tapID: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = withUnsafeMutablePointer(to: &asbd) { pointer in
            AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else {
            EngineLog.error("SystemAudioSource: kAudioTapPropertyFormat query failed (\(status))")
            return nil
        }
        return asbd
    }
}

/// Tracks the peak audio sample level (0.0–1.0, never the audio content): forwards it to
/// `onLevel` at UI-refresh rate (live level meter) and additionally logs it every two seconds
/// (diagnostic — distinguishes "the tap captures silence" from "the tap has real audio but
/// something downstream mishandles it").
final class AudioLevelMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var lastLoggedAt = Date.distantPast
    private var lastReportedAt = Date.distantPast
    private var runningPeak: Float = 0
    private let onLevel: (@Sendable (Float) -> Void)?

    init(onLevel: (@Sendable (Float) -> Void)?) {
        self.onLevel = onLevel
    }

    func observe(_ bufferListPointer: UnsafePointer<AudioBufferList>) {
        let bufferList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferListPointer))
        guard let first = bufferList.first, let data = first.mData else { return }
        let floatCount = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        guard floatCount > 0 else { return }
        let floatPointer = data.bindMemory(to: Float.self, capacity: floatCount)

        var peak: Float = 0
        for index in 0..<floatCount {
            peak = max(peak, abs(floatPointer[index]))
        }

        let (shouldReportLevel, shouldLog): (Bool, Bool) = lock.withLock {
            runningPeak = max(runningPeak, peak)
            let now = Date()
            let reportLevel = now.timeIntervalSince(lastReportedAt) >= 0.06  // ~15 Hz, plenty for a meter
            if reportLevel { lastReportedAt = now }
            let log = now.timeIntervalSince(lastLoggedAt) >= 2.0
            if log { lastLoggedAt = now }
            return (reportLevel, log)
        }

        if shouldReportLevel {
            onLevel?(peak)
        }
        if shouldLog {
            let reportedPeak = lock.withLock { () -> Float in
                let value = runningPeak
                runningPeak = 0
                return value
            }
            EngineLog.error("SystemAudioSource: captured audio peak level over last ~2s = \(reportedPeak) (0=silence, 1=max)")
        }
    }
}

extension AudioBuffer {
    /// Converts a Core Audio `AudioBufferList` (assumed 32-bit float, per the tap's canonical
    /// format) into the engine's Int16 `AudioBuffer` representation.
    fileprivate static func fromInterleavedFloat32(_ bufferListPointer: UnsafePointer<AudioBufferList>, sampleRate: Double) -> AudioBuffer? {
        let bufferList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferListPointer))
        guard let first = bufferList.first, let data = first.mData else { return nil }

        let floatCount = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        guard floatCount > 0 else { return nil }

        let floatPointer = data.bindMemory(to: Float.self, capacity: floatCount)
        var samples = [Int16](repeating: 0, count: floatCount)
        for index in 0..<floatCount {
            let clamped = max(-1.0, min(1.0, floatPointer[index]))
            samples[index] = Int16(clamped * Float(Int16.max))
        }

        return AudioBuffer(samples: samples, sampleRate: sampleRate, capturedAt: Date())
    }
}
