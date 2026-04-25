# Шаг 3 — Фаза B: media pipeline. План реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Скачивать медиа (картинки + mp4 + thumbnails для видео) на Railway volume и отдавать их по `/media/{postId}/{order}.{ext}` через `express.static`.

**Architecture:** Расширяем существующий cron-сервис `cron-refresh-instagram`: после `syncInstagramPosts()` запускаем `downloadPendingMedia()`, который для каждого поста без `InstagramMedia` записей запрашивает свежие `media_url` (они истекают за сутки), качает файлы на volume, через `ffprobe` достаёт width/height/duration, через `ffmpeg` генерирует thumbnail для видео, в одной транзакции создаёт записи `InstagramMedia`. Параллельно — Express-роут раздачи статики.

**Tech Stack:** Node.js 22, TypeScript ESM, Prisma, Postgres, vitest. **Новые зависимости:** `ffmpeg` (системная), `image-size` (npm). Volume — Railway-managed, монтируется в `/data/media`.

**Спека:** [step-03-instagram-feed.md](step-03-instagram-feed.md) разделы 4.4 и 4.7.

---

## Файловая карта

| Файл | Что | Статус |
|---|---|---|
| `api/Dockerfile` | + установка `ffmpeg` через apt | modify |
| `api/package.json` | + dep `image-size` | modify |
| `api/src/instagram/config.ts` | + `MEDIA_DIR` (по умолчанию `/data/media`) | modify |
| `api/src/instagram/media-probe.ts` | Чистые функции: парсинг ffprobe JSON, выбор расширения | create |
| `api/src/instagram/media-downloader.ts` | `downloadPendingMedia()` — главная функция | create |
| `api/src/instagram/refresh-cli.ts` | + после sync вызывать downloader | modify |
| `api/src/routes/media.ts` | `express.static(MEDIA_DIR)` под `/media` | create |
| `api/src/app.ts` | + `app.use("/media", mediaRouter)` | modify |
| `api/test/instagram-media-probe.test.ts` | Юнит-тесты на парсер ffprobe | create |

Файлы `instagram_media` создаются только когда файл реально лежит на диске — это инвариант, упрощающий логику (нет «частично записанных» постов).

---

## Task 1: ffmpeg в Dockerfile

**Files:**
- Modify: `api/Dockerfile`

- [ ] **Step 1.1:** Открыть `api/Dockerfile`. После `apt-get install` секции (или после `FROM node:22`, если apt-get там нет) добавить установку ffmpeg.

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*
```

- [ ] **Step 1.2:** Проверить локально, что Dockerfile валиден: `docker build api/` (если Docker установлен) или хотя бы `cat` чтобы убедиться, что синтаксис корректен. На Railway это будет применено при следующем deploy.

- [ ] **Step 1.3:** Коммит.

```bash
git add api/Dockerfile
git commit -m "Step 3.B1: install ffmpeg in api Docker image"
```

---

## Task 2: env config + image-size dep

**Files:**
- Modify: `api/src/instagram/config.ts`
- Modify: `api/package.json`

- [ ] **Step 2.1:** В `api/src/instagram/config.ts` экспортировать `getMediaDir()`:

```typescript
export function getMediaDir(): string {
  return process.env.MEDIA_DIR ?? "/data/media";
}
```

- [ ] **Step 2.2:** Добавить зависимость `image-size`. В `api/package.json` в `dependencies` добавить:

```json
"image-size": "^1.1.1"
```

И запустить `npm install` локально из `api/` (это обновит `package-lock.json`).

- [ ] **Step 2.3:** Коммит.

```bash
git add api/src/instagram/config.ts api/package.json api/package-lock.json
git commit -m "Step 3.B2: MEDIA_DIR env + image-size dep"
```

---

## Task 3: media-probe (TDD)

Чистые функции для разбора вывода `ffprobe` и выбора расширения файла.

**Files:**
- Create: `api/src/instagram/media-probe.ts`
- Test: `api/test/instagram-media-probe.test.ts`

- [ ] **Step 3.1: Написать тест.**

`api/test/instagram-media-probe.test.ts`:

```typescript
import { describe, it, expect } from "vitest";
import { parseFfprobeOutput, extensionFor } from "../src/instagram/media-probe.js";

