import TranslationEngine
import XCTest

@testable import RealtimeTranslator

/// Tests `PermissionsManager`'s state transitions using fake `AudioCaptureSource`s — never
/// touches the real microphone/system-audio TCC permissions (FR-010, FR-014).
@MainActor
final class PermissionFlowTests: XCTestCase {
    func testGrantedPermissionIsReflectedInCurrentState() async {
        let mic = FakePermissionSource(sourceType: .microphone, result: .granted)
        let system = FakePermissionSource(sourceType: .systemAudio, result: .denied)
        let manager = PermissionsManager(microphoneSource: mic, systemAudioSource: system)

        XCTAssertEqual(manager.currentState(for: .microphone), .notRequested)
        XCTAssertEqual(manager.currentState(for: .systemAudio), .notRequested)

        let micState = await manager.requestPermission(for: .microphone)
        let systemState = await manager.requestPermission(for: .systemAudio)

        XCTAssertEqual(micState, .granted)
        XCTAssertEqual(systemState, .denied)
        XCTAssertEqual(manager.currentState(for: .microphone), .granted)
        XCTAssertEqual(manager.currentState(for: .systemAudio), .denied)
    }

    /// FR-010: every source has a non-empty explanation and denied-guidance string.
    func testExplanationsAndGuidanceAreProvidedForEverySource() {
        let manager = PermissionsManager(
            microphoneSource: FakePermissionSource(sourceType: .microphone, result: .notRequested),
            systemAudioSource: FakePermissionSource(sourceType: .systemAudio, result: .notRequested)
        )
        for sourceType in [AudioSourceType.microphone, .systemAudio] {
            XCTAssertFalse(manager.explanation(for: sourceType).isEmpty)
            XCTAssertFalse(manager.deniedGuidance(for: sourceType).isEmpty)
        }
    }
}

private final class FakePermissionSource: AudioCaptureSource, @unchecked Sendable {
    let sourceType: AudioSourceType
    private let result: PermissionState
    private(set) var permission: PermissionState = .notRequested

    var permissionState: PermissionState { get async { permission } }

    init(sourceType: AudioSourceType, result: PermissionState) {
        self.sourceType = sourceType
        self.result = result
    }

    func requestPermission() async -> PermissionState {
        permission = result
        return result
    }

    func start() throws -> AsyncStream<AudioBuffer> {
        AsyncStream { $0.finish() }
    }

    func stop() {}
}
