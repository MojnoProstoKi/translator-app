import AppKit
import Combine
import SwiftUI

/// A small, floating, non-activating panel that shows the live translation on top of every
/// other application — including full-screen video calls — without stealing keyboard focus
/// from them (FR-009).
@MainActor
public final class OverlayWindowController: NSWindowController, NSWindowDelegate {
    private let onCloseRequested: () -> Void
    private var compactObservation: AnyCancellable?
    /// Expanded-mode size to restore when leaving compact mode — kept so a panel the user
    /// resized doesn't snap back to the default size every time it's expanded.
    private var expandedSize: NSSize?

    private static let expandedMinSize = NSSize(width: 360, height: 160)
    private static let compactHeight = OverlayView.titlebarRowHeight
    private static let compactMinWidth: CGFloat = 260

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
        panel.minSize = Self.expandedMinSize

        let hostingView = NSHostingView(rootView: OverlayView(viewModel: viewModel))
        // The panel's min/max size is managed here (see `applyCompactMode`) — left to SwiftUI, the
        // still-expanded content's minimum height kept the panel from shrinking to compact.
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        self.onCloseRequested = onCloseRequested
        super.init(window: panel)

        panel.delegate = self
        positionInBottomTrailingCorner()

        // `dropFirst`: the initial value needs no resize; `removeDuplicates` so re-publishing
        // the same value doesn't overwrite `expandedSize` with the compact size.
        compactObservation = viewModel.$isCompact
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] isCompact in self?.applyCompactMode(isCompact) }
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

    /// Resizes the panel between the full transcript and the one-line strip, keeping its bottom
    /// edge in place (the panel starts in the bottom-trailing corner, so that's the edge the
    /// user anchors on). Compact mode only allows horizontal resizing.
    private func applyCompactMode(_ isCompact: Bool) {
        guard let window else { return }
        var frame = window.frame
        if isCompact {
            expandedSize = frame.size
            window.minSize = NSSize(width: Self.compactMinWidth, height: Self.compactHeight)
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: Self.compactHeight)
            frame.size.height = Self.compactHeight
        } else {
            window.minSize = Self.expandedMinSize
            window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            frame.size = expandedSize ?? Self.expandedMinSize
        }
        window.setFrame(window.constrainFrameRect(frame, to: window.screen), display: true, animate: true)
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
