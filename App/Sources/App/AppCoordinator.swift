import AppKit
import Combine
import Foundation
import Translation
import TranslationEngine

private let bundleIdentifier = "com.translator.RealtimeTranslator"

/// Ties the session controller, overlay window, permissions, consent reminder, and session
/// recording/history together so the menu bar UI (RealtimeTranslatorApp.swift) has a single
/// object to drive.
@MainActor
public final class AppCoordinator: ObservableObject {
    public let sessionController: TranslationSessionController
    public let permissionsManager = PermissionsManager()
    public let sessionHistory: SessionHistoryViewModel

    private let overlayController: OverlayWindowController
    private let consentReminder: ConsentReminderPresenter
    private let sessionRecorder: SessionRecorder
    private var historyWindowController: SessionHistoryWindowController?
    private var translationPreparationWindow: TranslationPreparationWindowController?
    private var permissionGuidanceWindow: PermissionGuidanceWindowController?
    private var sessionNamingWindow: SessionNamingWindowController?
    private let callAppMonitor = CallAppMonitor()
    private let callReminderNotifier = CallReminderNotifier()
    private var cancellables: Set<AnyCancellable> = []

    @Published public private(set) var lastError: String?

    public init() {
        let controller = TranslationSessionController()
        self.sessionController = controller
        self.consentReminder = ConsentReminderPresenter(overlayViewModel: controller.overlayViewModel)

        let sessionsDirectory = SessionsDirectoryPreference.stored()
            ?? FileSessionTranscriptStore.defaultBaseDirectory(bundleIdentifier: bundleIdentifier)
        let store = FileSessionTranscriptStore(baseDirectory: sessionsDirectory)
        self.sessionRecorder = SessionRecorder(store: store)
        self.sessionHistory = SessionHistoryViewModel(store: store, sessionsDirectory: sessionsDirectory)

        // Captures the local `controller` (not `self`) — `self.overlayController` is exactly
        // the property this expression is initializing, so it can't be part of a `self`-capturing
        // closure yet. `controller.stop()` alone reproduces everything `AppCoordinator.stop()`
        // does for the session (`onSessionEnded` already drives the recorder/history); the panel
        // hides itself directly in `OverlayWindowController.windowShouldClose`.
        self.overlayController = OverlayWindowController(
            viewModel: controller.overlayViewModel,
            onCloseRequested: { controller.stop() }
        )
        self.sessionHistory.changeDirectoryAction = { [weak self] in self?.changeSessionsDirectory() }

        controller.onEvent = { [sessionRecorder] event in
            sessionRecorder.apply(event)
        }
        controller.onSessionEnded = { [weak self] in
            self?.finishSession()
        }

        consentReminder.remindAtFirstLaunchIfNeeded()

        // Notices when a call/meeting app (Zoom, Teams, FaceTime, …) launches and offers to turn
        // on translation, so the user doesn't have to remember to open the menu themselves.
        // Skipped while a session is already running — nothing useful to suggest at that point.
        callAppMonitor.onCallAppDetected = { [weak self] appName in
            guard let self, !self.sessionController.isRunning else { return }
            self.callReminderNotifier.notifyCallAppDetected(appName: appName)
        }
        callReminderNotifier.onStartTranslationRequested = { [weak self] in
            Task { @MainActor in self?.startSystemAudio() }
        }
        callAppMonitor.start()

        // `sessionController` is a nested ObservableObject: SwiftUI only re-renders views that
        // directly observe an object whose *own* objectWillChange fires. Without this, MenuBarExtra
        // (which observes `AppCoordinator`, not `sessionController`) would never notice
        // `isRunning`/`sourceLostMessage` changing — e.g. the menu staying on "Остановить перевод"
        // after a stop. Forwarding republishes the change up to `AppCoordinator.objectWillChange`.
        controller.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // FR-010: request both permissions explicitly, right at launch, rather than only ever
        // implicitly through first use. Confirmed by manual testing that this was missing
        // entirely for the microphone (its `requestPermission()` existed but nothing ever
        // called it) — the user never saw a single system permission dialog across many runs.
        Task { await requestInitialPermissionsIfNeeded() }
    }

    private func requestInitialPermissionsIfNeeded() async {
        NSApp.activate(ignoringOtherApps: true)
        for sourceType in [AudioSourceType.systemAudio, .microphone] {
            if permissionsManager.currentState(for: sourceType) == .notRequested {
                _ = await permissionsManager.requestPermission(for: sourceType)
            }
        }
        await callReminderNotifier.requestAuthorizationIfNeeded()
    }

