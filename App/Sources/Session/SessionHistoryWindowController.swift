import AppKit
import SwiftUI

/// A regular (non-floating) window presenting `SessionHistoryView` (FR-016).
@MainActor
public final class SessionHistoryWindowController: NSWindowController {
    public convenience init(viewModel: SessionHistoryViewModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "История сессий"
        window.contentView = NSHostingView(rootView: SessionHistoryView(viewModel: viewModel))
        window.center()
        self.init(window: window)
    }

    public func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
