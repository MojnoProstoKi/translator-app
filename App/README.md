# RealtimeTranslator (App)

Меню-бар приложение macOS, показывающее перевод речи собеседника в реальном времени в плавающем
оверлее (см. [`spec.md`](../specs/001-realtime-speech-translation/spec.md)). Построено поверх
библиотеки [`TranslationEngine`](../Packages/TranslationEngine).

Реализовано как Swift Package (не `.xcodeproj`) — см. `plan.md` → «Примечание по реализации».

## Сборка и запуск

```bash
swift build
swift run RealtimeTranslator
```

При первом запуске появится напоминание о согласии собеседника (FR-015) и, при старте сессии,
системные запросы разрешений на микрофон / системный звук (FR-010).

## Упаковка `.app` для запуска на другом компьютере

```bash
./Scripts/build-app.sh
```

Собирает release-бинарь, упаковывает его в `.build/RealtimeTranslator.app` (с `Resources/Info.plist`,
ad-hoc подписью) и кладёт `.build/RealtimeTranslator.zip` — этот архив можно переносить на другой Mac
(Apple Silicon, macOS 26+). Скрипт печатает инструкции по первому запуску на целевой машине
(снятие карантина Gatekeeper при передаче через AirDrop/почту/браузер, ручная выдача разрешения
System Audio Recording Only — см. [`quickstart.md`](../specs/001-realtime-speech-translation/quickstart.md)).

Или сразу собрать `.dmg`-инсталлятор (drag-and-drop в Applications):

```bash
./Scripts/build-dmg.sh
```

Собирает `.app` (вызывая `build-app.sh`) и кладёт `.build/RealtimeTranslator.dmg` — при открытии
показывает иконку приложения рядом с ярлыком `Applications`, перетащить одно на другое для установки.

## Тесты

```bash
swift test
```

`PermissionFlowTests` и `SessionHistoryTests` используют фейки/временные каталоги — реальные
разрешения не задействуются.

## Структура

- `Sources/App` — точка входа (`RealtimeTranslatorApp`), координатор (`AppCoordinator`), контроллер
  сессии, менеджер разрешений
- `Sources/Overlay` — плавающее окно перевода (`NSPanel`) и его SwiftUI-контент
- `Sources/Session` — запись сессии в `SessionTranscriptStore` и экран истории сессий
- `Sources/Consent` — ненавязчивое напоминание о согласии собеседника

См. [`quickstart.md`](../specs/001-realtime-speech-translation/quickstart.md) для ручных сценариев
проверки.