    public func startSystemAudio() {
        start(sources: [.systemAudio]) { [self] in try sessionController.startSystemAudioSession() }
    }

    public func startMicrophone() {
        start(sources: [.microphone]) { [self] in try sessionController.startMicrophoneSession() }
    }

    public func startCombined() {
        start(sources: [.systemAudio, .microphone]) { [self] in try sessionController.startCombinedSession() }
    }

    private func start(sources: Set<AudioSourceType>, _ action: @escaping () throws -> Void) {
        // This is an LSUIElement (menu-bar-only, no Dock icon) app; explicitly activating
        // ensures any pending system permission sheet has an active app to appear in front of.
        NSApp.activate(ignoringOtherApps: true)

        Task {
            await prepareTranslationAssetsIfNeeded()

            // FR-010: verify (and, if needed, actively (re-)request) every source's permission
            // before starting — never silently attempt capture that's going to be denied.
            for sourceType in sources {
                var state = permissionsManager.currentState(for: sourceType)
                if state == .notRequested {
                    state = await permissionsManager.requestPermission(for: sourceType)
                }
                guard state == .granted else {
                    let guidance = permissionsManager.deniedGuidance(for: sourceType)
                    lastError = guidance
                    presentPermissionGuidance(sourceType: sourceType, guidance: guidance)
                    return
                }
            }

            consentReminder.remindBeforeSessionStart()
            sessionRecorder.beginSession(sources: sources)
            do {
                try action()
                overlayController.show()
                lastError = nil
            } catch {
                lastError = "\(error)"
            }
        }
    }

    /// Ensures the on-device en→ru translation model is installed before a session starts,
    /// showing `TranslationPreparationWindowController`'s window (the only way to trigger Apple's
    /// system download-consent UI) if it isn't. Without this, the first-ever translation attempt
    /// used to fail outright with `LanguagePackNotInstalledError`, forcing a manual trip through
    /// the system Translate app — confirmed by manual testing. A no-op once the pack is installed.
    private func prepareTranslationAssetsIfNeeded() async {
        let source = Locale.Language(languageCode: .english)
        let target = Locale.Language(languageCode: .russian)
        let status = await LanguageAvailability().status(from: source, to: target)
        guard status == .supported else { return }

        NSApp.activate(ignoringOtherApps: true)
        await withCheckedContinuation { continuation in
            let controller = TranslationPreparationWindowController(source: source, target: target) {
                continuation.resume()
            }
            translationPreparationWindow = controller
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
        }
        translationPreparationWindow?.close()
        translationPreparationWindow = nil
    }

    /// Prompts for a name before persisting the session that just ended (FR-012), pre-filled
    /// with a sensible default so naming stays optional in practice — confirming immediately
    /// keeps that default. Skipped entirely (same as before this feature existed) when there's
    /// nothing to save, matching `endSession(title:)`'s own finalized-only precondition.
    private func finishSession() {
        guard sessionRecorder.hasFinalizedSegments, let startedAt = sessionRecorder.activeSessionStartedAt else {
            _ = try? sessionRecorder.endSession(title: "")
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let controller = SessionNamingWindowController(
            defaultTitle: SessionTranscript.defaultTitle(startedAt: startedAt)
        ) { [weak self] title in
            guard let self else { return }
            _ = try? self.sessionRecorder.endSession(title: title)
            self.sessionHistory.refresh()
            self.sessionNamingWindow = nil
        }
        sessionNamingWindow = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    /// FR-010: a denied permission never re-prompts on its own, so point the user straight at
    /// the exact System Settings pane instead of leaving them to find it from the text hint alone.
    private func presentPermissionGuidance(sourceType: AudioSourceType, guidance: String) {
        NSApp.activate(ignoringOtherApps: true)
        let controller = PermissionGuidanceWindowController(sourceType: sourceType, guidance: guidance)
        permissionGuidanceWindow = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    public func stop() {
        sessionController.stop()
        overlayController.hide()
    }

    public func showHistory() {
        let controller = historyWindowController ?? SessionHistoryWindowController(viewModel: sessionHistory)
        historyWindowController = controller
        controller.show()
    }

    /// Lets the user redirect where future session transcripts are saved (FR-012). Past
    /// transcripts under the previous folder are left in place — they simply stop showing up in
    /// history, since history always reflects the currently selected folder's contents.
    private func changeSessionsDirectory() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Выбрать"
        panel.message = "Выберите папку для сохранения переводов сессий"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        SessionsDirectoryPreference.save(url)
        let store = FileSessionTranscriptStore(baseDirectory: url)
        sessionRecorder.updateStore(store)
        sessionHistory.updateStore(store, sessionsDirectory: url)
    }
}
