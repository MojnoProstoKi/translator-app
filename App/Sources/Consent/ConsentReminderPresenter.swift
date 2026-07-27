import Foundation

/// Shows a brief, non-blocking reminder to notify/get the interlocutor's consent before their
/// speech is processed — once at first launch and again before every session start (FR-015).
///
/// "Non-blocking" here means literally that: `remindBeforeSessionStart()` never awaits anything
/// before returning, so callers can start the session immediately afterward. The reminder text
/// is shown as a transient banner in the overlay (`OverlayViewModel.consentBannerText`) that
/// clears itself after a few seconds.
@MainActor
public final class ConsentReminderPresenter {
    private static let hasShownAtLaunchKey = "com.translator.consentReminder.hasShownAtLaunch"
    private static let bannerDuration: UInt64 = 4_000_000_000  // 4s, in nanoseconds

    private let overlayViewModel: OverlayViewModel
    private let userDefaults: UserDefaults

    public static let reminderText =
        "Не забудьте предупредить собеседника, что вы используете перевод его речи."

    public init(overlayViewModel: OverlayViewModel, userDefaults: UserDefaults = .standard) {
        self.overlayViewModel = overlayViewModel
        self.userDefaults = userDefaults
    }

    /// Call once when the app finishes launching.
    public func remindAtFirstLaunchIfNeeded() {
        guard !userDefaults.bool(forKey: Self.hasShownAtLaunchKey) else { return }
        userDefaults.set(true, forKey: Self.hasShownAtLaunchKey)
        showBanner()
    }

    /// Call immediately before starting every session (does not block the start).
    public func remindBeforeSessionStart() {
        showBanner()
    }

    private func showBanner() {
        overlayViewModel.consentBannerText = Self.reminderText
        Task { [weak overlayViewModel] in
            try? await Task.sleep(nanoseconds: Self.bannerDuration)
            if overlayViewModel?.consentBannerText == Self.reminderText {
                overlayViewModel?.consentBannerText = nil
            }
        }
    }
}
