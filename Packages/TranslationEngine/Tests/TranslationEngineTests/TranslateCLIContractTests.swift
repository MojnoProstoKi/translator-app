import Foundation
import XCTest

/// Contract test for the `translate-cli` executable (contracts/translate-cli.md).
///
/// ⚠️ This spawns the real `translate-cli` binary, which invokes the real on-device
/// SpeechAnalyzer/Translation frameworks — the same permission caveats as
/// TranslationEngineIntegrationTests apply, and without a permission grant the binary hangs
/// rather than failing. Skipped unless `RUN_LIVE_TESTS=1` is set; run manually after
/// `swift build`. See quickstart.md.
final class TranslateCLIContractTests: XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Live on-device test — set RUN_LIVE_TESTS=1 to run")
        }
    }

    private func fixtureURL(_ name: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Fixtures")!
    }

    private func cliExecutableURL() throws -> URL {
        // Built by `swift build` at Packages/TranslationEngine/.build/<triple>/debug/translate-cli.
        let thisFile = URL(fileURLWithPath: #filePath)
        let packageRoot = thisFile
            .deletingLastPathComponent()  // TranslationEngineTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // TranslationEngine package root
        let candidates = [
            packageRoot.appendingPathComponent(".build/debug/translate-cli"),
            packageRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/translate-cli"),
        ]
        guard let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("translate-cli binary not found — run `swift build` first")
        }
        return found
    }

    /// Exit code 0 and one JSON object per line (JSON Lines) on stdout, per contract.
    func testJSONOutputIsJSONLinesWithExitCodeZero() throws {
        let cli = try cliExecutableURL()
        let process = Process()
        process.executableURL = cli
        process.arguments = ["--input", fixtureURL("sample-en-greeting").path, "--format", "json"]

        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        let lines = String(data: data, encoding: .utf8)!
            .split(separator: "\n")
            .filter { !$0.isEmpty }
        XCTAssertFalse(lines.isEmpty, "Expected at least one JSON Lines event")
        for line in lines {
            let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            XCTAssertNotNil(object?["segmentId"])
            XCTAssertNotNil(object?["translatedText"])
        }
    }
}
