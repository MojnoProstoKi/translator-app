import Foundation
import os

/// Structured logging for the translation pipeline (Constitution → Additional Constraints,
/// Principle V: Observability).
///
/// Recognized/translated text is potentially sensitive (it may contain a third party's speech,
/// see spec.md Clarifications) and MUST NOT be logged in full at INFO level or above. Metadata
/// (source, provider, latency) is safe to log at INFO for observability.
public enum EngineLog {
    private static let logger = Logger(subsystem: "com.translator.engine", category: "pipeline")

    /// Logs event metadata only — safe at INFO and above. Never pass segment text here.
    /// `textLength` (character count, not content) lets a "no translation appears" report be
    /// diagnosed from Console logs alone — e.g. distinguishing an empty/near-empty recognized
    /// fragment from a real translation failure — without ever logging the text itself.
    public static func segmentMetadata(
        source: AudioSourceType,
        provider: String,
        latencySeconds: TimeInterval,
        isFinal: Bool,
        textLength: Int
    ) {
        logger.info(
            """
            segment source=\(source.rawValue, privacy: .public) \
            provider=\(provider, privacy: .public) \
            latencyMs=\(Int(latencySeconds * 1000), privacy: .public) \
            final=\(isFinal, privacy: .public) \
            textLength=\(textLength, privacy: .public)
            """
        )
    }

    /// Logs the full recognized/translated text at DEBUG level only, additionally marked
    /// `.private` so it is redacted from the log unless the user has explicitly enabled
    /// sensitive logging on their device.
    public static func debugText(original: String, translated: String) {
        logger.debug(
            "text original=\(original, privacy: .private) translated=\(translated, privacy: .private)"
        )
    }

    /// Logs a non-content error/diagnostic (e.g. permission denied, provider failure).
    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
