# 2026-04-25-25 — Security and performance review

## Контекст

Пользователь попросил пройтись по проекту и проверить, нет ли security bugs,
security issues и неоптимальных загрузок. Перед ревью прочитан свежий лог
`2026-04-25-24-adapty-entitlement-backend.md` и актуальные спеки бэкенда,
Adapty entitlement и Instagram feed.

Рабочее дерево на старте: `main`, единственное изменение — уже существующий
untracked `AGENTS.md`; его не трогали.

## Что проверили

- Бэкенд Express/Prisma: роуты `/v1/feed`, `/v1/podcasts`, `/v1/episodes`,
  `/v1/devices`, `/v1/me/entitlement`, middleware viewer, serialization,
  клиенты Transistor, Adapty и Instagram Graph API.
- iOS: `APIClient`, `PodcastsRepository`, `DownloadService`, `PlayerService`,
  основные views фида, поиска и деталей подкаста.
- Секреты и ignore-правила: `.env*`, `*.env`, сертификаты, ключи, plist-ы.
- Dependency audit runtime-зависимостей через `npm audit --omit=dev --json`.
- iOS build: generic iOS Simulator destination.

## Результаты ревью

Критических проблем с утечкой секретов или явным обходом premium gating не
найдено. `audio_url` для premium episodes гейтится на сервере через
`episodeToDTO`, entitlement берётся из серверного кэша, клиент не может сам
прислать `is_premium`.

Найденные риски:

1. `api/src/app.ts`: production error handler возвращает клиенту `err.message`.
   Это может раскрывать внутренние детали Prisma/парсинга/интеграций. Лучше
   логировать подробность только на сервере, а наружу отдавать общий
   `internal`.
2. `api/src/transistor/public-rss.ts` и `api/src/instagram/graph-client.ts`:
   внешние fetch-запросы для RSS/Graph API без явного timeout. Adapty уже
   защищён `AbortController`, а эти интеграции могут зависнуть и задержать
   cron/collector.
3. `npm audit` нашёл moderate advisory для `fast-xml-parser <5.7.0`
   (GHSA-gh4j-gqv2-49f6). Текущий код использует `XMLParser`, а advisory
   относится к `XMLBuilder`, поэтому прямой exploit path в текущем коде не
   виден, но зависимость стоит обновить планово.
4. iOS сейчас грузит по 200 episodes на фид и по 200 episodes на экран
   подкаста без cursor pagination в UI. Для текущего MVP это терпимо, но с
   ростом каталога будет лишняя сеть/память и медленный первый экран.
5. `DownloadService.fileKey` берёт первые 40 hex-символов от `episode.id`;
   для длинных id с одинаковым префиксом возможна коллизия локальных файлов.
   Нужен hash полного id (например SHA-256), если формат id когда-нибудь станет
   непредсказуемым.

## Проверки

- `npm audit --omit=dev --json` — выполнен, найден 1 moderate runtime advisory
  (`fast-xml-parser`).
- `npm test` и `npm run build` для `api/` — не прошли из-за отсутствующих
  локальных dev dependencies (`vitest`, `@types/node`). Попытка `npm ci`
  дважды упала с `npm error Exit handler never called`; локальная версия Node
  `v20.19.2`, а проект требует `>=22`.
- `xcodebuild -project LiboLibo.xcodeproj -scheme LiboLibo -sdk iphonesimulator
  -destination 'generic/platform=iOS Simulator' -configuration Debug
  -derivedDataPath /tmp/LiboLiboDerivedData build` — `BUILD SUCCEEDED` после
  запуска вне sandbox.
- Исходный ритуальный destination `name=iPhone 17` недоступен в текущей
  среде Xcode, поэтому использован generic iOS Simulator.

## Открытые вопросы

- Починить локальную Node-среду под `>=22`, после этого повторить `npm ci`,
  `npm test`, `npm run build`.
- Решить, обновляем ли `fast-xml-parser` сразу на major `5.x` или сначала
  фиксируем lockfile на безопасную совместимую версию, если такая появится.
- При следующей iOS/API-сессии добавить server/client pagination для фида и
  экрана подкаста.
