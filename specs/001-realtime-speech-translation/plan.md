# Implementation Plan: Перевод речи собеседника в реальном времени (macOS)

**Branch**: `001-realtime-speech-translation` | **Date**: 2026-07-24 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-realtime-speech-translation/spec.md`

## Summary

Локальное настольное macOS-приложение, которое захватывает аудио с микрофона и/или системного
звука (звонки в Zoom/Teams/Discord, видео), распознаёт англоязычную речь собеседника в потоковом
режиме через Apple SpeechAnalyzer/SpeechTranscriber и переводит распознанные фрагменты на русский
через Apple Translation framework — полностью on-device, без каких-либо сетевых вызовов. Перевод
отображается инкрементально в плавающем always-on-top оверлее поверх других приложений с задержкой
3–5 секунд от начала фразы. Расшифровки сессий сохраняются локально как отдельные записи (по одной
на сессию), которые пользователь может просматривать и удалять независимо друг от друга.

## Technical Context

**Language/Version**: Swift 6.0+ (Xcode 17+), сборка под macOS 26 (Tahoe) SDK

**Primary Dependencies**:
- Apple **Speech** framework — `SpeechAnalyzer` / `SpeechTranscriber` (потоковое on-device
  распознавание речи, замена устаревшего `SFSpeechRecognizer`, доступно с macOS 26)
- Apple **Translation** framework — `TranslationSession` (on-device перевод текста, доступен с
  macOS 14.4, но приложение таргетирует macOS 26 из-за требования к ASR)
- **Core Audio Taps** (`AudioHardwareCreateProcessTap`, `CATapDescription`, macOS 14.4+) — захват
  системного звука без разрешения на запись экрана
- `AVAudioEngine` — захват микрофона
- SwiftUI + AppKit (`NSPanel`) — плавающий always-on-top оверлей
- Сторонние зависимости не требуются для MVP — все компоненты первого поколения от Apple
  (WhisperKit и локальная СУБД рассмотрены и отклонены, см. research.md)

**Storage**: Плоские JSON-файлы, по одному на сессию, в
`~/Library/Application Support/<bundle-id>/Sessions/`; без базы данных (см. research.md)

**Testing**: XCTest для unit- и contract-тестов; интеграционные тесты прогоняют реальный
on-device пайплайн SpeechAnalyzer → Translation на предзаписанных WAV-фикстурах — без моков
провайдеров распознавания/перевода (Constitution Principle IV)

**Target Platform**: macOS 26 (Tahoe) и новее, Apple Silicon (M1 или новее) — минимальные
требования продиктованы `SpeechAnalyzer`/`SpeechTranscriber` и Core Audio Taps

**Project Type**: macOS desktop app (SwiftUI/AppKit), опирающийся на отдельный Swift Package
(Library-First: движок захвата/распознавания/перевода отделён от UI-приложения)

**Performance Goals**:
- Первые слова перевода — не позднее 3–5 сек после начала фразы (SC-001)
- Запуск сессии перевода — не более 5 сек от выбора источника до первого перевода (SC-005)
- Отсутствие подвисаний интерфейса, пропуска кадров видео или прерывания звука в звонке/видео на
  протяжении сессии 30+ минут (SC-002)

**Constraints**:
- Полностью офлайн/on-device: никаких сетевых вызовов для ASR/MT (FR-006)
- Аудио не сохраняется на диск ни в каком виде (FR-011)
- Оверлей должен отображаться поверх полноэкранных приложений и окон, транслируемых через
  screen-share (FR-009)
- Текст расшифровки не логируется целиком на уровне INFO и выше (Constitution: Additional
  Constraints)

**Scale/Scope**: Один пользователь на одном устройстве; одна активная сессия на источник звука
одновременно; неограниченное количество сохранённых сессий без автоматической очистки (см.
Clarifications в spec.md)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Принцип | Статус | Обоснование |
|---|---|---|
| I. Library-First | PASS | Захват аудио, ASR-адаптер, MT-адаптер и потоковый пайплайн выделены в отдельный Swift Package `TranslationEngine`, независимый от UI, самодостаточный и тестируемый отдельно от приложения. |
| II. CLI Interface | PASS | `TranslationEngine` поставляется с исполняемой целью `translate-cli`, принимающей аудиофайл/путь и языковые коды через аргументы, выводящей поток JSON-событий (частичный/финальный перевод) в stdout и ошибки в stderr — используется для тестирования и автоматизации пайплайна независимо от GUI. |
| III. Test-First (NON-NEGOTIABLE) | PASS | `/speckit-tasks` обязан располагать тестовые задачи перед задачами реализации для каждой пользовательской истории; гейт применяется на этапе `/speckit-implement`. |
| IV. Integration Testing | PASS | Интеграционные тесты пайплайна используют реальные `SpeechAnalyzer`/`TranslationSession` на локальных WAV-фикстурах — без моков on-device провайдеров, как того требует принцип. |
| V. Observability, Versioning & Simplicity | PASS | Структурированное логирование метаданных (источник, ASR/MT-провайдер, задержка) без текста расшифровки на уровне INFO+; `TranslationEngine` версионируется по MAJOR.MINOR.BUILD; хранение данных — простые JSON-файлы вместо БД (YAGNI). |

Нарушений, требующих записи в Complexity Tracking, не выявлено.

## Project Structure

### Documentation (this feature)

```text
specs/001-realtime-speech-translation/
├── plan.md              # This file (/speckit-plan command output)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command)
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── contracts/           # Phase 1 output (/speckit-plan command)
│   ├── translation-engine-api.md
│   └── translate-cli.md
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
Packages/
└── TranslationEngine/
    ├── Package.swift
    ├── Sources/
    │   ├── TranslationEngine/        # захват аудио, ASR/MT-адаптеры, потоковый пайплайн, модели
    │   │   ├── Capture/              # MicrophoneSource, SystemAudioSource (Core Audio Taps)
    │   │   ├── Recognition/          # ASRProvider-адаптер над SpeechAnalyzer/SpeechTranscriber
    │   │   ├── Translation/          # TranslationProvider-адаптер над Translation framework
    │   │   ├── Pipeline/             # оркестрация: аудио → сегменты речи → переводы
    │   │   └── Models/               # TranslationSession, SpeechSegment, SegmentTranslation
    │   └── translate-cli/            # CLI-исполняемый файл поверх TranslationEngine
    └── Tests/
        ├── TranslationEngineTests/            # unit + contract-тесты адаптеров и пайплайна
        └── TranslationEngineIntegrationTests/ # реальный ASR+MT на WAV-фикстурах

