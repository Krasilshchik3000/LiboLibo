# Spec: Шаг 2 — бэкенд

**Базовое решение:** [docs/sessions/2026-04-25-14-step-2-backend-kickoff.md](../sessions/2026-04-25-14-step-2-backend-kickoff.md).
**Owner:** Самат, Claude.

## Цель шага 2

Поднять минимальный, работающий бэкенд, который полностью обслуживает текущее iOS-приложение: каталог подкастов и лента эпизодов отдаются с нашего API, а не парсятся клиентом. Поведение приложения снаружи не меняется.

После переезда iOS перестаёт ходить в Transistor напрямую: `RSSParser` и `PodcastsRepository.fetchFeed` удаляются, экран подкаста берёт описание только из `/v1/podcasts/:id`. Список подкастов из бандла (`podcasts.json`) остаётся как фолбэк на первый запуск без сети, но единственный авторитетный источник — API.

Подписки и история на фазе 2.0 продолжают жить в `UserDefaults` на устройстве — синк через бэкенд приедет на 2.1 вместе с Sign in with Apple. Поиск тоже остаётся клиентским (фильтрация уже подгруженных `/v1/podcasts` и `/v1/feed`); серверный `/v1/search` отложен и в фазу 2.0 не входит.

Шаг 2 разбит на подфазы. На этой странице — план фазы **2.0** (RAW: метаданные подкастов и эпизодов через наш API). Остальные подфазы перечислены в конце.

## Стек

| Слой | Выбор |
|---|---|
| Runtime | Node.js 22, TypeScript, ESM |
| HTTP | Express |
| ORM | Prisma |
| БД | Postgres (Railway Postgres plugin; локально — официальный образ Postgres 16) |
| Cron | Railway Cron Service (отдельный сервис, тот же Dockerfile, `npm run refresh`) |
| Парсер RSS | fast-xml-parser |
| Тесты | vitest |
| Локалка | Docker Compose |
| Деплой | Railway (один проект, два сервиса: `api` и `cron-refresh`) |

Рантайм-зависимости: `express`, `@prisma/client`, `fast-xml-parser`. Dev: `typescript`, `tsx`, `prisma`, `vitest`, `@types/express`, `@types/node`.

## Структура каталога `api/`

```
api/
  src/
    server.ts                  # точка входа для node/Docker
    app.ts                     # сборка Express-приложения
    db.ts                      # один PrismaClient
    routes/
      podcasts.ts
      feed.ts
      episodes.ts
      devices.ts
    transistor/
      parser.ts                # XML → нормализованные модели
      refresh.ts               # обход всех публичных фидов
      refresh-cli.ts           # entrypoint для Railway Cron Service
    lib/
      asyncHandler.ts          # обёртка для async-роутов Express
      seed.ts                  # сидинг подкастов из docs/specs/podcasts-feeds.json
  prisma/
    schema.prisma
  test/
    parser.test.ts             # vitest для RSS-парсера
  Dockerfile
  docker-compose.yml
  railway.json                 # конфиг web-сервиса для Railway
  package.json
  tsconfig.json
  .env.example
  .dockerignore
  README.md
```

## Схема БД (Prisma)

```prisma
model Podcast {
  id                BigInt    @id                       // iTunes id из podcasts-feeds.json
  name              String
  artist            String?
  feedUrl           String    @unique @map("feed_url")
  artworkUrl        String?   @map("artwork_url")
  description       String?                              // channel-level description из RSS
  genres            String[]
  hasPremium        Boolean   @default(false) @map("has_premium")
  lastEpisodeDate   DateTime? @map("last_episode_date")  // денормализовано: max(pubDate) по эпизодам
  transistorShowId  String?   @unique @map("transistor_show_id")
  updatedAt         DateTime  @updatedAt @map("updated_at")
  createdAt         DateTime  @default(now()) @map("created_at")
  episodes          Episode[]
  feedFetch         FeedFetch?
  @@map("podcasts")
}

model Episode {
  id           String   @id                       // RSS guid
  podcastId    BigInt   @map("podcast_id")
  podcast      Podcast  @relation(fields: [podcastId], references: [id], onDelete: Cascade)
  title        String
  summary      String?
  pubDate      DateTime @map("pub_date")
  durationSec  Int?     @map("duration_sec")
  audioUrl     String   @map("audio_url")
  isPremium    Boolean  @default(false) @map("is_premium")
  createdAt    DateTime @default(now()) @map("created_at")
  updatedAt    DateTime @updatedAt @map("updated_at")
  @@index([podcastId, pubDate(sort: Desc)])
  @@index([pubDate(sort: Desc)])
  @@map("episodes")
}

model FeedFetch {
  podcastId    BigInt   @id @map("podcast_id")
  podcast      Podcast  @relation(fields: [podcastId], references: [id], onDelete: Cascade)
  etag         String?
  lastModified String?  @map("last_modified")
  lastOkAt     DateTime? @map("last_ok_at")
  lastError    String?  @map("last_error")
  @@map("feed_fetches")
}

model Device {
  id           String   @id @default(uuid()) @db.Uuid
  apnsToken    String?  @map("apns_token")
  createdAt    DateTime @default(now()) @map("created_at")
  lastSeenAt   DateTime @default(now()) @map("last_seen_at")
  @@map("devices")
}
```

