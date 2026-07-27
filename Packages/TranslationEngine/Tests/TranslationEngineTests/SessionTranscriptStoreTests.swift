import Foundation
import XCTest

@testable import TranslationEngine

/// Contract tests for `SessionTranscriptStore` (contracts/translation-engine-api.md,
/// data-model.md → SessionTranscript/SessionTranscriptSummary). Uses a throwaway temp directory
/// per test — never touches the real Application Support directory.
final class SessionTranscriptStoreTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranslationEngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func makeTranscript(sourceType: AudioSourceType = .systemAudio) -> SessionTranscript {
        let startedAt = Date()
        var segment = SpeechSegment(sessionId: UUID(), sourceType: sourceType, startedAt: startedAt)
        segment.apply(recognizedText: "Hello there.", translatedText: "RU:Hello there.", isFinal: true, at: startedAt)
        var session = TranslationSession(startedAt: startedAt, audioSources: [sourceType])
        session.segments = [segment]
        session.status = .stopped
        session.endedAt = Date()
        return SessionTranscript(session: session)
    }

    func testSaveThenListReturnsSummary() throws {
        let store = FileSessionTranscriptStore(baseDirectory: tempDirectory)
        let transcript = makeTranscript()

        try store.save(transcript)
        let summaries = try store.listSessions()

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.sessionId, transcript.sessionId)
        XCTAssertEqual(summaries.first?.sourceTypes, transcript.audioSources)
    }

    /// FR-016: deleting one session MUST NOT affect any other session's stored record.
    func testDeleteIsolatesOtherSessions() throws {
        let store = FileSessionTranscriptStore(baseDirectory: tempDirectory)
        let first = makeTranscript(sourceType: .systemAudio)
        let second = makeTranscript(sourceType: .microphone)
        try store.save(first)
        try store.save(second)

        try store.delete(sessionId: first.sessionId)
        let remaining = try store.listSessions()

        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.sessionId, second.sessionId)
    }

    /// FR-011: a saved transcript file MUST NOT contain any raw audio data — only the JSON
    /// text fields defined by SessionTranscript.
    func testSavedFileContainsNoAudioData() throws {
        let store = FileSessionTranscriptStore(baseDirectory: tempDirectory)
        let transcript = makeTranscript()
        try store.save(transcript)

        let fileURL = tempDirectory.appendingPathComponent("\(transcript.sessionId.uuidString).json")
        let data = try Data(contentsOf: fileURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json)
        XCTAssertNil(json?["audio"])
        XCTAssertNil(json?["samples"])
    }
}
