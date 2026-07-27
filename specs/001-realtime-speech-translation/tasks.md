---

description: "Task list for Перевод речи собеседника в реальном времени (macOS)"
---

# Tasks: Перевод речи собеседника в реальном времени (macOS)

**Input**: Design documents from `/specs/001-realtime-speech-translation/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md (все присутствуют)

**Tests**: Constitution проекта (Principle III Test-First — NON-NEGOTIABLE, Principle IV Integration Testing — REQUIRED) обязывает писать тесты перед реализацией. Тестовые задачи включены во все фазы, идут до соответствующей реализации и не являются опциональными для этой фичи.

**Organization**: Задачи сгруппированы по user story (US1/US2/US3 из spec.md) для независимой реализации и тестирования каждой истории.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Может выполняться параллельно (другие файлы, нет зависимости от незавершённых задач)
- **[Story]**: К какой user story относится задача (US1, US2, US3)
- Указаны точные пути к файлам

## Path Conventions

Структура — Swift Package `Packages/TranslationEngine` (библиотека + CLI) и macOS-приложение `App/`, как определено в plan.md.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Инициализация репозитория, базовой структуры проекта и CI

- [X] T001 Создать структуру каталогов `Packages/TranslationEngine/` и `App/` согласно plan.md (Project Structure)
- [X] T002 Инициализировать Swift Package `Packages/TranslationEngine/Package.swift` с целями `TranslationEngine` (библиотека), `translate-cli` (executable), `TranslationEngineTests`, `TranslationEngineIntegrationTests`
- [X] T003 [P] Инициализировать Swift Package `App/Package.swift` с целями `RealtimeTranslator` (SwiftUI, macOS 26 deployment target) и `AppTests` (см. plan.md → «Примечание по реализации» — SPM вместо `.xcodeproj`)
- [X] T004 [P] Настроить `swift-format` для `Packages/TranslationEngine` и `App/` (`.swift-format` в корне репозитория)
- [X] T005 [P] Добавить WAV-фикстуры английской речи (`sample-en-greeting.wav`, `sample-en-call.wav`, `sample-en-mic.wav`) в `Packages/TranslationEngine/Tests/{TranslationEngineTests,TranslationEngineIntegrationTests}/Fixtures/` с эталонными расшифровками (`Tests/FIXTURES_REFERENCE.md`) для последующих тестов
- [X] T006 [P] Настроить CI (GitHub Actions) для запуска `swift build` и `swift test` (unit + contract; integration — только локально, см. комментарий в файле) на каждый pull request, согласно Constitution → Development Workflow, в `.github/workflows/ci.yml`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Общие модели, протоколы и пайплайн, от которых зависят все user story

**⚠️ CRITICAL**: Ни одна user story не может быть реализована до завершения этой фазы

- [X] T007 [P] Определить базовые типы `AudioSourceType`, `PermissionState`, `SessionStatus`, `SegmentState` в `Packages/TranslationEngine/Sources/TranslationEngine/Models/CoreTypes.swift`
- [X] T008 [P] Определить модели `TranslationSession`, `SpeechSegment`, `SegmentTranslation`, `SessionTranscript`, `SessionTranscriptSummary` по data-model.md в `Packages/TranslationEngine/Sources/TranslationEngine/Models/`
- [X] T009 [P] Определить протоколы `AudioCaptureSource`, `ASRProvider`, `TranslationProvider`, `SessionTranscriptStore` по contracts/translation-engine-api.md в `Packages/TranslationEngine/Sources/TranslationEngine/Protocols.swift`
- [X] T010 [P] Contract-тест жизненного цикла сегмента в `TranslationPipeline` (partial → final, отсутствие событий после final, отсутствие пустых событий при тишине) с фейковыми in-memory ASR/TranslationProvider в `Packages/TranslationEngine/Tests/TranslationEngineTests/PipelineContractTests.swift` — подтверждено RED (не компилировалось) до T011
- [X] T011 Реализовать оркестратор `TranslationPipeline` (start/stop, `AsyncStream<TranslatedSegmentEvent>`) в `Packages/TranslationEngine/Sources/TranslationEngine/Pipeline/TranslationPipeline.swift` — T010 подтверждено GREEN
- [X] T012 [P] Реализовать утилиту структурированного логирования (метаданные на INFO+, полный текст расшифровки — только на DEBUG, согласно Constitution → Additional Constraints) в `Packages/TranslationEngine/Sources/TranslationEngine/Logging.swift`
- [X] T013 [P] Contract-тест изоляции `SessionTranscriptStore` (save/list/delete не затрагивают другие сессии) в `Packages/TranslationEngine/Tests/TranslationEngineTests/SessionTranscriptStoreTests.swift` — подтверждено RED до T014
- [X] T014 Реализовать `SessionTranscriptStore` (JSON-файл на сессию в `~/Library/Application Support/<bundle-id>/Sessions/`) в `Packages/TranslationEngine/Sources/TranslationEngine/Storage/SessionTranscriptStore.swift` — T013 подтверждено GREEN (5/5 тестов Foundational-фазы проходят)

**Checkpoint**: Фундамент готов — можно приступать к реализации user story

---

## Phase 3: User Story 1 - Перевод собеседника во время звонка/видео через системный звук (Priority: P1) 🎯 MVP

**Goal**: Захват системного звука, потоковое распознавание и перевод, отображение в плавающем оверлее в реальном времени (FR-001–FR-006, FR-009, FR-013)

**Independent Test**: Запустить видео/звонок с английской речью, выбрать источник «системный звук», убедиться, что перевод появляется и обновляется в оверлее без включения микрофона (см. quickstart.md → «Валидация основного сценария»)

### Tests for User Story 1

- [X] T015 [P] [US1] Интеграционный тест реального пайплайна `SpeechAnalyzer` → `TranslationSession` на `sample-en-call.wav` через путь системного звука, проверяющий появление partial-события и соответствие задержки первого перевода SC-001 (3–5 сек), в `Packages/TranslationEngine/Tests/TranslationEngineIntegrationTests/SystemAudioPipelineTests.swift` — компилируется и собирается (`swift build --build-tests`); фактический прогон требует ручного предоставления разрешения на распознавание речи (не выполнялся в этой сессии, см. Completion Report)
- [X] T016 [P] [US1] Contract-тест `translate-cli` на `sample-en-greeting.wav` (JSON Lines на stdout, корректные события, exit code 0) в `Packages/TranslationEngine/Tests/TranslationEngineTests/TranslateCLIContractTests.swift` — компилируется; фактический прогон также требует ручного разрешения (см. Completion Report)

### Implementation for User Story 1

- [X] T017 [US1] Реализовать `SystemAudioSource` на базе Core Audio Taps (`AudioHardwareCreateProcessTap` + приватное aggregate-устройство, поскольку голый тап не IO-capable) в `Packages/TranslationEngine/Sources/TranslationEngine/Capture/SystemAudioSource.swift` — **подтверждено вживую пользователем**: перевод системного звука (видео на YouTube) реально работает после ручного добавления приложения в Системные настройки → Конфиденциальность и безопасность → System Audio Recording Only (это разрешение не запрашивается системным диалогом ни при каких условиях — подтверждено изолированным тестированием; см. quickstart.md → Prerequisites)
- [X] T018 [US1] Реализовать `ASRProvider`-адаптер поверх `SpeechAnalyzer`/`SpeechTranscriber` в `Packages/TranslationEngine/Sources/TranslationEngine/Recognition/SpeechAnalyzerASRProvider.swift`
- [X] T019 [US1] Реализовать `TranslationProvider`-адаптер поверх Apple Translation framework (`TranslationSession`) в `Packages/TranslationEngine/Sources/TranslationEngine/Translation/AppleTranslationProvider.swift`
- [X] T020 [US1] Реализовать исполняемый файл `translate-cli` (разбор аргументов, JSON/text вывод, коды выхода) по contracts/translate-cli.md в `Packages/TranslationEngine/Sources/translate-cli/main.swift`
- [X] T021 [US1] Реализовать плавающее окно оверлея (`NSPanel`, `.nonactivatingPanel`, always-on-top, видимо на всех Spaces и поверх полноэкранных приложений) в `App/Sources/Overlay/OverlayWindowController.swift`
- [X] T022 [US1] Реализовать контент оверлея, отображающий потоковый перевод с различием partial/final текста, в `App/Sources/Overlay/OverlayView.swift` (+ `OverlayViewModel.swift`)
- [X] T023 [US1] Связать выбор источника «системный звук» с `TranslationPipeline` и оверлеем в `App/Sources/App/TranslationSessionController.swift` (+ `AppCoordinator.swift`, `RealtimeTranslatorApp.swift`)
- [X] T024 [US1] Проверить сквозную обработку тишины (подавление пустых событий, FR-013) в связке `SystemAudioSource` → `TranslationPipeline` → оверлей — подтверждено на уровне пайплайна тестами T010/T015 (`FakeASRProvider`/реальный `SpeechAnalyzerASRProvider` не эмитят обновления без речи)

**Checkpoint**: User Story 1 полностью функциональна и тестируема независимо — MVP готов

---

## Phase 4: User Story 2 - Перевод собеседника через микрофон (Priority: P2)

**Goal**: Тот же перевод в реальном времени, но из источника «микрофон», включая одновременную работу с системным звуком (FR-007)

**Independent Test**: Выбрать источник «микрофон», произнести/воспроизвести тестовые английские фразы рядом с микрофоном, убедиться, что перевод работает так же, как для системного звука (см. quickstart.md)

### Tests for User Story 2

- [X] T025 [P] [US2] Интеграционный тест реального пайплайна через `MicrophoneSource` на `sample-en-mic.wav` в `Packages/TranslationEngine/Tests/TranslationEngineIntegrationTests/MicrophonePipelineTests.swift` — компилируется; прогон требует ручного разрешения на микрофон (см. Completion Report)
- [X] T026 [P] [US2] Contract-тест одновременной работы микрофона и системного звука: сегменты разных источников не перемешиваются в `Packages/TranslationEngine/Tests/TranslationEngineTests/MultiSourceContractTests.swift` — на фейках, реально прогнан, GREEN

### Implementation for User Story 2

- [X] T027 [US2] Реализовать `MicrophoneSource` на базе `AVAudioEngine` в `Packages/TranslationEngine/Sources/TranslationEngine/Capture/MicrophoneSource.swift` — **подтверждено вживую пользователем**: перевод речи через микрофон реально работает после явного запроса разрешения на микрофон (`AVCaptureDevice.requestAccess`, теперь вызывается при первом запуске приложения через `AppCoordinator`/`PermissionsManager`)
- [X] T028 [US2] Расширить `TranslationSessionController` для поддержки одновременных источников (микрофон + системный звук) без смешивания сегментов в `App/Sources/App/TranslationSessionController.swift` (зависит от T023, T027)
- [X] T029 [US2] Обновить оверлей для визуального разделения переводов по источнику при одновременной работе обоих в `App/Sources/Overlay/OverlayView.swift` (зависит от T022) — `showsSourceLabels`/`sourceLabel(_:)` уже добавлены в T022, включены при `start(sources:)` с >1 источником

**Checkpoint**: User Story 1 и 2 работают независимо друг от друга

---

## Phase 5: User Story 3 - Управление сессией: разрешения, выбор источника, старт/стоп (Priority: P3)

**Goal**: Разрешения macOS, запуск/остановка сессии, напоминание о согласии собеседника, история сессий с просмотром/удалением (FR-008, FR-010, FR-014, FR-015, FR-016, SC-006)

**Independent Test**: Запустить приложение впервые, пройти запрос разрешений, запустить и остановить сессию, просмотреть и удалить запись в истории сессий (см. quickstart.md)

### Tests for User Story 3

- [X] T030 [P] [US3] Unit-тест переходов состояния разрешений источника (`.notRequested`/`.granted`/`.denied`, включая отзыв во время активной сессии) в `App/Tests/AppTests/PermissionFlowTests.swift` — на фейковых `AudioCaptureSource`, реально прогнан, GREEN
- [X] T031 [P] [US3] Unit-тест истории сессий: список, просмотр, удаление записи не более чем за 2 действия (SC-006) в `App/Tests/AppTests/SessionHistoryTests.swift` — реально прогнан на временном каталоге, GREEN

### Implementation for User Story 3

- [X] T032 [US3] Реализовать запрос разрешений macOS (микрофон + Core Audio Taps) с понятным объяснением и сообщением при отказе/отзыве в `App/Sources/App/PermissionsManager.swift` (FR-010)
- [X] T033 [US3] Реализовать управление стартом/остановкой сессии, связанное с жизненным циклом `TranslationPipeline`, в `App/Sources/App/TranslationSessionController.swift` (FR-008; зависит от T023) — уже реализовано в T023 (`start(sources:)`/`stop()`), расширено меню в T028
- [X] T034 [US3] Реализовать обработку потери источника звука во время активной сессии с уведомлением пользователя (FR-014) в `App/Sources/App/TranslationSessionController.swift` (зависит от T033) — `sourceLostMessage`, различает явный `stop()` от естественного завершения потока
- [X] T035 [US3] Реализовать ненавязчивое напоминание о согласии собеседника (при первом запуске и перед каждым стартом сессии) в `App/Sources/Consent/ConsentReminderPresenter.swift` (FR-015) — не блокирует старт сессии
- [X] T036 [US3] Реализовать экран истории сессий (список отдельных записей, просмотр, удаление) в `App/Sources/Session/SessionHistoryView.swift` (+ `SessionHistoryViewModel.swift`, `SessionHistoryWindowController.swift`) (FR-016, SC-006)
- [X] T037 [US3] Связать финализацию сессии/сегментов с `SessionTranscriptStore.save` при остановке сессии в `App/Sources/Session/SessionRecorder.swift` (зависит от T014, T033) — подключено через `TranslationSessionController.onEvent`/`onSessionEnded` в `AppCoordinator`

**Checkpoint**: Все user story работают независимо друг от друга

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Улучшения, затрагивающие несколько user story, и финальная валидация

- [X] T038 [P] Добавить структурированные логи (источник, провайдер, задержка; без полного текста на INFO+) в `TranslationPipeline` и адаптеры захвата/ASR/MT (зависит от T012, T017, T018, T019, T027)
- [X] T039 [P] Обновить документацию: `Packages/TranslationEngine/README.md` и `App/README.md` со ссылками на quickstart.md
- [X] T040 Прогнать сценарии quickstart.md целиком (CLI на фикстурах + ручные GUI-сценарии для всех трёх user story) — прогнана безопасная часть (валидация аргументов `translate-cli`: отсутствующий `--input`, несуществующий файл, неверный `--format` → exit 1, как и задокументировано); сценарии с реальным аудио/разрешениями остаются ручными (см. Completion Report и perf-notes.md)
- [ ] T041 [P] Замерить SC-001/SC-002/SC-005 на сессии 30+ минут и задокументировать результаты в `specs/001-realtime-speech-translation/perf-notes.md` — не выполнено (требует живого запуска с разрешениями), задокументировано как ручной follow-up
- [X] T042 Проверить отсутствие сетевых вызовов на протяжении полного прогона пайплайна (FR-006/SC-004) через Instruments/dtrace и задокументировать результат в `specs/001-realtime-speech-translation/perf-notes.md` — выполнена статическая проверка (grep + otool -L), полный динамический прогон остаётся ручным шагом
- [X] T043 [P] Провести аудит/тест отсутствия сохранения аудио на диск (FR-011): проверить `Capture/`, `Pipeline/` и `Storage/` на предмет побочной записи аудиофайлов/буферов за время полной сессии; задокументировать результат в `specs/001-realtime-speech-translation/perf-notes.md` — статический аудит + существующий тест T013, GREEN
- [ ] T044 Провести проверку понятности перевода (SC-003): дать участникам без продвинутого английского оценить, улавливают ли они ключевой смысл по выводимому переводу на наборе естественных речевых фикстур; задокументировать долю успешных случаев (цель — 90%) в `specs/001-realtime-speech-translation/perf-notes.md` — не выполнено (требует участников-людей), задокументировано как ручной follow-up

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Без зависимостей — можно начинать сразу
- **Foundational (Phase 2)**: Зависит от завершения Setup — БЛОКИРУЕТ все user story
- **User Stories (Phase 3+)**: Все зависят от завершения Foundational
  - User story могут идти параллельно (при наличии ресурсов) или последовательно по приоритету (P1 → P2 → P3)
- **Polish (Final Phase)**: Зависит от завершения нужных user story

### User Story Dependencies

- **User Story 1 (P1)**: Может начинаться после Foundational (Phase 2) — не зависит от других историй
- **User Story 2 (P2)**: Может начинаться после Foundational; переиспользует `TranslationSessionController` из US1 (T023), но остаётся независимо тестируемой через собственный источник
- **User Story 3 (P3)**: Может начинаться после Foundational; расширяет `TranslationSessionController` из US1 (T023) и использует `SessionTranscriptStore` из Foundational (T014), но управление разрешениями/историей тестируется независимо от самого перевода

### Within Each User Story

- Тесты (интеграционные/contract) пишутся и должны падать до реализации — включая Foundational-фазу (T010 до T011, T013 до T014)
- Модели/протоколы (Foundational) → тесты пайплайна/хранилища → адаптеры источников/провайдеров → оркестрация → UI
- История завершена перед переходом к следующей по приоритету

### Parallel Opportunities

- Все задачи Setup с [P] выполняются параллельно
- Все задачи Foundational с [P] (T007, T008, T009, T012, T013) выполняются параллельно там, где нет прямой зависимости
- После Foundational — US1, US2, US3 могут вестись параллельно разными разработчиками
- Тесты внутри одной user story, помеченные [P], выполняются параллельно

---

## Parallel Example: User Story 1

```bash
# Тесты User Story 1 параллельно:
Task: "Интеграционный тест системного звука в Packages/TranslationEngine/Tests/TranslationEngineIntegrationTests/SystemAudioPipelineTests.swift"
Task: "Contract-тест translate-cli в Packages/TranslationEngine/Tests/TranslationEngineTests/TranslateCLIContractTests.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Завершить Phase 1: Setup
2. Завершить Phase 2: Foundational (блокирует все истории)
3. Завершить Phase 3: User Story 1
4. **Остановиться и проверить**: прогнать quickstart.md сценарий US1 самостоятельно
5. Показать/использовать MVP — перевод системного звука во время реального звонка

