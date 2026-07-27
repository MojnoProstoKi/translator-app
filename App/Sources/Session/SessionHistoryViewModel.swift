import Foundation
import TranslationEngine

/// Drives `SessionHistoryView`: lists past sessions and lets the user delete any one of them
/// independently (FR-016, SC-006: deletion in at most 2 UI actions).
@MainActor
public final class SessionHistoryViewModel: ObservableObject {
    @Published public private(set) var summaries: [SessionTranscriptSummary] = []
    @Published public private(set) var lastError: String?
    @Published public private(set) var sessionsDirectory: URL

    private var store: SessionTranscriptStore

    /// Set by `AppCoordinator` to present the folder picker; kept as a closure rather than an
    /// AppKit dependency here since this view model otherwise only imports Foundation.
    public var changeDirectoryAction: (() -> Void)?

    public init(store: SessionTranscriptStore, sessionsDirectory: URL) {
        self.store = store
        self.sessionsDirectory = sessionsDirectory
    }

    public func changeDirectory() {
        changeDirectoryAction?()
    }

    /// Switches to a newly chosen sessions folder. Past sessions saved under the previous folder
    /// are left untouched — they simply no longer appear here, since this list always reflects
    /// whatever the current folder contains.
    public func updateStore(_ store: SessionTranscriptStore, sessionsDirectory: URL) {
        self.store = store
        self.sessionsDirectory = sessionsDirectory
        refresh()
    }

    public func refresh() {
        do {
            summaries = try store.listSessions().sorted { $0.startedAt > $1.startedAt }
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
    }

    /// Deletes one session's record — a single UI action (a button tap), well within SC-006's
    /// 2-action budget — without affecting any other stored session (FR-016).
    public func delete(sessionId: UUID) {
        do {
            try store.delete(sessionId: sessionId)
            summaries.removeAll { $0.sessionId == sessionId }
        } catch {
            lastError = "\(error)"
        }
    }
}
