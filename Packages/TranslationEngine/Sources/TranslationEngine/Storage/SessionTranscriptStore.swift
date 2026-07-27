import Foundation

public enum SessionTranscriptStoreError: Error, Equatable {
    case sessionNotFound(UUID)
}

/// Default directory used in production: one JSON file per session, under
/// `~/Library/Application Support/<bundle-id>/Sessions/` (data-model.md, research.md §6).
extension FileSessionTranscriptStore {
    public static func defaultBaseDirectory(bundleIdentifier: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Sessions", isDirectory: true)
    }
}

/// A `SessionTranscriptStore` backed by one JSON file per session (FR-012, FR-016).
///
/// No audio is ever written — `SessionTranscript` has no field capable of holding it (FR-011).
/// A plain flat-file layout was chosen over a database for simplicity (research.md §6, YAGNI):
/// operations are limited to save/list/delete of independent, modestly-sized text records.
public final class FileSessionTranscriptStore: SessionTranscriptStore, @unchecked Sendable {
    private let baseDirectory: URL
    private let fileManager: FileManager = .default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    private func fileURL(for sessionId: UUID) -> URL {
        baseDirectory.appendingPathComponent("\(sessionId.uuidString).json")
    }

    public func save(_ transcript: SessionTranscript) throws {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode(transcript)
        try data.write(to: fileURL(for: transcript.sessionId), options: .atomic)
    }

    public func listSessions() throws -> [SessionTranscriptSummary] {
        guard fileManager.fileExists(atPath: baseDirectory.path) else { return [] }
        let files = try fileManager.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        // A file that fails to decode (e.g. saved by an older build under a since-changed
        // `SessionTranscript` schema) is skipped rather than failing the whole list — one stale
        // file shouldn't make every other session inaccessible.
        return files.compactMap { url -> SessionTranscriptSummary? in
            do {
                let data = try Data(contentsOf: url)
                let transcript = try decoder.decode(SessionTranscript.self, from: data)
                return SessionTranscriptSummary(transcript: transcript)
            } catch {
                EngineLog.error("FileSessionTranscriptStore: skipping unreadable session file \(url.lastPathComponent): \(error)")
                return nil
            }
        }
        .sorted { $0.startedAt < $1.startedAt }
    }

    /// Deletes exactly one session's record (FR-016) — never touches any other file.
    public func delete(sessionId: UUID) throws {
        let url = fileURL(for: sessionId)
        guard fileManager.fileExists(atPath: url.path) else {
            throw SessionTranscriptStoreError.sessionNotFound(sessionId)
        }
        try fileManager.removeItem(at: url)
    }
}
