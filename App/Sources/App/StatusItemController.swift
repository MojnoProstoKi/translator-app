import AppKit

/// Builds and drives the menu-bar icon (`NSStatusItem`) and its dropdown menu, replacing the
/// SwiftUI `MenuBarExtra` this app used to use. `autosaveName` is only available on `NSStatusItem`
/// (SwiftUI's `MenuBarExtra` doesn't expose it), and is what lets the icon's position in the menu
/// bar survive relaunches instead of drifting back to whatever slot happens to be free.
///
/// The menu is rebuilt from scratch in `menuNeedsUpdate` right before it opens — mirroring how
/// SwiftUI recomputed the old menu's body from `AppCoordinator`'s state — rather than kept in sync
/// incrementally, since it only ever needs to reflect state at the moment the user opens it.
@MainActor
final class StatusItemController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var coordinator: AppCoordinator!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator()
        self.coordinator = coordinator

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "com.translator.RealtimeTranslator.statusItem"
        item.button?.image = NSImage(
            systemSymbolName: "waveform.circle",
            accessibilityDescription: "RealtimeTranslator"
        )
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let controller = coordinator.sessionController

        if controller.isRunning {
            addItem(to: menu, title: "Остановить перевод", action: #selector(stop))
        } else {
            let directionItem = NSMenuItem(
                title: "Направление: \(controller.direction.menuTitle)",
                action: nil,
                keyEquivalent: ""
            )
            let directionMenu = NSMenu()
            for direction in TranslationDirection.allCases {
                let directionItem = NSMenuItem(
                    title: direction.menuTitle,
                    action: #selector(selectDirection(_:)),
                    keyEquivalent: ""
                )
                directionItem.target = self
                directionItem.representedObject = direction
                directionItem.state = direction == controller.direction ? .on : .off
                directionMenu.addItem(directionItem)
            }
            directionItem.submenu = directionMenu
            menu.addItem(directionItem)

            menu.addItem(.separator())
            addItem(to: menu, title: "Слушать системный звук (звонок/видео)", action: #selector(startSystemAudio))
            addItem(to: menu, title: "Слушать микрофон", action: #selector(startMicrophone))
            addItem(to: menu, title: "Слушать оба источника", action: #selector(startCombined))
        }

        if let sourceLostMessage = controller.sourceLostMessage {
            menu.addItem(.separator())
            addItem(to: menu, title: sourceLostMessage, action: nil)
        }
        if let lastError = coordinator.lastError {
            menu.addItem(.separator())
            addItem(to: menu, title: lastError, action: nil)
        }

        menu.addItem(.separator())
        addItem(to: menu, title: "История сессий…", action: #selector(showHistory))

        menu.addItem(.separator())
        addItem(to: menu, title: "Выход", action: #selector(quit))
    }

    private func addItem(to menu: NSMenu, title: String, action: Selector?, keyEquivalent: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        menu.addItem(item)
    }

    @objc private func stop() {
        coordinator.stop()
    }

    @objc private func startSystemAudio() {
        coordinator.startSystemAudio()
    }

    @objc private func startMicrophone() {
        coordinator.startMicrophone()
    }

    @objc private func startCombined() {
        coordinator.startCombined()
    }

    @objc private func showHistory() {
        coordinator.showHistory()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func selectDirection(_ sender: NSMenuItem) {
        guard let direction = sender.representedObject as? TranslationDirection else { return }
        coordinator.sessionController.setDirection(direction)
    }
}