## Эндпоинты фазы 2.0

| Метод | Путь | Описание |
|---|---|---|
| `GET` | `/v1/health` | Liveness / readiness. Возвращает `{ ok: true, db: true }` |
| `POST` | `/v1/devices` | Регистрирует устройство, возвращает `{ device_id }`. iOS сохраняет в Keychain |
| `PATCH` | `/v1/devices/:id` | Обновляет `apns_token` и/или `last_seen_at` |
| `GET` | `/v1/podcasts` | Список 44 подкастов |
| `GET` | `/v1/podcasts/:id` | Деталь подкаста |
| `GET` | `/v1/podcasts/:id/episodes?limit=50&cursor=...` | Эпизоды одного подкаста, курсорная пагинация по `pubDate desc` |
| `GET` | `/v1/feed?limit=50&cursor=...` | Глобальная лента всех 44 подкастов, отсортированная по `pubDate desc` |
| `GET` | `/v1/episodes/:id` | Деталь эпизода |

Обновление фидов — отдельный Railway Cron Service (см. ниже), HTTP-эндпоинта для cron нет.

Подробный контракт — в [`docs/specs/api/openapi.yaml`](api/openapi.yaml).

### Премиум

Премиум-эпизоды живут на стороне Transistor — они не попадают в публичный RSS, но видны через Transistor API под мастер-API-ключом издателя.

**Источник ключа.** API-ключ хранится только в `api/transistor.env` (локально) и в Railway Variables (прод). Файл занесён в `.gitignore` правилом `*.env` — закоммитить случайно не получится. Шаблон без значения — `api/transistor.env.example`. На клиент ключ никогда не уезжает.

**Алгоритм обновления.** В `transistor/refresh.ts` для каждого подкаста:

1. Тянется публичный RSS — это источник правды по тому, что считается публичным.
2. Если `TRANSISTOR_API_KEY` задан, через REST API Transistor (`x-api-key`) подгружаются ВСЕ эпизоды шоу (включая subscriber-only).
3. Эпизод, которого нет в публичном RSS, помечается `is_premium = true`.
4. У подкаста, в котором обнаружен хотя бы один такой эпизод, выставляется `has_premium = true`.

`Podcast.transistor_show_id` резолвится один раз при первом обходе (по совпадению `feed_url`) и кэшируется в БД.

**Что отдаёт API клиенту.** Метаданные премиум-эпизода (название, описание, дата, длительность, обложка подкаста) видны всем — это тизер, чтобы бесплатные пользователи захотели купить. Поле `audio_url` присутствует, но для премиум-эпизодов оно `null` — пока у запрашивающего устройства нет активного entitlement. Логика проверки entitlement встроена в `serialize.ts` через `ViewerContext.hasPremiumEntitlement` — на фазе 2.0 этот флаг всегда `false` (никто ещё не платит); включится на фазе 2.3 после Apple IAP.

**Контракт по типам.** `Podcast.artist` и `Episode.summary` всегда присутствуют как строка (если в RSS пусто — отдаём `""`), чтобы iOS-модели оставались с non-optional полями. `Episode.audio_url` обязательное, но nullable: для премиум-эпизодов без entitlement приходит `null` — клиентская модель `Episode.audioUrl` поэтому становится `URL?`, а в UI плеера/строки рисуется тизер «доступно по подписке».

## Воркер обновления фидов

Отдельный Railway-сервис `cron-refresh` собирается из того же Dockerfile, но запускает CLI `npm run refresh` (под капотом — `src/transistor/refresh-cli.ts`). Расписание `*/15 * * * *` задаётся в Railway UI на этом сервисе. Логика:

