# 2026-04-25-22 — Adapty entitlement: бэкенд (фаза 2.3, ветка)

**Ветка:** `phase-2.3-adapty-entitlement` (не запушена, не смерджена).
**Спека:** [`docs/specs/step-2.3-premium-adapty.md`](../specs/step-2.3-premium-adapty.md).

## Контекст

Пользователь хочет запустить премиум-подписки. Без логина — идентификатор зрителя только `adapty_profile_id`. Бэк проверяет entitlement по этому id, отдаёт `audio_url` для премиум-эпизодов только подписчикам. После успешной покупки/restore iOS явно дёргает бэк, чтобы тот сходил в Adapty Server API и обновил кэш.

Решено делать всё в отдельной ветке. Ключи Adapty / App Store пользователь даст позже — пока делаем то, что можно без них (вся серверная инфра).

## Что сделали (только бэкенд)

### Документация
- `docs/specs/step-2.3-premium-adapty.md` — спека фазы. Контракт ручки, схема, env-переменные, план iOS-стороны и sandbox-проверки.

### Схема БД
- Новая модель `Entitlement` в [prisma/schema.prisma](../../api/prisma/schema.prisma): `adapty_profile_id` (id), `is_premium`, `expires_at`, `source`, timestamps. На Railway применится при следующем `prisma db push --skip-generate` (он же `preDeployCommand`).

### Код
- [`api/src/lib/adapty.ts`](../../api/src/lib/adapty.ts) — клиент Adapty Server API: `fetchProfile`, чистая `resolveEntitlementFromProfile` (легко тестируется), error-классы `AdaptyConfigError`/`AdaptyApiError`, таймаут 5с.
- [`api/src/middleware/viewer.ts`](../../api/src/middleware/viewer.ts) — middleware читает `X-Adapty-Profile-Id` (валидация UUID), смотрит локальный кэш `Entitlement`, кладёт `req.viewer = { hasPremiumEntitlement: bool }`. **В Adapty не ходит** — только в БД.
- [`api/src/routes/me.ts`](../../api/src/routes/me.ts) — `POST /v1/me/entitlement/refresh` (идёт в Adapty, апсертит `Entitlement`, отвечает свежим состоянием) и `GET /v1/me/entitlement` (быстрый снимок из кэша). Ratelimit 1 запрос / 5 секунд на профиль (in-memory).
- Подключили `resolveViewer` к `/v1/feed`, `/v1/podcasts/:id/episodes`, `/v1/episodes/:id` и пробросили `req.viewer` в `episodeToDTO`. На `/v1/podcasts` (без эпизодов) middleware не нужен.
- [`api/src/app.ts`](../../api/src/app.ts) — подключён `meRouter`.

### Тесты
- `api/test/adapty.test.ts` — 6 кейсов на `resolveEntitlementFromProfile` (active/lifetime/expired/inactive/empty/custom-level).
- `api/test/serialize.test.ts` — гарантирует, что `episodeToDTO` правильно гейтит `audio_url` по `viewer.hasPremiumEntitlement`.
- Все тесты зелёные (13/13), `tsc --noEmit` чистый.

### OpenAPI
- `docs/specs/api/openapi.yaml` — новые ручки `/me/entitlement` и `/me/entitlement/refresh`, параметр `X-Adapty-Profile-Id` подвешен ко всем ручкам, где он влияет на ответ.

## Что не делали и почему

- **Webhook от Adapty.** Решили — не на старте. Пока единственный путь обновить статус — клиентский `POST /refresh`. Если будет нужно — фаза 2.3.1.
- **Интеграционные тесты** на роуты с реальной БД. У проекта пока тестируются чистые функции; добавление test-DB — отдельная инфраструктурная задача.
- **iOS-сторона.** Adapty SDK, paywall, кнопка Restore, метка «премиум» в ленте. Делаем следующей сессией, когда придут ключи (`ADAPTY_PUBLIC_SDK_KEY`, продукты в Adapty/App Store Connect).
- **Не пушили ветку.** Без переменной `ADAPTY_SECRET_KEY` на Railway ручка `/refresh` будет возвращать 503; всё остальное работает как раньше (anon viewer = текущее поведение). Деплоить можно безопасно, но решили подождать.

## Что нужно от пользователя

Чтобы закончить фазу 2.3 (iOS + sandbox), нужны:
1. **Adapty Secret API Key** → Railway Variables: `ADAPTY_SECRET_KEY`.
2. **Adapty Public SDK Key** (для iOS).
3. **Имя access level** в Adapty (если не `premium` — в Railway Variables: `ADAPTY_PREMIUM_ACCESS_LEVEL`).
4. **Продукты** в App Store Connect (Subscription Group, цены) и в Adapty (paywall + placement).
5. **Sandbox-тестер** в App Store Connect для отладки.

## Открытые вопросы

- Точный путь `GET /profile/{id}` Adapty Server API (`/api/v1/server-side-api/profile/{id}`) сверить по их актуальной документации после получения ключа. Сейчас вынесено в константу + переменную `ADAPTY_API_BASE_URL`.
- UX скачанных премиум-эпизодов после истечения подписки — обсудить перед iOS-сессией.
- Опц. webhook на `subscription_renewed/expired` — оценить после первой недели в проде.

## Деплой на main

Пользователь дал ключи Adapty (`subs.env`, не в репо) — проставил `ADAPTY_SECRET_KEY` в Railway Variables сервиса `LiboLibo` (production) через `railway variable set`. Access level — `premium` (default), отдельная переменная не нужна.

Ветка смерджена в `main` — Railway запустит `prisma db push --skip-generate` на старте, добавит таблицу `entitlements`, и ручки `/v1/me/entitlement` и `/v1/me/entitlement/refresh` станут доступны на проде. Поведение для существующих клиентов не меняется: без заголовка `X-Adapty-Profile-Id` viewer остаётся анонимным, `audio_url: null` для премиум-эпизодов как и раньше.

## Следующий шаг

iOS-сессия: SPM-зависимость Adapty, `AdaptyService` (activate с public-ключом из `subs.env`, observe profile, purchase, restore), заголовок `X-Adapty-Profile-Id` в `APIClient`, paywall (AdaptyUI), кнопка Restore в `ProfileView`, метка «премиум» в `EpisodeListItem`.
