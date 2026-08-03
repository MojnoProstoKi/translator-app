import UserNotifications

/// Turns a `CallAppMonitor` detection into an actionable system notification, so noticing a call
/// has started doesn't require the user to have RealtimeTranslator's menu open. Only ever
/// suggests turning translation on — starting it always stays the user's own action
/// (`onStartTranslationRequested`), triggered by tapping the notification or its action button.
public final class CallReminderNotifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private static let categoryIdentifier = "CALL_DETECTED"
    private static let startActionIdentifier = "START_TRANSLATION"

    // Left as a plain (non-`@MainActor`) closure: `didReceive` below calls it as-is, on whatever
    // thread the system delivers the response on — the `Task { @MainActor in ... }` hop is the
    // caller's responsibility, same convention as `TranslationSessionController.onLevel`.
    public var onStartTranslationRequested: (() -> Void)?

    private let center = UNUserNotificationCenter.current()

    public override init() {
        super.init()
        center.delegate = self
        let startAction = UNNotificationAction(
            identifier: Self.startActionIdentifier,
            title: "Включить перевод",
            options: []
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryIdentifier,
                actions: [startAction],
                intentIdentifiers: [],
                options: []
            ),
        ])
    }

    public func requestAuthorizationIfNeeded() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    public func notifyCallAppDetected(appName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Похоже, начался звонок"
        content.body = "Открылось приложение «\(appName)» — включить перевод?"
        content.categoryIdentifier = Self.categoryIdentifier
        content.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // Without this, notifications are suppressed by default while RealtimeTranslator (an
    // LSUIElement app, but still "foreground" while its menu is open) is the active app.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let shouldStart = response.actionIdentifier == Self.startActionIdentifier
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier
        if shouldStart {
            onStartTranslationRequested?()
        }
        completionHandler()
    }
}
