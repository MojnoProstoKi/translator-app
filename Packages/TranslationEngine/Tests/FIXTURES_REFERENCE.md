# Test Fixtures Reference

WAV-фикстуры сгенерированы синтезом речи (`say -v Samantha`, 16kHz/16-bit/mono PCM) — не записи
реальных людей, но содержат настоящую распознаваемую английскую речь для сквозного тестирования
ASR → перевод.

| Файл | Эталонный текст |
|---|---|
| `sample-en-greeting.wav` | "Hello there, how are you doing today?" |
| `sample-en-call.wav` | "I think we should schedule the meeting for next Tuesday afternoon, if that works for everyone on the team." |
| `sample-en-mic.wav` | "Can you hear me clearly? I wanted to follow up on the project timeline we discussed yesterday." |

Присутствуют в обоих тестовых таргетах (`TranslationEngineTests/Fixtures`,
`TranslationEngineIntegrationTests/Fixtures`), так как оба используют фикстуры (contract-тест
`translate-cli` и реальные интеграционные тесты пайплайна).