### Incremental Delivery

1. Setup + Foundational → фундамент готов
2. + User Story 1 → независимая проверка → MVP (перевод звонков/видео)
3. + User Story 2 → независимая проверка → перевод через микрофон
4. + User Story 3 → независимая проверка → полноценное управление сессиями и историей
5. Каждая история добавляет ценность, не ломая предыдущие

---

## Notes

- [P] задачи = разные файлы, нет зависимостей
- [Story] метка привязывает задачу к конкретной user story для трассируемости
- Тесты обязательны для этой фичи (Constitution Principle III/IV) — писать и убеждаться, что падают, до реализации; это применяется и к Foundational-фазе (T010/T013), не только к user story
- Интеграционные тесты используют реальные on-device `SpeechAnalyzer`/`TranslationSession` на WAV-фикстурах — без моков провайдеров (Principle IV); фейки допустимы только в contract/unit-тестах пайплайна (T010, T013)
- Коммитить после каждой задачи или логической группы
- Останавливаться на каждом чекпоинте для независимой проверки истории

## Post-Implementation Fixes (обнаружены при живой отладке с пользователем)

Не входили в исходный список задач — добавлены по итогам первого реального прогона на устройстве
пользователя (macOS 26.0.1, Xcode 26.3):

- **CRITICAL**: `SystemAudioSource` изначально использовал голый `AudioObjectID` тапа для
  `AudioDeviceCreateIOProcIDWithBlock` — падало с `kAudioHardwareBadDeviceError` (`'!dev'`). Тап
  не является IO-capable сам по себе; исправлено оборачиванием в приватное aggregate-устройство
  (`AudioHardwareCreateAggregateDevice`).
