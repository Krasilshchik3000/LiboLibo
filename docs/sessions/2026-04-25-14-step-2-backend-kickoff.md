# 2026-04-25 — Шаг 2: стартовая сессия по бэкенду (сессия 8)

**Контекст:** Шаг 1 (iOS-каркас) закрыт — приложение тянет 44 RSS-фида Либо-Либо напрямую с Transistor, играет, помнит подписки и историю локально (см. [сессия 7](2026-04-25-07-step-1.4.md), [спека шага 1](../specs/step-01-ios-skeleton.md)). Теперь стартует параллельный трек — бэкенд Самата. На этой сессии договорились о стеке, инфраструктуре, объёме фазы 2.0.

**Участники:** Самат Галимов (backend), Claude.

## Что решили

### Стек бэкенда

| Слой | Выбор | Почему |
|---|---|---|
| Runtime | Node.js 22 + TypeScript | Стандарт; TS обязателен для Prisma |
| HTTP-фреймворк | Express | Зрелый, простой, всем знаком |
| ORM | Prisma | Запрошен явно; типы и миграции из коробки |
| БД | Postgres (Railway plugin) | Нативная интеграция, `DATABASE_URL` подставляется reference-переменной |
| Cron | Railway Cron Service | Отдельный сервис из того же Dockerfile, запускает CLI |
| Парсер RSS | fast-xml-parser | Самый адекватный pure-JS парсер |
| Тесты | vitest | По запросу |
| Логи | console.\* | На фазе 2.0 хватит; pino/Sentry — позже |
| Локалка | Docker Compose (Postgres + API) | Запуск в одну команду |

Зависимости рантайма: `express`, `@prisma/client`, `fast-xml-parser`. Dev: `typescript`, `tsx`, `prisma`, `vitest`, `@types/express`, `@types/node`. Больше ничего.

### Что бэкенд делает на фазе 2.0 (RAW)

Заменить 44 параллельных запроса с iOS к Transistor на один-два запроса к нашему API. Поведение приложения снаружи не меняется. Всё про премиум, push, оплаты, аккаунты, синк подписок — на следующих фазах.

Полный план фазы — в [`docs/specs/step-02-backend.md`](../specs/step-02-backend.md). Контракт API — в [`docs/specs/api/openapi.yaml`](../specs/api/openapi.yaml).

### Источник правды по контенту

Transistor остаётся источником правды, аудио продолжает раздавать он. Свой CDN не делаем. Бэкенд — про метаданные и контроль доступа.

### Premium на стороне Transistor

Премиум — на уровне эпизода. Чтобы наш бэкенд видел приватные эпизоды, нужен мастер-subscriber-token Transistor. Самат предоставит позже — до этого момента закладываем модель `is_premium` и поле в API, но реальное наполнение — отдельной маленькой подфазой 2.0.1, под фича-флагом.

### Аутентификация

На фазе 2.0 — анонимный `device_id` (UUID, выдаёт сервер при первой регистрации устройства). iOS хранит в Keychain. Полноценный логин (Sign in with Apple + email) — позже, вместе с оплатой картами.

### Что отложено

- Sign in with Apple, аккаунты, синк подписок и истории между устройствами.
- Push-уведомления (APNs).
- Apple IAP и интеграция с CloudPayments.
- Voice commentary (фича приложения, к бэкенду не относится).
- Аналитика прослушиваний — будет нужна, но не сейчас.
- Миграция пользователей из текущего Telegram-приложения — пока не думаем.
- Rate limiting — забиваем до первого инцидента.

## Конвенция по документации

В корень репо положили [`CLAUDE.md`](../../CLAUDE.md) — он фиксирует правило: каждая сессия завершается логом в `docs/sessions/`, спеки — в `docs/specs/`. AI-ассистенты подхватывают это автоматически; контрибьюторам тоже видно.

## Открытые вопросы

- Точный механизм премиум-фидов на стороне Transistor (один мастер-токен на студию или per-show) — выяснится после получения токена.
- Стратегия публикации в App Store, Apple Developer-аккаунт — на горизонте.

## Поправка по ходу сессии: платформа

Сначала закладывались на Vercel (serverless functions + Vercel Cron + Neon через marketplace). По ходу решили переехать на **Railway** — всегда-он Express проще, cron ставится отдельным сервисом из того же Dockerfile. Удалили `vercel.json`, `api/api/index.ts`, `routes/cron.ts`, переменную `CRON_SECRET`. Добавили `api/railway.json`. Всё остальное (стек, схема, эндпоинты, OpenAPI) — без изменений.

## Поправка по ходу сессии: премиум-эпизоды и секреты

