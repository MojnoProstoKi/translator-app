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
                // Fixed for a session's lifetime (TranslationSessionController.setDirection is a
                // no-op while running), so the picker only makes sense to show before starting.
                Menu("Направление: \(coordinator.sessionController.direction.menuTitle)") {
                    ForEach(TranslationDirection.allCases, id: \.self) { direction in
                        Button {
                            coordinator.sessionController.setDirection(direction)
                        } label: {
                            if direction == coordinator.sessionController.direction {
                                Label(direction.menuTitle, systemImage: "checkmark")
                            } else {
                                Text(direction.menuTitle)
                            }
                        }
                    }
                }
                Divider()
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
