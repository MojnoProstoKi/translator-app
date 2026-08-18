import SwiftUI

/// RealtimeTranslator — real-time translation of the interlocutor's English speech into Russian
/// (spec.md). A menu-bar-only utility app: no Dock icon, no main window; the live translation is
/// shown in a floating overlay (OverlayWindowController) started/stopped from this menu.
///
/// The menu itself is a plain AppKit `NSStatusItem` (`StatusItemController`) rather than SwiftUI's
/// `MenuBarExtra`: only `NSStatusItem` exposes `autosaveName`, which persists wherever the user
/// drags the icon in the menu bar across relaunches — without it, a crowded menu bar (many other
/// apps' icons) can re-squeeze RealtimeTranslator back to the same easily-clipped spot every
/// launch. `Settings` is an empty placeholder scene: a SwiftUI `App` requires at least one, but an
/// LSUIElement app never surfaces it (no app menu to reach "Preferences…" from).
@main
struct RealtimeTranslatorApp: App {
    @NSApplicationDelegateAdaptor(StatusItemController.self) private var statusItemController

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
