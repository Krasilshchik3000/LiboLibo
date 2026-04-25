# 2026-04-25-23 — Public RSS как gate-сигнал для exclusive-эпизодов

## Контекст

После перехода на «только Transistor API» (см.
[2026-04-25-22-transistor-api-only.md](2026-04-25-22-transistor-api-only.md))
выяснилось: эпизод «Мы пригласили в подкаст ИИ!» (id `3187703`,
podcast «Два по цене одного») в Transistor помечен как **Exclusive** для
платных подписчиков, но в API-выдаче от него **нет ни одного** отличающего
поля — `type=full`, `status=published`, `audio_processing=False`. Документация
Transistor подтверждает: episode-level флага для exclusive нет.

Однако этот эпизод **отсутствует в публичном RSS-фиде** (`/feeds/.../`),
тогда как в API он виден. Это и есть единственный способ отличить
exclusive: эпизод опубликован в Transistor, но Transistor не выдаёт его
через публичный RSS.

## Что сделали

1. Новый файл `api/src/transistor/public-rss.ts`:
   - `fetchPublicMediaUrls(feedUrl)` — тянет публичный RSS, возвращает
     `Set<string>` всех `<enclosure url="…">`.
   - Это gate-сигнал, метаданные эпизодов оттуда мы **не берём**.

2. `api/src/transistor/refresh.ts`:
   - В `refreshOne()` для каждого подкаста дополнительно тянется его
     публичный RSS.
   - `is_premium = (mediaUrl ∉ publicMediaUrls) || type === "bonus"`.
   - Если RSS недоступен — fallback на bonus-only логику + warning.
   - Добавлена опция `RefreshOptions { onlyPodcastIds?: bigint[] }`,
     чтобы можно было прогнать рефреш только для конкретных подкастов.

3. `api/src/transistor/refresh-cli.ts`:
   - Поддерживает `--podcast-id <id>` (можно несколько раз):
     `npm run refresh -- --podcast-id 1371411915`.

## Проверка на проде

`npm run refresh -- --podcast-id 1371411915` (локально с прод-DB):

- `[refresh] 1/1 Два по цене одного → ok episodes=153 premium=34`
- Эпизод **3187703** «Мы пригласили в подкаст ИИ!» → `is_premium=true` ✓
- Эпизод **3181074** «Мы нашли 100…» → `is_premium=false` ✓

До этой правки premium-эпизодов было 31 (только bonus-type), стало 34
(добавились exclusive-эпизоды, у которых `type=full`).

## Открытые вопросы / следующий шаг

- В `episodes` для `podcast_id=1371411915` после прогона лежит **273**
  записи: 153 numeric Transistor id + 120 RSS-style id'ов. Старые 120 —
  «осадок» от Railway cron-refresh, который успел отработать **до**
  деплоя коммита `2d6a85d` (RSS → API). После деплоя этого нового
  коммита нужно:
  - дождаться передеплоя `cron-refresh` сервиса в Railway;
  - удалить «осадок»: `DELETE FROM episodes WHERE id !~ '^[0-9]+$'`.
- В Transistor у Либо-Либо **56 shows**, в БД — **44 podcasts**.
  12 shows из аккаунта не заведены как подкасты в каталоге (Любить
  нельзя воспитывать, Братислава, и т.д.). Это вопрос seed'а, не refresh'а.
- Refresh идёт последовательно по подкастам. При большом росте каталога
  стоит вернуть `CONCURRENCY=8` параллелизм по подкастам.
