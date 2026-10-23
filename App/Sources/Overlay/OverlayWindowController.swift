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
    private var screenSharingObservation: AnyCancellable?
    private let hostingView: NSHostingView<OverlayView>
    /// Expanded-mode size to restore when leaving compact mode — kept so a panel the user
    /// resized doesn't snap back to the default size every time it's expanded.
    private var expandedSize: NSSize?
    private var isCompact = false

    private static let expandedMinSize = NSSize(width: 360, height: 160)
    private static let compactHeight = OverlayView.compactHeight
    private static let compactMinWidth: CGFloat = 260

    /// - Parameter onCloseRequested: called when the user clicks the panel's close button.
    ///   The panel itself is never actually torn down (it's reused across sessions) — this just
    ///   maps the close button onto "stop the translation session", matching the menu's "Остановить
    ///   перевод" action, rather than leaving it disabled as dead UI (as it was before `.closable`
    ///   was added to the style mask).
    public init(viewModel: OverlayViewModel, onCloseRequested: @escaping () -> Void) {
        let panel = Self.makePanel()

        let hostingView = NSHostingView(rootView: OverlayView(viewModel: viewModel))
        // Size limits are enforced in `windowWillResize` instead — left to SwiftUI, the
        // still-expanded content's minimum height kept the panel from shrinking to compact. (With
        // this off, the hosting view also resets the window's `minSize`/`maxSize` on every update,
        // so those can't be used either.)
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        self.hostingView = hostingView
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

        // No `dropFirst`: the remembered setting has to apply from the first time the panel shows.
        screenSharingObservation = viewModel.$isHiddenFromScreenSharing
            .sink { [weak self] isHidden in
                // Deferred: un-hiding replaces the panel, and this fires from a click on a button
                // inside that very panel — swap it once that event has finished.
                DispatchQueue.main.async { self?.applyScreenSharing(hidden: isHidden) }
            }
    }

    private static func makePanel() -> NSPanel {
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
        return panel
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

    /// Limits the user's live resizing: compact mode is width-only, expanded mode has a minimum
    /// size. Not called for programmatic `setFrame`, so `applyCompactMode` isn't affected.
    public func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        if isCompact {
            return NSSize(width: max(frameSize.width, Self.compactMinWidth), height: Self.compactHeight)
        }
        return NSSize(
            width: max(frameSize.width, Self.expandedMinSize.width),
            height: max(frameSize.height, Self.expandedMinSize.height)
        )
    }

    /// Resizes the panel between the full transcript and the one-line strip, keeping its bottom
    /// edge in place (the panel starts in the bottom-trailing corner, so that's the edge the
    /// user anchors on).
    private func applyCompactMode(_ isCompact: Bool) {
        guard let window else { return }
        self.isCompact = isCompact
        var frame = window.frame
        if isCompact {
            expandedSize = frame.size
            frame.size.height = Self.compactHeight
        } else {
            frame.size = expandedSize ?? Self.expandedMinSize
        }
        window.setFrame(window.constrainFrameRect(frame, to: window.screen), display: true, animate: true)
    }

    /// Asks macOS to leave the panel out of screen sharing/recording, or to include it again.
    /// AppKit won't take a window back out of `.none` (setting `.readOnly`/`.readWrite` afterwards
    /// is silently ignored — confirmed on macOS 26), so un-hiding swaps in a fresh panel carrying
    /// the same content and frame.
    private func applyScreenSharing(hidden: Bool) {
        guard let window else { return }
        if hidden {
            window.sharingType = .none
            return
        }
        guard window.sharingType == .none else { return }

        let replacement = Self.makePanel()
        replacement.setFrame(window.frame, display: false)
        let wasVisible = window.isVisible
        window.delegate = nil
        window.orderOut(nil)
        window.contentView = nil
        replacement.contentView = hostingView
        replacement.delegate = self
        self.window = replacement
        if wasVisible {
            replacement.orderFrontRegardless()
        }
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
