# Сессия 17 — аудит статуса фазы 2.0

**Дата:** 2026-04-25
**Участники:** Самат, Claude (Opus 4.7)
**Контекст:** Самат спросил про текущее состояние API хранения пользовательских данных и подписок, и где мы по дорожной карте шага 2. По ходу обнаружили, что `step-02-backend.md` и журнал сессий не отражают реальное состояние: фаза 2.0 в действительности закрыта (включая 2.0.1, Railway-деплой и переключение iOS на API), но в документации это не зафиксировано. Сессия — только документационная, код не трогали.

## Что проверили

### API пользовательских данных и подписок

- Пользовательских аккаунтов в API нет. Единственная «пользовательская» сущность — `Device` (`POST /v1/devices`, `PATCH /v1/devices/:id`), хранит `id` и `apns_token`. См. [api/src/routes/devices.ts](../../api/src/routes/devices.ts), Prisma-модель `Device` в [api/prisma/schema.prisma](../../api/prisma/schema.prisma).
- Подписки на подкасты и история прослушиваний по-прежнему живут в `UserDefaults` на iOS. Серверной синхронизации нет.
- Это соответствует плану: API учётных записей и синк подписок отложены на подфазу 2.1 (Sign in with Apple), Apple IAP — на 2.3.

### Фаза 2.0.1 (премиум через Transistor API) — закрыта

Реализована end-to-end:

- Клиент Transistor REST API: [api/src/transistor/api.ts](../../api/src/transistor/api.ts) — заголовок `x-api-key`, поиск шоу по `feed_url`, листинг всех опубликованных эпизодов. После коммита `b5656c5` шоу и эпизоды забираются батчем один раз на запуск, а не по одному на подкаст.
- Двухшаговый refresh: сначала публичный RSS, затем (если задан `TRANSISTOR_API_KEY`) — API Transistor; всё, чего нет в публичных guid'ах, апсертится с `is_premium = true`. См. [api/src/transistor/refresh.ts:65](../../api/src/transistor/refresh.ts) (`fetchPublicRSS`) и [api/src/transistor/refresh.ts:230](../../api/src/transistor/refresh.ts) (`syncPremiumViaAPI`).
- `Podcast.transistor_show_id` резолвится один раз и кэшируется.
- `hasPremium` на подкасте выставляется при наличии хотя бы одного премиум-эпизода.
- Сериализация: `audio_url` премиум-эпизода = `null`, пока `viewer.hasPremiumEntitlement = false` (на 2.0 это всегда false). См. [api/src/lib/serialize.ts:71](../../api/src/lib/serialize.ts). Гейт под IAP уже на месте, останется только включить флаг на фазе 2.3.
- На клиенте премиум-эпизод в ленте получает иконку замка и переход в детали (коммит `8da508e`).

### Состояние DoD фазы 2.0

| Пункт DoD | Статус | Источник |
|---|---|---|
| Премиум-эпизоды через Transistor API, `audio_url` = null без entitlement | Готово | refresh.ts, serialize.ts |
| vitest на парсере RSS | Готово | [api/test/parser.test.ts](../../api/test/parser.test.ts) |
| OpenAPI 0.1 в `docs/specs/api/openapi.yaml` | Готово | сверка контракта в сессии 15 |
| `Episode.audioUrl` стал `URL?` на iOS | Готово | [LiboLibo/Models/Episode.swift:15](../../LiboLibo/Models/Episode.swift) |
| `transistor.env` под `*.env` в `.gitignore`, секретов в репо нет | Готово | [.gitignore](../../.gitignore) |
| `docker compose up` поднимает Postgres + API локально | Готово | [api/docker-compose.yml](../../api/docker-compose.yml), [api/README.md](../../api/README.md) |
| Деплой на Railway: `api` и `cron-refresh`, Postgres подключён | Готово | коммит `9525ba3` (Railway deploy via CLI+GraphQL, cron-refresh, prod live) |
| Cron Service каждые 15 минут обновляет фиды | Готово | тот же коммит, расписание задано в Railway |
| iOS переключён на API: подкасты и эпизоды берутся с бэкенда | Готово | коммит `8201a3d` (Step 2.0: iOS switches from RSS to backend API) |

То есть фаза 2.0 полностью закрыта. Дальше по плану — фаза 2.1.

### Хвосты, которые остались в коде

В `LiboLibo/Services/` всё ещё лежат [RSSParser.swift](../../LiboLibo/Services/RSSParser.swift) и [PodcastsRepository.swift](../../LiboLibo/Services/PodcastsRepository.swift). Грепом по проекту видно, что ни один не используется (единственное вхождение `fetchFeed` снаружи — это `APIClient.fetchFeed`, обращение к нашему API, а не к RSS). Это мёртвый код, которого DoD требует удалить — лучше прибрать в отдельной короткой сессии, чтобы не путать читателя.

### Параллельный трек: шаг 3

В репо появились спеки [step-03-instagram-feed.md](../specs/step-03-instagram-feed.md) и [step-03-instagram-feed-plan-phase-a.md](../specs/step-03-instagram-feed-plan-phase-a.md) — отдельная фича (модерируемая лента-зеркало Instagram). Это самостоятельный трек, дорожную карту шага 2 не сдвигает.

## Что обновили в документации

1. Создан этот лог.
2. В [step-02-backend.md](../specs/step-02-backend.md) добавлен раздел «Статус фазы 2.0 (на 2026-04-25)» с разбивкой по DoD-пунктам и пометкой, что фаза закрыта.

## Открытые вопросы

— Когда удаляем мёртвый `RSSParser` / `PodcastsRepository`? Это мелкая чистка на одну сессию iOS.

## Следующий шаг

— Стартовать фазу 2.1: Sign in with Apple, аккаунты, серверный синк подписок и истории. Здесь впервые появятся настоящие API пользователя и подписок.
