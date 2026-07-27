import Foundation

/// Persists the user's chosen override for where session transcripts are saved. A plain
/// UserDefaults path is enough — the app isn't sandboxed, so there's no security-scoped bookmark
/// to maintain across launches, matching the flat-file, no-database philosophy of
/// `FileSessionTranscriptStore`.
public enum SessionsDirectoryPreference {
    private static let key = "com.translator.sessionsDirectoryPath"

    public static func stored() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: key) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    public static func save(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: key)
    }
}
