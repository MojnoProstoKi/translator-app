import Foundation
import TranslationEngine

/// Requests and tracks the macOS permissions required for each audio source, with a clear
/// explanation of why each is needed and what to do if denied (FR-010).
@MainActor
public final class PermissionsManager: ObservableObject {
    @Published public private(set) var microphonePermission: PermissionState = .notRequested
    @Published public private(set) var systemAudioPermission: PermissionState = .notRequested

    // Typed as the protocol (not the concrete Apple-framework-backed types) specifically so
    // tests can inject fakes instead of touching real microphone/system-audio TCC permissions.
    private let microphoneSource: any AudioCaptureSource
    private let systemAudioSource: any AudioCaptureSource

    public init(
        microphoneSource: any AudioCaptureSource = MicrophoneSource(),
        systemAudioSource: any AudioCaptureSource = SystemAudioSource()
    ) {
        self.microphoneSource = microphoneSource
        self.systemAudioSource = systemAudioSource
    }

    /// A short, user-facing explanation of why a given source's permission is needed —
    /// shown alongside the system prompt (FR-010).
    public func explanation(for sourceType: AudioSourceType) -> String {
        switch sourceType {
        case .microphone:
            return "Микрофон нужен, чтобы переводить речь собеседника, когда вы разговариваете лично, рядом с этим Mac."
        case .systemAudio:
            return "Доступ к системному звуку нужен, чтобы переводить речь собеседника во время звонков (Zoom/Teams/Discord) и видео."
        }
    }

    /// What to tell the user once a permission has been denied, so they know how to fix it
    /// (FR-010: informing the user with actionable next steps).
    public func deniedGuidance(for sourceType: AudioSourceType) -> String {
        switch sourceType {
        case .microphone:
            return "Разрешите доступ к микрофону в Системных настройках → Конфиденциальность и безопасность → Микрофон, затем перезапустите перевод."
        case .systemAudio:
            return "Разрешите доступ в Системных настройках → Конфиденциальность и безопасность → Запись системного звука, затем перезапустите перевод."
        }
    }

    public func requestPermission(for sourceType: AudioSourceType) async -> PermissionState {
        switch sourceType {
        case .microphone:
            let state = await microphoneSource.requestPermission()
            microphonePermission = state
            return state
        case .systemAudio:
            let state = await systemAudioSource.requestPermission()
            systemAudioPermission = state
            return state
        }
    }

    public func currentState(for sourceType: AudioSourceType) -> PermissionState {
        switch sourceType {
        case .microphone: return microphonePermission
        case .systemAudio: return systemAudioPermission
        }
    }
}
