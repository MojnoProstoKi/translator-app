import AppKit

/// Watches for known calling/meeting apps (`KnownCallApps`) becoming frontmost, so
/// `AppCoordinator` can prompt the user to turn on translation right when a call is likely
/// starting. Watches activation rather than just launch: a call app is very often already
/// running in the background (Zoom/Teams/Slack left open between meetings), so a launch-only
/// check misses every call started in an app that was already open — confirmed by user report.
@MainActor
public final class CallAppMonitor {
    public var onCallAppDetected: ((String) -> Void)?

    private var activateObserver: NSObjectProtocol?
    private var deactivateObserver: NSObjectProtocol?

    // Suppresses re-notifying while the same call app stays frontmost (e.g. its own windows
    // stealing/reclaiming activation); cleared on deactivation so switching away and back later
    // (a plausible new call) notifies again.
    private var notifiedBundleIdentifier: String?

    public init() {}

    public func start() {
        guard activateObserver == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        activateObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                let bundleIdentifier = app.bundleIdentifier,
                let displayName = KnownCallApps.displayName(forBundleIdentifier: bundleIdentifier)
            else { return }
            Task { @MainActor in
                guard let self, bundleIdentifier != self.notifiedBundleIdentifier else { return }
                self.notifiedBundleIdentifier = bundleIdentifier
                self.onCallAppDetected?(displayName)
            }
        }
        deactivateObserver = center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let bundleIdentifier = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            else { return }
            Task { @MainActor in
                guard let self, bundleIdentifier == self.notifiedBundleIdentifier else { return }
                self.notifiedBundleIdentifier = nil
            }
        }
    }

    public func stop() {
        let center = NSWorkspace.shared.notificationCenter
        if let activateObserver { center.removeObserver(activateObserver) }
        if let deactivateObserver { center.removeObserver(deactivateObserver) }
        activateObserver = nil
        deactivateObserver = nil
        notifiedBundleIdentifier = nil
    }
}
