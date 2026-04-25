# Шаг 2.3 — Премиум-подписка через Adapty (без логина)

**Статус:** в разработке (ветка `phase-2.3-adapty-entitlement`).
**Зависит от:** фаза 2.0 (`step-02-backend.md`) — модель `Episode.isPremium`, контракт `audio_url: string | null`, `viewer.hasPremiumEntitlement` в `episodeToDTO`.

## Что делаем

1. Заводим понятие «entitlement» — состояние «у этого зрителя есть премиум».
2. Идентификатор зрителя — `adapty_profile_id` (UUID, генерится Adapty SDK на iOS, переживает переустановку через App Store receipt при `restorePurchases`). Логина нет.
3. iOS шлёт `X-Adapty-Profile-Id` во все запросы; бэкенд по этому заголовку решает, отдавать ли `audio_url` для премиум-эпизодов.
4. Источник истины — Adapty Server API. На бэке локальный кэш в таблице `entitlements`, **обновляется явно** ручкой `POST /v1/me/entitlement/refresh`. Эту ручку iOS дёргает после успешной покупки и после restore.

## Что НЕ делаем в этой фазе

- Sign in with Apple, аккаунты, `users` таблица.
- Webhook от Adapty (`subscription_renewed`, `expired`). Если кэш протух и юзер продлил подписку через App Store без захода в приложение — он узнает об этом при следующем старте, когда iOS дёрнет `refresh`. Webhook добавим, если понадобится (фаза 2.3.1).
- Server-to-server проверка App Store receipt напрямую (Adapty это берёт на себя).

## Контракт

### Заголовок `X-Adapty-Profile-Id`

- UUID v4. Без заголовка → анонимный зритель (`audio_url: null` для премиум-эпизодов).
- С заголовком → бэкенд читает строку из `entitlements` по `adapty_profile_id` и принимает решение.
- Если `entitlements` нет записи — анонимный зритель (но это значит, что iOS ещё не вызывал `/refresh` или у юзера и правда нет премиума).

### `POST /v1/me/entitlement/refresh`

**Запрос:**
```
POST /v1/me/entitlement/refresh
X-Adapty-Profile-Id: <uuid>
Content-Type: application/json
{}
```

**Ответ 200:**
```json
{
  "is_premium": true,
  "expires_at": "2027-04-25T12:00:00.000Z",
  "checked_at": "2026-04-25T20:31:04.512Z"
}
```

**Логика:**

1. Берём `profileId` из заголовка. Без него → 400 `missing_profile_id`.
2. Если `ADAPTY_SECRET_KEY` не задан → 503 `entitlement_unavailable` (на проде такого не должно быть).
3. Зовём Adapty Server API: `GET /server-side-api/v1/profile/{profile_id}` с заголовком `Authorization: Api-Key <SECRET>`.
4. В ответе ищем access level с именем `ADAPTY_PREMIUM_ACCESS_LEVEL` (default `premium`). Считаем активным, если `is_active === true` и (`expires_at` отсутствует ИЛИ в будущем).
5. Апсертим `Entitlement(adaptyProfileId, isPremium, expiresAt)`.
6. Возвращаем результат + `checked_at = now()`.

**Когда iOS зовёт:**

- Сразу после `Adapty.makePurchase` success.
- После `Adapty.restorePurchases` success.
- При `applicationDidBecomeActive`, если последний refresh был более часа назад (опционально — детали в iOS-сессии).

**Защита:** простой in-memory rate-limit (1 запрос в 5 секунд на `profileId`), чтобы клиент-баг не задудосил Adapty.

### `GET /v1/me/entitlement` (опционально, для дебага)

Возвращает текущее значение из таблицы `entitlements` без обращения к Adapty. Если записи нет — `is_premium: false, expires_at: null`. Полезно для юнит-проверки на iOS-стороне.

### Существующие ручки