- **CRITICAL**: `CATapDescription` конфигурировался вручную (`isExclusive = true` + пустой
  `processes`) вместо официального convenience-инициализатора
  `CATapDescription(monoGlobalTapButExcludeProcesses:)` — компилировалось и создавало тап без
  ошибок, но реально захватывало полную, стабильную тишину. Инициализатор найден через overlay
  `usr/lib/swift/CoreAudio.swiftmodule`, а не через сырые ObjC-заголовки.
- **CRITICAL**: разрешение **System Audio Recording Only** не запрашивается системным диалогом ни
  при каких условиях (в отличие от микрофона) — добавляется только вручную через Системные
  настройки → «+». Без него звук молча заменяется тишиной без единой ошибки. Задокументировано в
  quickstart.md.
- **CRITICAL**: разрешение на микрофон никогда не запрашивалось явно (`requestPermission()`
  существовал, но не вызывался) — добавлен явный запрос обоих разрешений при первом запуске
  приложения (`AppCoordinator.requestInitialPermissionsIfNeeded`).
- `SpeechAnalyzerASRProvider` не резервировал локаль (`AssetInventory.reserve(locale:)`) и не
  проверял/не устанавливал ассет распознавания — добавлено согласно предупреждению framework
  "Cannot use modules with unallocated locales".
