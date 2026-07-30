import AppKit
import SwiftUI
import TranslationEngine

/// Shown when a required audio permission is denied. Unlike microphone/speech recognition,
/// macOS never re-prompts for a denied permission — the only way forward is System Settings —
/// so this gives the user a direct button there instead of just a text hint (FR-010).
@MainActor
public final class PermissionGuidanceWindowController: NSWindowController {
    public convenience init(sourceType: AudioSourceType, guidance: String) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 160),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Нужно разрешение"
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        window.contentView = NSHostingView(
            rootView: PermissionGuidanceView(
                guidance: guidance,
                settingsURL: sourceType.systemSettingsURL,
                onClose: { [weak window] in window?.close() }
            )
        )
    }
}

private extension AudioSourceType {
    /// Deep links straight into the relevant System Settings pane instead of leaving the user
    /// to find it themselves. Apple folded "System Audio Recording" into the same pane as Screen
    /// Recording (relabeled "Screen & System Audio Recording" from Sonoma on) — same anchor
    /// (`Privacy_ScreenCapture`) opens it for both.
    var systemSettingsURL: URL {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        case .systemAudio:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        }
    }
}

private struct PermissionGuidanceView: View {
    let guidance: String
    let settingsURL: URL
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(guidance)
                .multilineTextAlignment(.center)
                .font(.callout)
            HStack(spacing: 12) {
                Button("Закрыть", action: onClose)
                Button("Открыть Настройки") {
                    NSWorkspace.shared.open(settingsURL)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380, height: 160)
    }
}