describe("parseFfprobeOutput", () => {
  it("извлекает width/height/duration из видео-стрима", () => {
    const json = JSON.stringify({
      streams: [
        { codec_type: "audio", duration: "23.5" },
        { codec_type: "video", width: 1080, height: 1920, duration: "23.456" },
      ],
      format: { duration: "23.5" },
    });
    expect(parseFfprobeOutput(json)).toEqual({
      width: 1080,
      height: 1920,
      durationSec: 23,
    });
  });

  it("использует format.duration если у стрима его нет", () => {
    const json = JSON.stringify({
      streams: [{ codec_type: "video", width: 720, height: 1280 }],
      format: { duration: "12.9" },
    });
    expect(parseFfprobeOutput(json)).toEqual({ width: 720, height: 1280, durationSec: 13 });
  });

  it("кидает ошибку если video-стрима нет", () => {
    const json = JSON.stringify({ streams: [], format: {} });
    expect(() => parseFfprobeOutput(json)).toThrow(/no video stream/i);
  });
});

describe("extensionFor", () => {
  it("video → mp4", () => {
    expect(extensionFor("VIDEO")).toBe("mp4");
  });
  it("image → jpg", () => {
    expect(extensionFor("IMAGE")).toBe("jpg");
  });
});
```

- [ ] **Step 3.2: Запустить тесты — должны падать.**

```bash
cd api && npm test -- instagram-media-probe
```

Expected: FAIL — модуль не найден.

- [ ] **Step 3.3: Реализация.**

`api/src/instagram/media-probe.ts`:

```typescript
// Helpers for parsing ffprobe output and picking file extensions.
// Pure functions — no I/O, easy to unit-test.

export interface VideoMeta {
  width: number;
  height: number;
  durationSec: number;
}

interface RawProbe {
  streams?: Array<{
    codec_type?: string;
    width?: number;
    height?: number;
    duration?: string;
  }>;
  format?: { duration?: string };
}

export function parseFfprobeOutput(stdout: string): VideoMeta {
  const probe = JSON.parse(stdout) as RawProbe;
  const video = (probe.streams ?? []).find((s) => s.codec_type === "video");
  if (!video) throw new Error("ffprobe: no video stream");
  if (!video.width || !video.height) {
    throw new Error("ffprobe: video stream missing width/height");
  }
  const rawDuration = video.duration ?? probe.format?.duration ?? "0";
  const durationSec = Math.round(Number(rawDuration));
  return { width: video.width, height: video.height, durationSec };
}

export type IgMediaKind = "IMAGE" | "VIDEO";

export function extensionFor(kind: IgMediaKind): "jpg" | "mp4" {
  return kind === "VIDEO" ? "mp4" : "jpg";
}
```

- [ ] **Step 3.4: Тесты должны позеленеть.**

```bash
cd api && npm test -- instagram-media-probe
```

Expected: PASS, 5 тестов.

- [ ] **Step 3.5: Коммит.**

```bash
git add api/src/instagram/media-probe.ts api/test/instagram-media-probe.test.ts
git commit -m "Step 3.B3: media-probe pure helpers (ffprobe parser, extension picker)"
```

---

## Task 4: media-downloader

Главная функция: `downloadPendingMedia()` — для всех `InstagramPost`-ов без связанных `InstagramMedia` запрашивает детали через `fetchMediaDetails`, скачивает файлы, создаёт записи. Тестов на эту функцию не пишем (I/O-heavy), полагаемся на smoke.

**Files:**
- Create: `api/src/instagram/media-downloader.ts`

- [ ] **Step 4.1: Реализация.**

`api/src/instagram/media-downloader.ts`:

```typescript
// Скачивает картинки/видео для постов, у которых ещё нет записей в
// instagram_media, и создаёт эти записи в одной транзакции с реально
// скачанным файлом. Запускается из refresh-cli после syncInstagramPosts.

import { mkdir, writeFile, stat } from "node:fs/promises";
import { join, dirname } from "node:path";
import { spawn } from "node:child_process";
import { imageSize } from "image-size";

import { prisma } from "../db.js";
import { isConfigured, readConfig, getMediaDir } from "./config.js";
import { fetchMediaDetails, type IgChildMedia, type IgMediaDetails } from "./graph-client.js";
import { extensionFor, parseFfprobeOutput } from "./media-probe.js";

export interface DownloadSummary {
  postsScanned: number;
  postsCompleted: number;
  filesWritten: number;
  errors: Array<{ postId: string; error: string }>;
}

