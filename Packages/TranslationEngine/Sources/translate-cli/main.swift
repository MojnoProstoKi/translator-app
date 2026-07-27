import Foundation
import TranslationEngine

// translate-cli — see specs/001-realtime-speech-translation/contracts/translate-cli.md
//
//   translate-cli --input <path-to-wav> [--format json|text] [--source-lang en] [--target-lang ru]

enum ExitCode: Int32 {
    case success = 0
    case argumentError = 1
    case pipelineFailure = 2
    case languagePackMissing = 3
}

struct CLIOptions {
    var inputPath: String
    var format: String = "json"
    var sourceLang: String = "en"
    var targetLang: String = "ru"

    static func parse(_ arguments: [String]) -> CLIOptions? {
        var inputPath: String?
        var format = "json"
        var sourceLang = "en"
        var targetLang = "ru"

        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--input":
                index += 1
                guard index < arguments.count else { return nil }
                inputPath = arguments[index]
            case "--format":
                index += 1
                guard index < arguments.count else { return nil }
                format = arguments[index]
            case "--source-lang":
                index += 1
                guard index < arguments.count else { return nil }
                sourceLang = arguments[index]
            case "--target-lang":
                index += 1
                guard index < arguments.count else { return nil }
                targetLang = arguments[index]
            default:
                return nil
            }
            index += 1
        }

        guard let inputPath, format == "json" || format == "text" else { return nil }
        return CLIOptions(inputPath: inputPath, format: format, sourceLang: sourceLang, targetLang: targetLang)
    }
}

/// Wire format for `--format json` (JSON Lines) — see contracts/translate-cli.md. Distinct from
/// `TranslatedSegmentEvent` so the on-the-wire field names (`latencyMs` as an Int) stay stable
/// regardless of the internal Swift type's representation.
private struct CLIEvent: Encodable {
    let segmentId: String
    let sourceType: String
    let originalText: String
    let translatedText: String
    let isFinal: Bool
    let latencyMs: Int

    init(_ event: TranslatedSegmentEvent) {
        segmentId = event.segmentId.uuidString
        sourceType = event.sourceType.rawValue
        originalText = event.originalText
        translatedText = event.translatedText
        isFinal = event.isFinal
        latencyMs = Int(event.latency * 1000)
    }
}

func fail(_ message: String, code: ExitCode) -> Never {
    FileHandle.standardError.write(Data("translate-cli: \(message)\n".utf8))
    exit(code.rawValue)
}

guard let options = CLIOptions.parse(Array(CommandLine.arguments.dropFirst())) else {
    fail("usage: translate-cli --input <path-to-wav> [--format json|text] [--source-lang en] [--target-lang ru]", code: .argumentError)
}

guard FileManager.default.fileExists(atPath: options.inputPath) else {
    fail("input file not found: \(options.inputPath)", code: .argumentError)
}

if #available(macOS 26.0, *) {
    let inputURL = URL(fileURLWithPath: options.inputPath)
    let source = FileAudioSource(fileURL: inputURL, sourceType: .systemAudio)
    let asr = SpeechAnalyzerASRProvider(locale: Locale(identifier: "\(options.sourceLang)-US"))
    let translation = AppleTranslationProvider(
        source: Locale.Language(identifier: options.sourceLang),
        target: Locale.Language(identifier: options.targetLang)
    )
    let pipeline = TranslationPipeline(sources: [source], asr: asr, translation: translation)

    let encoder = JSONEncoder()
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "HH:mm:ss.SSS"

    do {
        let stream = try pipeline.start()
        for await event in stream {
            switch options.format {
            case "json":
                let data = try encoder.encode(CLIEvent(event))
                print(String(data: data, encoding: .utf8)!)
            default:
                let marker = event.isFinal ? "(final)" : "(partial)"
                print("[\(dateFormatter.string(from: Date()))] \(event.originalText) → \(event.translatedText) \(marker)")
            }
        }
        exit(ExitCode.success.rawValue)
    } catch is LanguagePackNotInstalledError {
        fail("required on-device language pack is not installed", code: .languagePackMissing)
    } catch {
        fail("pipeline error: \(error)", code: .pipelineFailure)
    }
} else {
    fail("translate-cli requires macOS 26 or later", code: .pipelineFailure)
}
