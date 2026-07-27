import SwiftUI

/// RealtimeTranslator — real-time translation of the interlocutor's English speech into Russian
/// (spec.md). A menu-bar-only utility app: no Dock icon, no main window; the live translation is
/// shown in a floating overlay (OverlayWindowController) started/stopped from this menu.
@main
struct RealtimeTranslatorApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("RealtimeTranslator", systemImage: "waveform.circle") {
            if coordinator.sessionController.isRunning {
                Button("Остановить перевод") {
                    coordinator.stop()
                }
            } else {
                Button("Слушать системный звук (звонок/видео)") {
                    coordinator.startSystemAudio()
                }
                Button("Слушать микрофон") {
                    coordinator.startMicrophone()
                }
                Button("Слушать оба источника") {
                    coordinator.startCombined()
                }
            }

            if let sourceLostMessage = coordinator.sessionController.sourceLostMessage {
                Divider()
                Text(sourceLostMessage)
            }
            if let lastError = coordinator.lastError {
                Divider()
                Text(lastError)
            }

            Divider()
            Button("История сессий…") {
                coordinator.showHistory()
            }

            Divider()
            Button("Выход") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