export async function downloadPendingMedia(): Promise<DownloadSummary> {
  if (!isConfigured()) {
    return { postsScanned: 0, postsCompleted: 0, filesWritten: 0, errors: [] };
  }
  const config = readConfig();
  const mediaDir = getMediaDir();

  // Берём все посты, у которых ещё нет связанных media-записей.
  const posts = await prisma.instagramPost.findMany({
    where: { media: { none: {} } },
    select: { id: true, igMediaId: true, type: true },
    orderBy: { igCreatedAt: "desc" },
    take: 50,
  });

  const summary: DownloadSummary = {
    postsScanned: posts.length,
    postsCompleted: 0,
    filesWritten: 0,
    errors: [],
  };

  for (const post of posts) {
    try {
      const details = await fetchMediaDetails(config, post.igMediaId);
      const items = expandToItems(post.type, details);
      const records: Array<Parameters<typeof prisma.instagramMedia.create>[0]["data"]> = [];

      for (let order = 0; order < items.length; order++) {
        const item = items[order]!;
        const written = await downloadOne(post.id, order, item, mediaDir);
        records.push({
          postId: post.id,
          order,
          kind: item.kind,
          filePath: written.filePath,
          thumbnailPath: written.thumbnailPath,
          width: written.width,
          height: written.height,
          durationSec: written.durationSec,
        });
        summary.filesWritten += 1;
      }

      await prisma.$transaction(records.map((data) => prisma.instagramMedia.create({ data })));
      summary.postsCompleted += 1;
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      summary.errors.push({ postId: post.id, error: msg });
    }
  }

  return summary;
}

interface Item {
  kind: "IMAGE" | "VIDEO";
  mediaUrl: string;
  thumbnailUrl: string | null;
}

function expandToItems(
  type: "IMAGE" | "CAROUSEL" | "VIDEO",
  details: IgMediaDetails,
): Item[] {
  if (type === "CAROUSEL") {
    return details.children
      .filter((c): c is IgChildMedia & { mediaUrl: string } => !!c.mediaUrl)
      .map((c) => ({
        kind: c.mediaType,
        mediaUrl: c.mediaUrl,
        thumbnailUrl: c.thumbnailUrl,
      }));
  }
  if (!details.mediaUrl) {
    throw new Error(`media_url is null for ${type} post ${details.id}`);
  }
  return [
    {
      kind: type === "VIDEO" ? "VIDEO" : "IMAGE",
      mediaUrl: details.mediaUrl,
      thumbnailUrl: details.thumbnailUrl,
    },
  ];
}

interface Written {
  filePath: string;
  thumbnailPath: string | null;
  width: number;
  height: number;
  durationSec: number | null;
}

async function downloadOne(
  postId: string,
  order: number,
  item: Item,
  mediaDir: string,
): Promise<Written> {
  const ext = extensionFor(item.kind);
  const relPath = `${postId}/${order}.${ext}`;
  const absPath = join(mediaDir, relPath);
  await mkdir(dirname(absPath), { recursive: true });

  await downloadToFile(item.mediaUrl, absPath);

  if (item.kind === "IMAGE") {
    const buf = await readFileBuf(absPath);
    const dims = imageSize(buf);
    return {
      filePath: relPath,
      thumbnailPath: null,
      width: dims.width ?? 0,
      height: dims.height ?? 0,
      durationSec: null,
    };
  }

  // VIDEO: ffprobe → размеры/длительность, ffmpeg → thumbnail.
  const probeStdout = await runCmd("ffprobe", [
    "-v", "error",
    "-print_format", "json",
    "-show_streams",
    "-show_format",
    absPath,
  ]);
  const meta = parseFfprobeOutput(probeStdout);

  const thumbRel = `${postId}/${order}.thumb.jpg`;
  const thumbAbs = join(mediaDir, thumbRel);
  await runCmd("ffmpeg", [
    "-y",
    "-ss", "0",
    "-i", absPath,
    "-frames:v", "1",
    "-q:v", "3",
    thumbAbs,
  ]);

  return {
    filePath: relPath,
    thumbnailPath: thumbRel,
    width: meta.width,
    height: meta.height,
    durationSec: meta.durationSec,
  };
}

async function downloadToFile(url: string, dest: string): Promise<void> {
  const resp = await fetch(url);
  if (!resp.ok) throw new Error(`download ${dest}: HTTP ${resp.status}`);
  const buf = Buffer.from(await resp.arrayBuffer());
  await writeFile(dest, buf);
}

async function readFileBuf(path: string): Promise<Buffer> {
  const { readFile } = await import("node:fs/promises");
  return readFile(path);
}

