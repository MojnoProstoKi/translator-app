# Data Model: Перевод речи собеседника в реальном времени (macOS)

Извлечено из Key Entities в [spec.md](./spec.md) и уточнений в [Clarifications](./spec.md#clarifications).

## TranslationSession (Сессия перевода)

Период с момента запуска до остановки прослушивания одного или нескольких источников звука.

| Поле | Тип | Описание |
|---|---|---|
| `id` | UUID | Уникальный идентификатор сессии |
| `startedAt` | Date | Момент запуска сессии |
| `endedAt` | Date? | Момент остановки; `nil`, пока сессия активна |
| `audioSources` | Set\<AudioSourceType\> | Источники, включённые в этой сессии (микрофон и/или системный звук) |
| `status` | SessionStatus | `.active` \| `.stopped` |
| `segments` | [SpeechSegment] | Упорядоченная по времени последовательность распознанных фрагментов речи |

**Validation rules**:
- `endedAt` MUST быть `nil`, пока `status == .active`, и MUST быть установлен при переходе в `.stopped`.
- `audioSources` MUST содержать хотя бы один элемент (FR-001, FR-007).
- `segments` упорядочены по `SpeechSegment.startedAt` по возрастанию.

**State transitions**: `.active → .stopped` (терминальный переход для конкретной сессии).
Повторный запуск перевода после остановки создаёт **новую** `TranslationSession` с новым `id`
(FR-016: каждая сессия хранится как отдельная запись) — предыдущая сессия не возобновляется, а
завершается окончательно.

## AudioSource (Источник аудио)

Конфигурация конкретного потока звука, который может слушать приложение.

| Поле | Тип | Описание |
|---|---|---|
| `type` | AudioSourceType | `.microphone` \| `.systemAudio` |
| `permissionState` | PermissionState | `.notRequested` \| `.granted` \| `.denied` |

**Validation rules**:
- Сессию нельзя перевести в `.active` для источника, чей `permissionState != .granted` (FR-010).
- При отзыве разрешения во время активной сессии источник MUST перейти в `.denied`, а связанный
  с ним захват — прекратиться (FR-014).

## SpeechSegment (Фрагмент речи / реплика)

Непрерывный отрезок распознанной английской речи собеседника.

| Поле | Тип | Описание |
|---|---|---|
| `id` | UUID | Идентификатор фрагмента |
| `sessionId` | UUID | Ссылка на родительскую `TranslationSession` |
| `sourceType` | AudioSourceType | Источник, из которого распознан фрагмент |
| `startedAt` | Date | Момент начала произнесения (для расчёта задержки, SC-001) |
| `state` | SegmentState | `.recognizing` \| `.partiallyTranslated` \| `.finalized` |
| `recognizedText` | String | Распознанный английский текст (может обновляться до `.finalized`) |
| `translation` | SegmentTranslation | Текущий перевод фрагмента |

**Validation rules**:
- `recognizedText` и `translation.text` MUST NOT изменяться после перехода `state` в `.finalized`
  (FR-005: уточнения возможны только до завершения фрагмента).
- Если `sourceType` не имеет речи (тишина/шум), новый `SpeechSegment` не создаётся (FR-013).

**State transitions**: `.recognizing → .partiallyTranslated → .finalized`. Переход
`.recognizing → .finalized` напрямую допустим для очень коротких фрагментов без промежуточного
частичного перевода.

**Триггер финализации** (устраняет неопределённость по Edge Case «долгая безостановочная речь
без пауз» в spec.md): `SpeechSegment` переходит в `.finalized`, когда выполняется первое из:
1. `ASRProvider` (SpeechAnalyzer/SpeechTranscriber) сообщает о собственной границе конца
   реплики (voice-activity/utterance boundary) — обычная пауза в речи собеседника;
2. Сегмент достиг максимальной длительности **15 секунд** без обнаруженной границы реплики —
   принудительная финализация, чтобы при длинной безостановочной речи текст в оверлее
   периодически фиксировался и обновлялся, а не рос неограниченно. Оставшаяся часть речи
   продолжается как новый `SpeechSegment`.

## SegmentTranslation (Перевод фрагмента)

| Поле | Тип | Описание |
|---|---|---|
| `text` | String | Текст перевода на русском |
| `isFinal` | Bool | Соответствует ли `SpeechSegment.state == .finalized` |
| `updatedAt` | Date | Момент последнего обновления перевода |

**Validation rules**: `updatedAt` MUST обновляться при каждом уточнении текста, пока `isFinal == false`.

## SessionTranscript (Расшифровка сессии)

Персистентное представление одной `TranslationSession` на диске — ровно один файл на сессию.

| Поле | Тип | Описание |
|---|---|---|
| `sessionId` | UUID | Соответствует `TranslationSession.id` |
| `startedAt` / `endedAt` | Date / Date? | Копируются из сессии на момент сохранения |
| `finalizedSegments` | [SpeechSegment] | Только фрагменты в состоянии `.finalized` |
| `storageURL` | URL | `~/Library/Application Support/<bundle-id>/Sessions/<sessionId>.json` |

**Validation rules**:
- Один `SessionTranscript` соответствует ровно одной `TranslationSession` (FR-016) — не
  допускается объединение нескольких сессий в одну запись.
- Аудио MUST NOT входить в `SessionTranscript` ни в каком виде (FR-011).
- Удаление `SessionTranscript` — это удаление соответствующего файла целиком; должно быть
  выполнимо не более чем за 2 действия в UI (SC-006).
- Автоматическая очистка по сроку давности/объёму отсутствует (см. Clarifications в spec.md).

## SessionTranscriptSummary (Сводка расшифровки — для списка сессий)

Облегчённая проекция `SessionTranscript`, используемая `SessionTranscriptStore.listSessions()`
(см. contracts/translation-engine-api.md), чтобы отображать список прошлых сессий (FR-016) без
загрузки полного содержимого каждой расшифровки.

| Поле | Тип | Описание |
|---|---|---|
| `sessionId` | UUID | Соответствует `TranslationSession.id` / `SessionTranscript.sessionId` |
| `startedAt` / `endedAt` | Date / Date? | Для отображения в списке сессий |
| `sourceTypes` | Set\<AudioSourceType\> | Источники, использованные в сессии |

**Validation rules**: Поля `SessionTranscriptSummary` MUST быть производными от соответствующего
`SessionTranscript` (не хранятся отдельно) — при чтении списка сессий значения читаются из
метаданных файла расшифровки без парсинга `finalizedSegments` целиком.

## Связи между сущностями

```text
TranslationSession 1 ── * SpeechSegment 1 ── 1 SegmentTranslation
TranslationSession 1 ── 0..1 SessionTranscript (создаётся/обновляется при финализации фрагментов)
AudioSource — конфигурационная сущность, на которую ссылаются TranslationSession.audioSources
             и SpeechSegment.sourceType (не персистентная сама по себе, кроме permissionState)
```