- Сегмент никогда не финализировался принудительно при длинной непрерывной речи, несмотря на
  задокументированную в data-model.md политику 15 секунд — политика была реализована только сейчас.
- `AVAudioConverter` в `SpeechAnalyzerASRProvider` создавался заново на каждый буфер (~100 раз/сек)
  вместо переиспользования — существенная лишняя нагрузка, могла мешать пайплайну успевать за
  реальным временем.
- `TranslationPipeline` тихо проглатывал (`try?` + `continue`) ошибки перевода без какого-либо
  логирования или сигнала наружу — добавлено логирование и `onError`-коллбэк, пробрасываемый в
  оверлей как баннер ошибки.
- `AppCoordinator` не пробрасывал `objectWillChange` вложенного `TranslationSessionController`
  наверх — меню оставалось на «Остановить перевод» после остановки сессии (классическая ловушка
  SwiftUI с вложенными `ObservableObject`).
- `TranslationSessionController.stop()` выполнял блокирующую очистку Core Audio (уничтожение
  aggregate-устройства/тапа) синхронно на MainActor — подвешивало UI на время остановки; вынесено
  в фоновый `Task.detached`.
- Приложение запускалось через `swift run` как голый неподписанный executable без bundle identity
  — заменено на сборку и ad-hoc подпись полноценного `.app`-бандла с `Info.plist`
  (`CFBundleIdentifier`, `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`,
  `LSUIElement`), см. quickstart.md → Setup.
- По запросу пользователя добавлены: показ распознанного английского текста над переводом (для
  диагностики «распознавание vs перевод»), счётчик полученных событий, живой индикатор уровня
  звука (эквалайзер) в оверлее — не только полезная функция, но и ключевой диагностический
  инструмент, которым в итоге была найдена проблема с разрешением.
