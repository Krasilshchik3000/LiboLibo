# Шаг 3 — Фаза C: модерация-админка + публичный API. План

> **Goal:** редактор может зайти в `/admin`, проставить CTA каждому `PENDING` посту и опубликовать. Опубликованные посты отдаются по `GET /v1/feed/instagram?cursor=&limit=` для iOS-клиента.

## Файлы

- Create: `api/src/admin/auth.ts` — HTTP Basic Auth middleware (env: `ADMIN_USER`, `ADMIN_PASSWORD`).
- Create: `api/src/admin/router.ts` — Express-роутер: `GET /`, `GET /posts`, `GET /posts/:id`, `POST /posts/:id`.
- Create: `api/src/admin/views/layout.ejs`, `list.ejs`, `detail.ejs` — server-rendered HTML.
- Create: `api/src/lib/instagram-feed-serialize.ts` — чистая функция превращает `InstagramPost + media + episode + podcast` в DTO для iOS.
- Create: `api/src/routes/feed-instagram.ts` — `GET /v1/feed/instagram` с курсором по `(publishedAt desc, id)`.
- Create: `api/test/instagram-feed-serialize.test.ts` — тесты на сериализатор.
- Modify: `api/src/app.ts` — монтирует `/admin` и `/v1`.
- Modify: `api/package.json` — `ejs`, `basic-auth` (уже добавлено).

## Архитектура форм

`POST /admin/posts/:id` принимает `application/x-www-form-urlencoded`:

| Поле | Допустимые значения |
|---|---|
| `action` | `publish` / `hide` / `save_draft` |
| `cta_type` | `none` / `episode` / `podcast` / `link` |
| `cta_episode_id` | string (UUID-ish; для `episode`) |
| `cta_podcast_id` | string (BigInt; для `podcast`) |
| `cta_url` | URL (для `link`) |
| `cta_label` | свободный текст ≤ 80 |

Валидация:
- При `action=publish` для CTA-варианта обязательны соответствующие поля.
- При `cta_type=none` пост допускается публиковать без CTA.

## Курсорная пагинация публичного API

Курсор кодирует `(publishedAt-iso, id-uuid)` через `Buffer.from(...).toString('base64url')`. Существующий `lib/cursor.ts` шаблон используется как референс.

## Self-review

- Spec coverage: спека разделы 4.5 (admin) и 4.6 (public API).
- Все маршруты статусом `PUBLISHED` — фильтр на стороне API.
- Token/password не в логах: Basic Auth middleware читает `process.env.*`, не печатает.
