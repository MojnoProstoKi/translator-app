# Contract: TranslationEngine (Swift Package public API)

Публичная поверхность библиотеки `TranslationEngine`, потребляемая как приложением (`App/`), так
и `translate-cli`. Реализует Constitution Principle I (Library-First): вся логика захвата,
распознавания и перевода изолирована здесь и не зависит от UI.

## Протоколы-адаптеры провайдеров

Провайдеры изолированы за протоколами (Constitution: Additional Constraints — "изолировать
provider-specific логику за границей библиотеки"), чтобы `SpeechAnalyzer`/`Translation
framework` можно было заменить (например, на WhisperKit) без изменения вызывающего кода.

```swift
public protocol AudioCaptureSource {
    var sourceType: AudioSourceType { get }               // .microphone | .systemAudio
    var permissionState: PermissionState { get }           // .notRequested | .granted | .denied
    func requestPermission() async -> PermissionState
    func start() throws -> AsyncStream<AudioBuffer>
    func stop()
}

public protocol ASRProvider {
    /// Потребляет буферы аудио одного источника, эмитит обновления распознанных фрагментов.
    func recognize(_ buffers: AsyncStream<AudioBuffer>) -> AsyncStream<RecognizedSegmentUpdate>
}

public protocol TranslationProvider {
    /// Переводит текст с английского на русский; вызывается по каждому обновлению фрагмента.
    func translate(_ text: String, isFinal: Bool) async throws -> String
}
```

## Оркестрация пайплайна

```swift
public struct RecognizedSegmentUpdate {
    public let segmentId: UUID
    public let sourceType: AudioSourceType
    public let text: String          // распознанный английский текст на текущий момент
    public let isFinal: Bool         // true = сегмент завершён (см. SpeechSegment.state)
    public let startedAt: Date
}

public struct TranslatedSegmentEvent {
    public let segmentId: UUID
    public let sourceType: AudioSourceType
    public let originalText: String
    public let translatedText: String
    public let isFinal: Bool
    public let latency: TimeInterval   // startedAt → момент эмита данного события (для SC-001)
}

public final class TranslationPipeline {
    public init(sources: [AudioCaptureSource], asr: ASRProvider, translation: TranslationProvider)

    /// Запускает захват выбранных источников и возвращает поток переведённых обновлений
    /// сегментов речи. Останавливается вызовом `stop()`.
    public func start() throws -> AsyncStream<TranslatedSegmentEvent>
    public func stop()
}
```

**Контрактные гарантии** (проверяются contract-тестами `TranslationEngineTests`):

1. `TranslatedSegmentEvent` для данного `segmentId` эмитится минимум один раз с `isFinal == true`
   до того, как соответствующий `AudioCaptureSource` остановлен штатно (FR-004, FR-005).
2. После события с `isFinal == true` для данного `segmentId` дальнейшие события с тем же
   `segmentId` не эмитятся (соответствует неизменности `SpeechSegment.state == .finalized` в
   data-model.md).
3. Если во входном потоке `AudioBuffer` нет распознаваемой речи (тишина/шум), `ASRProvider` не
   должен порождать новый `RecognizedSegmentUpdate` (FR-013) — пайплайн не эмитит пустые события.
4. `latency` первого события по `segmentId` MUST быть измерима и логируема для проверки SC-001;
   сам контракт не устанавливает числового порога — порог проверяется в интеграционных/приёмочных
   тестах на реальных фикстурах.
5. Ни `ASRProvider`, ни `TranslationProvider` не выполняют сетевых вызовов (проверяется
   интеграционным тестом, отслеживающим сетевую активность процесса — соответствует FR-006/SC-004).

## Хранение сессий

```swift
public protocol SessionTranscriptStore {
    func save(_ transcript: SessionTranscript) throws
    func listSessions() throws -> [SessionTranscriptSummary]   // id, startedAt, endedAt, sourceTypes
    func delete(sessionId: UUID) throws
}
```

**Контрактные гарантии**:
1. `save` не сохраняет аудио ни в каком поле (FR-011) — тип `SessionTranscript` не содержит
   аудиоданных по построению (см. data-model.md).
2. `delete(sessionId:)` удаляет ровно одну запись, не затрагивая другие сессии (FR-016).
3. Каждой `TranslationSession` соответствует не более одного файла расшифровки на диске (FR-016).
