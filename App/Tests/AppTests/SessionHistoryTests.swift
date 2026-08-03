import Foundation
import TranslationEngine
import XCTest

@testable import RealtimeTranslator

/// Tests `SessionHistoryViewModel` against a real `FileSessionTranscriptStore` pointed at a
/// throwaway temp directory (FR-016, SC-006).
@MainActor
final class SessionHistoryTests: XCTestCase {
    // XCTestCase's setUp/tearDown overrides are not themselves MainActor-isolated even though
    // this class is; these are only ever touched serially by XCTest, never concurrently.
    private nonisolated(unsafe) var tempDirectory: URL!
    private nonisolated(unsafe) var store: FileSessionTranscriptStore!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        store = FileSessionTranscriptStore(baseDirectory: tempDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func save(sourceType: AudioSourceType) throws -> UUID {
        let startedAt = Date()
        var segment = SpeechSegment(sessionId: UUID(), sourceType: sourceType, startedAt: startedAt)
        segment.apply(recognizedText: "Hi", translatedText: "RU:Hi", isFinal: true, at: startedAt)
        var session = TranslationSession(startedAt: startedAt, audioSources: [sourceType])
        session.segments = [segment]
        session.status = .stopped
        session.endedAt = Date()
        let transcript = SessionTranscript(session: session, title: "Test session")
        try store.save(transcript)
        return transcript.sessionId
    }

    func testRefreshListsSavedSessions() throws {
        _ = try save(sourceType: .systemAudio)
        _ = try save(sourceType: .microphone)

        let viewModel = SessionHistoryViewModel(store: store, sessionsDirectory: tempDirectory)
        viewModel.refresh()

        XCTAssertEqual(viewModel.summaries.count, 2)
    }

    /// SC-006: deleting a session is a single call/action, and only affects that one session.
    func testDeleteRemovesOnlyTheTargetedSession() throws {
        let keep = try save(sourceType: .systemAudio)
        let remove = try save(sourceType: .microphone)

        let viewModel = SessionHistoryViewModel(store: store, sessionsDirectory: tempDirectory)
        viewModel.refresh()
        XCTAssertEqual(viewModel.summaries.count, 2)

        viewModel.delete(sessionId: remove)  // <- the one action

        XCTAssertEqual(viewModel.summaries.count, 1)
        XCTAssertEqual(viewModel.summaries.first?.sessionId, keep)
    }
}