Сначала премиум хотели включать отдельной подфазой 2.0.1, после получения «мастер-subscriber-token». По ходу решили реализовать сразу:

- В `.gitignore` усилили правило: `*.env` (плюс исключение `*.env.example`). Теперь `transistor.env` гарантированно не попадёт в коммит. Проверено `git check-ignore`.
- Добавлен файл `api/transistor.env.example` — шаблон с пустым `TRANSISTOR_API_KEY`. Реальный `transistor.env` Самат положит вручную; в сессии его содержимое не светится.
- `api/docker-compose.yml` подсасывает `transistor.env` через `env_file` с `required: false` — без файла всё работает, просто без премиум-эпизодов.
- В Postgres-схеме у `Podcast` появилось поле `transistor_show_id` — кэш show-id Transistor, резолвится один раз по `feed_url`.
- Новый клиент `src/transistor/api.ts` — тонкая обёртка над REST API Transistor, авторизация заголовком `x-api-key`, ключ берётся из `process.env`, нигде не логируется.
- `src/transistor/refresh.ts` теперь делает два прохода: публичный RSS (источник правды по «что считать публичным») + Transistor API (даёт всё включая subscriber-only). Эпизоды, которых нет в публичном RSS, помечаются `is_premium = true`.
- `src/lib/serialize.ts` получил `ViewerContext.hasPremiumEntitlement`. На фазе 2.0 он всегда `false` → метаданные премиум-эпизодов отдаются всем (тизер), но `audio_url` для них `null`. Когда на 2.3 появится Apple IAP, флаг будет приходить из проверки entitlements.

## Поправка по ходу сессии: pull последних изменений Ильи

К моменту завершения каркаса бэкенда на main прилетели сессии Ильи 1.5–1.10 (коммиты `b6f48b8..ea8916f`). Сделал `git pull --ff-only`, конфликтов не было. Из релевантного для бэкенда:

- В `Podcast` (Swift-модель) появились два новых поля: `description` (channel-level описание из RSS) и `lastEpisodeDate` (дата последнего выпуска — клиент по ней делит подкасты на «выходят сейчас / недавно / давно не выходят»).
- Скрипт `scripts/refresh-podcast-metadata.py` обогащает `docs/specs/podcasts-feeds.json` и `LiboLibo/Resources/podcasts.json` этими полями. Запускается раз в сутки/неделю.
- iOS-парсер `RSSParser.swift` теперь возвращает не только эпизоды, но и `PodcastChannelInfo.description`.

Чтобы бэкенд закрыл эту функциональность за клиента (после переключения iOS на API скрипт `refresh-podcast-metadata.py` станет ненужным), сделал:

1. В Prisma-схему `Podcast` добавил `lastEpisodeDate` (`last_episode_date` в БД).
2. Парсер `transistor/parser.ts` теперь возвращает `ParsedFeed = { channel: { description }, episodes }`. Channel-level description стрипает HTML — зеркально iOS-парсеру и Python-скрипту.
3. Воркер `transistor/refresh.ts` в новой функции `refreshPodcastMetadata`:
   - сохраняет `description` из RSS в `Podcast.description`, если RSS дал непустую (на 304 не затирает старое значение);
   - пересчитывает `lastEpisodeDate = max(pubDate)` по эпизодам подкаста;
   - выставляет `hasPremium = true`, если найден хоть один премиум-эпизод.
4. `serialize.ts` отдаёт `last_episode_date` в `PodcastDTO` (ISO-строка).
5. `seed.ts` забирает `lastEpisodeDate` из бандла при первичной инициализации — чтобы на холодном старте до первого refresh уже было что отдать.
6. OpenAPI-схема `Podcast` пополнилась полем `last_episode_date` (`format: date-time`, nullable).
7. Тест парсера расширен на проверку channel description.

Также переименовал лог этой сессии: `2026-04-25-08-step-2-backend-kickoff.md` → `2026-04-25-14-step-2-backend-kickoff.md`. Номер 08 занял Ильин лог 1.5; перенумеровал свой на следующий после его последнего (#13). Ссылка в `docs/specs/step-02-backend.md` обновлена.

## Что дальше

1. Каркас `api/` создан в этом репо (Express + Prisma + Docker Compose + сидинг 44 подкастов из `podcasts-feeds.json` + CLI обновления фидов).
2. Самат заводит Railway-проект, подключает Postgres-плагин, поднимает два сервиса (`api` и `cron-refresh`) — детали в [`api/README.md`](../../api/README.md).
3. Илья (отдельной сессией) переключает iOS-клиент на наш API за фича-флагом, удаляет `RSSParser.swift`.
