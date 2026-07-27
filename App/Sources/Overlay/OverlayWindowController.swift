import AppKit
import SwiftUI

/// A small, floating, non-activating panel that shows the live translation on top of every
/// other application — including full-screen video calls — without stealing keyboard focus
/// from them (FR-009).
@MainActor
public final class OverlayWindowController: NSWindowController {
    public convenience init(viewModel: OverlayViewModel) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 160),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // `.screenSaver` places the panel above full-screen apps and Spaces switches, so a
        // full-screen Zoom/Teams call or video doesn't hide it (FR-009).
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false

        panel.contentView = NSHostingView(rootView: OverlayView(viewModel: viewModel))

        self.init(window: panel)
        positionInBottomTrailingCorner()
    }

    private func positionInBottomTrailingCorner() {
        guard let window, let screen = NSScreen.main else { return }
        let margin: CGFloat = 24
        let frame = window.frame
        let origin = NSPoint(
            x: screen.visibleFrame.maxX - frame.width - margin,
            y: screen.visibleFrame.minY + margin
        )
        window.setFrameOrigin(origin)
    }

    public func show() {
        window?.orderFrontRegardless()
    }

    public func hide() {
        window?.orderOut(nil)
    }
}
