# TranslationEngine

Локальная библиотека потокового перевода английской речи на русский для macOS 26+
(`SpeechAnalyzer`/`SpeechTranscriber` + Apple `Translation` framework, полностью on-device).

Спецификация, план и решения по дизайну — в
[`specs/001-realtime-speech-translation/`](../../specs/001-realtime-speech-translation), в
частности [`research.md`](../../specs/001-realtime-speech-translation/research.md) и
[`contracts/`](../../specs/001-realtime-speech-translation/contracts).

## Сборка и тесты

```bash
swift build
swift test --filter TranslationEngineTests   # unit + contract тесты (фейки, без разрешений)
```

`TranslationEngineIntegrationTests` и часть `TranslationEngineTests` (`TranslateCLIContractTests`)
используют реальные `SpeechAnalyzer`/`Translation` и требуют интерактивно предоставленных
разрешений (распознавание речи / микрофон / системный звук) — не запускаются автоматически
(`TranslateCLIContractTests` пропускается, пока не задано `RUN_LIVE_TESTS=1`), см.
[`quickstart.md`](../../specs/001-realtime-speech-translation/quickstart.md).

## CLI

```bash
swift run translate-cli --input path/to/audio.wav --format text
```

См. [`contracts/translate-cli.md`](../../specs/001-realtime-speech-translation/contracts/translate-cli.md).
