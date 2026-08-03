import AppKit

/// Watches for known calling/meeting apps (`KnownCallApps`) launching, so `AppCoordinator` can
/// prompt the user to turn on translation right when a call is likely starting.
@MainActor
public final class CallAppMonitor {
    public var onCallAppDetected: ((String) -> Void)?

    private var observer: NSObjectProtocol?

    public init() {}

    public func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                let bundleIdentifier = app.bundleIdentifier,
                let displayName = KnownCallApps.displayName(forBundleIdentifier: bundleIdentifier)
            else { return }
            Task { @MainActor in
                self?.onCallAppDetected?(displayName)
            }
        }
    }

    public func stop() {
        guard let observer else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(observer)
        self.observer = nil
    }
}