App/
├── Package.swift          # SPM-приложение (не .xcodeproj — см. примечание ниже)
├── Sources/
│   ├── App/          # SwiftUI App entry point, поток запроса разрешений (FR-010)
│   ├── Overlay/       # плавающее always-on-top окно перевода (FR-009)
│   ├── Session/       # управление сессиями, хранение расшифровок в JSON (FR-012, FR-016)
│   └── Consent/       # ненавязчивое напоминание о согласии собеседника (FR-015)
└── Tests/
    └── AppTests/      # unit-тесты слоя управления сессиями и хранения
```

**Structure Decision**: Двухкомпонентная структура — библиотека `Packages/TranslationEngine`
(захват звука, ASR, MT, потоковая оркестрация, CLI) и приложение `App/` (SwiftUI/AppKit GUI,
оверлей, хранение сессий). Разделение соответствует принципу Library-First: движок перевода
самодостаточен, тестируется и используется как через CLI, так и через GUI-приложение.

**Примечание по реализации**: `App/` реализован как отдельный Swift Package (`App/Package.swift`)
с исполняемой целью `RealtimeTranslator`, а не как `.xcodeproj`. Причина: нет инструмента для
программной генерации `.xcodeproj` «с нуля» (обычно создаётся мастером Xcode вручную); ручное
написание `project.pbxproj` избыточно рискованно. Чистый SPM-таргет собирается и запускается
через `swift build`/`swift run` и полностью поддерживается Xcode (открывается напрямую через
`open App/Package.swift`) для отладки, назначения entitlements и дальнейшей упаковки в `.app`
при необходимости. Изменений в Constitution Check это не требует.

## Complexity Tracking

> Нарушений Constitution Check нет — таблица не заполняется.
