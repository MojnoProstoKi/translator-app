import AppKit
import SwiftUI

/// A small, floating, non-activating panel that shows the live translation on top of every
/// other application — including full-screen video calls — without stealing keyboard focus
/// from them (FR-009).
@MainActor
public final class OverlayWindowController: NSWindowController, NSWindowDelegate {
    private let onCloseRequested: () -> Void

    /// - Parameter onCloseRequested: called when the user clicks the panel's close button.
    ///   The panel itself is never actually torn down (it's reused across sessions) — this just
    ///   maps the close button onto "stop the translation session", matching the menu's "Остановить
    ///   перевод" action, rather than leaving it disabled as dead UI (as it was before `.closable`
    ///   was added to the style mask).
    public init(viewModel: OverlayViewModel, onCloseRequested: @escaping () -> Void) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // `.screenSaver` places the panel above full-screen apps and Spaces switches, so a
        // full-screen Zoom/Teams call or video doesn't hide it (FR-009).
        panel.level = .screenSaver
        // No `.stationary`: that behavior pins the panel to the space/screen it was created on,
        // which is what made dragging it to a second display minimize/vanish it instead of
        // actually moving there.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 360, height: 160)

        panel.contentView = NSHostingView(rootView: OverlayView(viewModel: viewModel))

        self.onCloseRequested = onCloseRequested
        super.init(window: panel)

        panel.delegate = self
        positionInBottomTrailingCorner()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Intercepts the close button: stops the session and hides the panel itself (rather than
    /// letting AppKit tear it down — it's reused across sessions).
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        onCloseRequested()
        hide()
        return false
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
