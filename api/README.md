# libolibo-api

Бэкенд приложения «Либо-Либо», фаза 2.0.
Полная спека — [`docs/specs/step-02-backend.md`](../docs/specs/step-02-backend.md).
Контракт API — [`docs/specs/api/openapi.yaml`](../docs/specs/api/openapi.yaml).

## Секреты

Чувствительные значения никогда не попадают в репо — `*.env` в `.gitignore`.

| Файл | Что внутри | Когда нужен |
|---|---|---|
| `api/.env` (необязательный) | `DATABASE_URL`, `PORT` | Только если запускаешь без Docker |
| `api/transistor.env` | `TRANSISTOR_API_KEY` | Чтобы тянуть премиум-эпизоды через API Transistor |

Шаблоны без значений: `.env.example`, `transistor.env.example`. На Railway эти переменные ставятся в Variables сервиса, файлы туда не нужны.

Без `transistor.env` API запустится, но будет видеть только публичные эпизоды (приватные не подтянутся, `is_premium` останется `false`).

## Запуск локально (Docker)

Нужен установленный Docker.

```bash
cd api
docker compose up --build
```

Если у тебя есть API-ключ Transistor — положи его в `api/transistor.env` (формат — в `transistor.env.example`). Docker Compose подхватит файл автоматически. Без файла всё работает, просто без премиум-эпизодов.

При первом запуске Docker сам синхронизирует схему БД (`prisma db push`) и поднимет API на `http://localhost:3000`.

> На фазе 2.0 используется `db push` — без файлов миграций. Когда схема стабилизируется — заменим на чекинутые миграции и `migrate deploy`.

В отдельном терминале — сидинг 44 подкастов из `docs/specs/podcasts-feeds.json` и одноразовый прогон фидов:

```bash
docker compose exec api npm run seed
docker compose exec api npm run refresh
```

Проверка:

```bash
curl http://localhost:3000/v1/health        | jq .
curl http://localhost:3000/v1/podcasts      | jq '.items | length'
curl http://localhost:3000/v1/feed?limit=5  | jq .
```

Остановить и удалить тома:

```bash
docker compose down -v
```

## Запуск без Docker

```bash
cd api
cp .env.example .env
# поправь DATABASE_URL под свой Postgres
npm install
npx prisma db push --skip-generate
npm run seed
npm run dev
```

## Тесты

```bash
docker compose exec api npm test
# или локально
npm test
```

## Деплой на Railway

Бэкенд состоит из **двух Railway-сервисов** в одном проекте, оба собираются из этого репо и используют один Dockerfile:

1. **`api`** — всегда работающий веб-сервер (Express). Конфиг — [`railway.json`](railway.json).
2. **`cron-refresh`** — Railway Cron Service, запускается каждые 15 минут, гоняет `npm run refresh`. Создаётся отдельно через UI Railway (см. шаги ниже).

### Шаги (одноразово)

1. На Railway создай проект, привяжи к этому GitHub-репо. Root Directory: `api`.
2. Добавь плагин **Postgres** (New → Database → Postgres). Railway создаст переменную `DATABASE_URL` в проекте.
3. На сервисе `api` в Variables добавь:
   - `DATABASE_URL` = `${{Postgres.DATABASE_URL}}` (reference variable).
   - `TRANSISTOR_TOKEN` — пустой пока (заполним на фазе 2.0.1).
4. Railway сам подхватит `railway.json`: `preDeployCommand` синкает схему БД, `startCommand` запускает сервер. После первого деплоя проверь `https://<service>.up.railway.app/v1/health`.
5. Одноразово прогони сидинг — через Railway CLI:
   ```bash
   railway link        # выбери проект и сервис api
   railway run npm run seed
   ```
6. Создай **второй сервис** в том же проекте: New → GitHub Repo → этот же репо.
   - Root Directory: `api`.
   - Settings → Deploy → Start Command: `npm run refresh`.
   - Settings → Deploy → Cron Schedule: `*/15 * * * *`.
   - Variables: `DATABASE_URL` = `${{Postgres.DATABASE_URL}}` (та же).
   - Healthcheck оставь пустым — это cron-сервис, он не должен слушать порт.

После этого фид сам обновляется каждые 15 минут.

### Ручной триггер обновления

Через Railway CLI:

```bash
railway run --service cron-refresh npm run refresh
```

Или через UI: Cron Service → "Run Now".

## Структура

```
src/
  app.ts             # Express-приложение
  server.ts          # entrypoint (используется и локально, и на Railway)
  db.ts              # один PrismaClient
  routes/            # health, podcasts, feed, episodes, devices
  transistor/        # парсер RSS, воркер обновления, CLI для cron-сервиса
  lib/               # cursor pagination, async wrapper, serialization, seed
prisma/schema.prisma # модели БД
test/                # vitest
railway.json         # конфиг web-сервиса для Railway
Dockerfile           # один на оба сервиса (web и cron)
docker-compose.yml   # локальный dev (Postgres + API)
```

## Что считается «готово» (DoD фазы 2.0)

См. [`docs/specs/step-02-backend.md`](../docs/specs/step-02-backend.md#definition-of-done-фазы-20).