`/v1/feed`, `/v1/podcasts/:id/episodes`, `/v1/episodes/:id` начинают читать `req.viewer.hasPremiumEntitlement` из middleware `resolveViewer` и пробрасывать в `episodeToDTO`. Контракт ответа не меняется: `audio_url: string | null` уже описан в OpenAPI с фазы 2.0 — теперь у поля просто появляется реальный путь к non-null значению для премиум-зрителя.

`/v1/podcasts` (без эпизодов) viewer не нужен.

## Схема БД

```prisma
model Entitlement {
  adaptyProfileId String    @id @map("adapty_profile_id")
  isPremium       Boolean   @default(false) @map("is_premium")
  expiresAt       DateTime? @map("expires_at")
  // На будущее: webhook или ручной refresh — будем знать, откуда узнали.
  source          String    @default("refresh") @map("source")
  createdAt       DateTime  @default(now()) @map("created_at")
  updatedAt       DateTime  @updatedAt @map("updated_at")

  @@map("entitlements")
}
```

Деплой: Railway по-прежнему делает `prisma db push --skip-generate` на старте (см. `railway.json`), миграционные файлы пока не чекинятся.

## Переменные окружения (Railway → web service)

| Переменная | Значение |
|---|---|
| `ADAPTY_SECRET_KEY` | Adapty Server API secret key (Profile → API Keys → Secret) |
| `ADAPTY_PREMIUM_ACCESS_LEVEL` | Имя access level в Adapty (default: `premium`) |
| `ADAPTY_API_BASE_URL` | Опц., default: `https://api.adapty.io/api/v1` |

## Безопасность

- `ADAPTY_SECRET_KEY` — только в Railway Variables, никогда в репо.
- iOS никогда не отправляет на бэк значение `is_premium` от себя — только `profile_id`.
- Бэк не доверяет клиенту: после `refresh` всегда заново читает Adapty.
- TTL кэша задаёт клиент (он решает, когда позвать `refresh`). На фазе 2.3 нет автоматического протухания на сервере — это ОК, потому что без webhook'а сервер всё равно не узнает об истечении подписки иначе как через явный refresh.

## План разработки

1. **Бэкенд (эта сессия):**
   - Prisma: модель `Entitlement`.
   - `lib/adapty.ts` — клиент Adapty Server API.
   - `middleware/viewer.ts` — резолв `X-Adapty-Profile-Id` → `req.viewer`.
   - Подключить middleware к `/feed`, `/podcasts/:id/episodes`, `/episodes/:id`, пробросить `req.viewer` в `episodeToDTO`.
   - `routes/me.ts` — `POST /me/entitlement/refresh` и `GET /me/entitlement`.
   - Тесты на чистые функции (`resolveEntitlementFromProfile`, `episodeToDTO` с премиум-viewer'ом).
   - Обновить `openapi.yaml`.

2. **iOS (следующая сессия, после получения ключей):**
   - SPM-зависимость Adapty.
   - `AdaptyService` (activate, observe profile, purchase, restore).
   - Заголовок `X-Adapty-Profile-Id` в `APIClient`.
   - Метка «премиум» в `EpisodeListItem`, тап на премиум → paywall.
   - Кнопка «Восстановить покупки» в `ProfileView`.

3. **Sandbox-проверка:**
   - Купить в sandbox → бэк отдаёт `audio_url` → плеер играет.
   - Restore на свежей установке.
   - Истечение sandbox-подписки → бэк перестаёт отдавать `audio_url` после следующего `refresh`.

## Открытые вопросы

- Точный путь `GET /profile/{id}` в Adapty Server API — сверить по их актуальной документации, когда придут ключи. Сейчас в коде он вынесен в константу с комментарием.
- Нужен ли webhook на старте? Пока решили — нет (см. «что не делаем»).
- Поведение скачанных премиум-эпизодов после истечения подписки — UX-вопрос для iOS-сессии.