1. Берёт все 44 подкаста из БД (после первого сидинга).
2. Параллельно (concurrency = 8) делает `GET feedUrl` с заголовками `If-None-Match` / `If-Modified-Since` из `feed_fetches`.
3. На 304 — обновляет `last_ok_at`.
4. На 200 — парсит XML, идемпотентно апсертит эпизоды по `guid`, обновляет `etag` / `last_modified`.
5. На ошибку — пишет `last_error`, не падает остальной обход.

Тот же CLI можно запустить вручную: `railway run --service cron-refresh npm run refresh`, или локально `docker compose exec api npm run refresh`.

Сидинг подкастов — отдельный скрипт `seed.ts`, читает `docs/specs/podcasts-feeds.json` и наполняет таблицу `podcasts`. Запускается вручную при первом развёртывании; cron работает только когда подкасты уже есть.

## Локальный запуск

```bash
cd api
cp .env.example .env
docker compose up --build
# в другом терминале — сидинг и одноразовое обновление фидов
docker compose exec api npm run seed
docker compose exec api npm run refresh
curl http://localhost:3000/v1/feed | jq .
```

Hot reload — через `tsx watch` (см. скрипт `dev`).

## Развёртывание на Railway (что делает Самат)

Один Railway-проект, два сервиса из этого репо + плагин Postgres.

1. Создаёт Railway-проект, подключает GitHub-репо. Root Directory всех сервисов — `api`.
2. Добавляет плагин **Postgres** (New → Database → Postgres). Railway генерит `DATABASE_URL`.
3. **Сервис `api`** (web): подхватывает [`api/railway.json`](../../api/railway.json), `preDeployCommand` синкает схему, `startCommand` запускает Express. Variables: `DATABASE_URL = ${{Postgres.DATABASE_URL}}`. Появится домен `*.up.railway.app`.
4. **Сервис `cron-refresh`** (Railway Cron Service): создаётся отдельно из того же репо. Settings → Deploy → Start Command: `npm run refresh`. Settings → Deploy → Cron Schedule: `*/15 * * * *`. Variables: `DATABASE_URL = ${{Postgres.DATABASE_URL}}`. Healthcheck отключён.
5. Одноразово (после первого деплоя): `railway link && railway run npm run seed` — наполняет таблицу `podcasts`.
6. На фазе 2.0.1 в обоих сервисах добавится `TRANSISTOR_TOKEN`.

## Definition of Done фазы 2.0

- `docker compose up` поднимает Postgres + API локально, схема синкается, сидинг наполняет 44 подкаста, `curl /v1/feed` возвращает реальные эпизоды.
- При наличии `transistor.env` с валидным `TRANSISTOR_API_KEY` бэкенд подтягивает приватные эпизоды через Transistor API, помечает их `is_premium = true`, отдаёт тизеры всем; `audio_url` премиум-эпизодов — `null` (entitlement-логика появится на 2.3).
- На Railway задеплоены оба сервиса под временным доменом `*.up.railway.app`, Postgres подключён.
- Cron Service каждые 15 минут обновляет фиды, ошибки видны в Railway Logs.
- vitest проходит на парсере RSS (минимум один зелёный тест).
- OpenAPI 0.1 в `docs/specs/api/openapi.yaml` соответствует реальному API.
- iOS-приложение переключено на API: `RSSParser`, `PodcastsRepository.fetchFeed` и прямые походы в `feedUrl` удалены; `Episode.audioUrl` стал `URL?`, плеер и строки эпизодов корректно показывают премиум-тизер при `null`.
- Никаких секретов в репозитории. `transistor.env` покрыт `*.env` в `.gitignore`.

## Дальнейшие подфазы (после 2.0)

| Подфаза | Содержание |
|---|---|
| 2.0.1 | (закрыто внутри 2.0) Премиум-эпизоды через Transistor API: бэкенд тянет приватные эпизоды, помечает `is_premium`, отдаёт тизеры. |
| 2.1 | Sign in with Apple, аккаунты, синк подписок и истории через API. |
| 2.2 | Push-уведомления о новых эпизодах (APNs напрямую). |
| 2.3 | Apple IAP, entitlements, защита `audio_url` премиум-эпизодов. |
| 2.4 | CloudPayments для веб-оплаты (если будет веб). |
| 2.5 | Аналитика прослушиваний. |
| 2.6 | Админка (тонкая, на Next.js, в этом же репо). |

Каждая подфаза = отдельная сессия + отдельная спека или дополнение к этой.