async function runCmd(cmd: string, args: string[]): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args);
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => (stdout += d.toString()));
    child.stderr.on("data", (d) => (stderr += d.toString()));
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) resolve(stdout);
      else reject(new Error(`${cmd} exit ${code}: ${stderr}`));
    });
  });
}
```

- [ ] **Step 4.2:** Type-check + тесты.

```bash
cd api && npx tsc -p tsconfig.json --noEmit && npm test
```

Expected: тихо + все существующие тесты зелёные.

- [ ] **Step 4.3: Коммит.**

```bash
git add api/src/instagram/media-downloader.ts
git commit -m "Step 3.B4: downloadPendingMedia (download + ffprobe + ffmpeg thumb)"
```

---

## Task 5: интеграция с refresh-cli

**Files:**
- Modify: `api/src/instagram/refresh-cli.ts`

- [ ] **Step 5.1:** В `refresh-cli.ts` после `syncInstagramPosts` вызывать `downloadPendingMedia`. Финальный JSON содержит обе суммы.

```typescript
import { syncInstagramPosts } from "./collector.js";
import { downloadPendingMedia } from "./media-downloader.js";

(async () => {
  const sync = await syncInstagramPosts();
  const download = await downloadPendingMedia();
  console.log(JSON.stringify({ sync, download }, null, 2));
  process.exit(0);
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

- [ ] **Step 5.2:** Коммит.

```bash
git add api/src/instagram/refresh-cli.ts
git commit -m "Step 3.B5: refresh-cli runs downloader after sync"
```

---

## Task 6: статик-роут /media

**Files:**
- Create: `api/src/routes/media.ts`
- Modify: `api/src/app.ts`

- [ ] **Step 6.1:** Создать `api/src/routes/media.ts`.

```typescript
import { Router } from "express";
import express from "express";
import { getMediaDir } from "../instagram/config.js";

export const mediaRouter = Router();

// `express.static` сам выставит правильный Content-Type (image/jpeg, video/mp4),
// 404 на ненайденный путь и 304 по If-Modified-Since.
mediaRouter.use(
  express.static(getMediaDir(), {
    maxAge: "1y",
    immutable: true,
    fallthrough: false,
  }),
);
```

- [ ] **Step 6.2:** В `api/src/app.ts` подмонтировать:

```typescript
import { mediaRouter } from "./routes/media.js";
// ...
app.use("/media", mediaRouter);
```

- [ ] **Step 6.3:** `npm run build && npm test`.

- [ ] **Step 6.4:** Коммит.

```bash
git add api/src/routes/media.ts api/src/app.ts
git commit -m "Step 3.B6: /media static route"
```

---

## Task 7: PR + Railway-конфигурация

**Файлы:** —

- [ ] **Step 7.1:** `git push -u origin step-3-phase-b` и открыть PR.

- [ ] **Step 7.2:** В Railway:
  1. На сервисе `LiboLibo` создать **Volume**: New → Volume → mount path `/data/media`. Размер — 5 GB на старт.
  2. На сервисе `cron-refresh-instagram` присоединить тот же Volume (mount path `/data/media`). Это нужно, чтобы downloader писал, а api читал из того же места.
  3. Добавить переменную `MEDIA_DIR=/data/media` в оба сервиса (или оставить дефолт `getMediaDir()`).
  4. После merge PR — Railway сам перебилдит образ (с `ffmpeg`) и применит volume.

- [ ] **Step 7.3:** Smoke на проде:
  - В Cron Service `cron-refresh-instagram` нажать **Run Now**.
  - В Logs ожидать JSON `{ sync: ..., download: { postsScanned: 30, postsCompleted: 30, filesWritten: ~60-90, ... } }`.
  - Проверить через `railway connect Postgres`: `SELECT count(*) FROM instagram_media;` → ~60-90.
  - Проверить раздачу: `curl -I https://<api-domain>/media/<some-uuid>/0.jpg` → `200 OK`, `Content-Type: image/jpeg`.

---

## Self-review

- [x] **Spec coverage.** Спека раздел 4.4 (downloader) → Tasks 1, 2, 4, 5. Раздел 4.7 (раздача) → Task 6. Volume → Task 7.
- [x] **Placeholder scan.** Нет TBD/TODO. Все код-блоки полные.
- [x] **Type consistency.** `IgMediaKind` определён в `media-probe.ts` как `"IMAGE" | "VIDEO"`, совпадает с типом в Prisma. `Item.kind` тоже `"IMAGE" | "VIDEO"`. `IgChildMedia.mediaType` (из graph-client) — то же самое.
- [x] **Идемпотентность.** `where: { media: { none: {} } }` гарантирует, что повторный запуск не качает уже скачанное.
