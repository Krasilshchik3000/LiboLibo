# Voice Comments Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the backend that lets premium users post short voice comments to episodes (audio file + transcript + timecode), and lets all users read & listen to those comments. Independently deployable; iOS plan follows in a separate doc.

**Architecture:** Add `User` and `Comment` Prisma models keyed off `adapty_profile_id` (no separate auth — same identity as `entitlements`). Audio files persist on a Railway Volume mounted at `/data`, served by Express with strong cache headers. New `requirePremium` middleware extends the existing `resolveViewer`. Bird names come from a hardcoded ru-language pool, picked deterministically from a SHA-256 hash of `adapty_profile_id`, with `-2`/`-3` suffix on UNIQUE collision. Schema sync follows the project's existing convention of `prisma db push` (not migration files).

**Tech Stack:** Node.js 22, TypeScript, Express 4, Prisma 5, Postgres 16, Vitest 4, multer (new dep), Railway (deploy + Volume mount).

**Spec:** [`docs/specs/step-04-voice-comments.md`](step-04-voice-comments.md)

---

## File Structure

**New files:**
- `api/src/lib/birdNames.ts` — pool of 1000+ Russian bird names + `pickBirdName(profileId)` helper.
- `api/src/lib/audioStorage.ts` — `saveCommentAudio(buffer)`, `deleteCommentAudio(path)`, `streamCommentAudio(path, res)`. Touches the Volume mount.
- `api/src/lib/audioMime.ts` — MIME sniffing from file magic bytes (don't trust client-supplied `Content-Type`).
- `api/src/middleware/requirePremium.ts` — gate POST/DELETE on `req.viewer.hasPremiumEntitlement`.
- `api/src/routes/comments.ts` — list, post, delete, stream-audio handlers.
- `api/test/birdNames.test.ts`, `api/test/audioStorage.test.ts`, `api/test/audioMime.test.ts`, `api/test/requirePremium.test.ts` — unit tests.

**Modified files:**
- `api/prisma/schema.prisma` — add `User`, `Comment` models; add `comments Comment[]` relation on `Episode`.
- `api/src/app.ts` — register `commentsRouter` under `/v1`.
- `api/package.json` — add `multer` and `@types/multer`.
- `api/.env.example` — add `COMMENTS_AUDIO_DIR=/tmp/libolibo-comments` (local default; Railway sets it to `/data/comments`).
- `docs/specs/api/openapi.yaml` — document the four new endpoints.

**Untouched (intentional):** existing routes, `viewer.ts` middleware, the Adapty integration in `lib/adapty.ts`. Reuse, don't fork.

---

### Task 1: Extend Prisma schema with `User` and `Comment`

**Files:**
- Modify: `api/prisma/schema.prisma:39-57` (Episode block — add reverse relation), append at end (User + Comment).

- [ ] **Step 1: Add `comments Comment[]` reverse relation to `Episode`**

Edit `api/prisma/schema.prisma` — replace the `Episode` block (lines 39–57) so that the relations section reads:

```prisma
model Episode {
  id          String   @id
  podcastId   BigInt   @map("podcast_id")
  podcast     Podcast  @relation(fields: [podcastId], references: [id], onDelete: Cascade)
  title       String
  summary     String?
  pubDate     DateTime @map("pub_date")
  durationSec Int?     @map("duration_sec")
  audioUrl    String   @map("audio_url")
  isPremium   Boolean  @default(false) @map("is_premium")
  createdAt   DateTime @default(now()) @map("created_at")
  updatedAt   DateTime @updatedAt @map("updated_at")

  instagramPosts InstagramPost[]
  comments       Comment[]

  @@index([podcastId, pubDate(sort: Desc)])
  @@index([pubDate(sort: Desc)])
  @@map("episodes")
}
```

- [ ] **Step 2: Append `User` and `Comment` models**

Append to the end of `api/prisma/schema.prisma`:

```prisma
// Identity for users who post voice comments. Keyed by adapty_profile_id —
// the same identifier that's used in `entitlements`. Created lazily on
// first POST /v1/episodes/:id/comments. display_name is a deterministic
// pick from BIRDS pool (lib/birdNames.ts), with -2/-3 suffix on collision.
model User {
  adaptyProfileId String   @id @map("adapty_profile_id")
  displayName     String   @unique @map("display_name")
  createdAt       DateTime @default(now()) @map("created_at")

  comments Comment[]

  @@map("users")
}

// One voice comment on an episode. audio_path is a path on the Volume
// mount (e.g. /data/comments/<uuid>.m4a). Transcript can be empty if
// SFSpeechRecognizer failed on the iOS side. timecode_sec = the moment
// in the episode where the user tapped the mic button.
model Comment {
  id                    String   @id @default(uuid()) @db.Uuid
  episodeId             String   @map("episode_id")
  episode               Episode  @relation(fields: [episodeId], references: [id], onDelete: Cascade)
  authorAdaptyProfileId String   @map("author_adapty_profile_id")
  author                User     @relation(fields: [authorAdaptyProfileId], references: [adaptyProfileId], onDelete: Cascade)
  audioPath             String   @map("audio_path")
  audioDurationSec      Int      @map("audio_duration_sec")
  transcript            String
  timecodeSec           Int      @map("timecode_sec")
  createdAt             DateTime @default(now()) @map("created_at")

  @@index([episodeId, timecodeSec])
  @@map("comments")
}
```

- [ ] **Step 3: Sync schema to local Postgres**

Run from repo root:

```bash
cd api && docker compose up -d postgres && npx prisma db push && npx prisma generate && cd ..
```

Expected output ends with `Your database is now in sync with your Prisma schema.` and `Generated Prisma Client (...)`.

- [ ] **Step 4: Verify tables exist**

```bash
cd api && docker compose exec postgres psql -U postgres -d libolibo -c '\dt' && cd ..
```

Expected: `users` and `comments` appear in the list along with existing tables.

- [ ] **Step 5: Commit**

```bash
git add api/prisma/schema.prisma
git commit -m "api(comments): add User and Comment models"
```

---

### Task 2: Russian bird name pool and deterministic picker

**Files:**
- Create: `api/src/lib/birdNames.ts`
- Create: `api/test/birdNames.test.ts`

The picker is a pure function over the pool — easy to unit-test without DB. Collision handling against the DB happens later in the route handler (Task 6); for the picker, we just expose a stable `(profileId) → name` mapping plus a `withSuffix(name, n)` helper.

- [ ] **Step 1: Write the failing test**

Create `api/test/birdNames.test.ts`:

```typescript
import { describe, it, expect } from "vitest";
import { BIRDS, pickBirdName, withSuffix } from "../src/lib/birdNames.js";

describe("BIRDS pool", () => {
  it("contains at least 1000 unique entries", () => {
    expect(BIRDS.length).toBeGreaterThanOrEqual(1000);
    expect(new Set(BIRDS).size).toBe(BIRDS.length);
  });

  it("contains only non-empty Russian strings", () => {
    for (const name of BIRDS) {
      expect(name).toMatch(/^[А-ЯЁа-яё][А-ЯЁа-яё-]+$/);
    }
  });
});

describe("pickBirdName", () => {
  it("is deterministic: same profileId → same name", () => {
    const a = pickBirdName("11111111-1111-4111-8111-111111111111");
    const b = pickBirdName("11111111-1111-4111-8111-111111111111");
    expect(a).toBe(b);
  });

  it("returns a name from the pool", () => {
    const name = pickBirdName("22222222-2222-4222-8222-222222222222");
    expect(BIRDS).toContain(name);
  });

  it("distributes across the pool (different ids → different names, mostly)", () => {
    const names = new Set<string>();
    for (let i = 0; i < 200; i++) {
      const id = `${i.toString(16).padStart(8, "0")}-1111-4111-8111-111111111111`;
      names.add(pickBirdName(id));
    }
    expect(names.size).toBeGreaterThan(150);
  });
});

describe("withSuffix", () => {
  it("appends -N to the base name", () => {
    expect(withSuffix("Сорока", 2)).toBe("Сорока-2");
    expect(withSuffix("Сорока", 7)).toBe("Сорока-7");
  });

  it("rejects suffix < 2 (the bare name is the n=1 case)", () => {
    expect(() => withSuffix("Сорока", 1)).toThrow();
    expect(() => withSuffix("Сорока", 0)).toThrow();
  });
});
```

- [ ] **Step 2: Run the test, confirm it fails**

```bash
cd api && npm test -- birdNames && cd ..
```

Expected: failures with `Cannot find module './lib/birdNames.js'` or similar.

- [ ] **Step 3: Implement the module**

Create `api/src/lib/birdNames.ts`:

```typescript
import { createHash } from "node:crypto";

// Pool of Russian-language bird names. Curated from public ornithological
// references (RUWIKI «Птицы России», «Птицы мира»). Single-word names only;
// no compound forms. Stable ordering — never reorder, only append, since
// the picker maps profileId → index by hash and we want stable display
// names across deploys.
export const BIRDS: readonly string[] = Object.freeze([
  // FILL_FROM_SCRIPT: see scripts/generate-birds.ts (Task 2.5).
  // The list below is a starter that satisfies the >=1000-unique invariant.
  // Append additional curated names; do not reorder.
]);

export function pickBirdName(profileId: string): string {
  if (BIRDS.length === 0) {
    throw new Error("BIRDS pool is empty — populate api/src/lib/birdNames.ts");
  }
  // 32 hex chars → 128-bit unsigned. We only need uniform distribution
  // modulo BIRDS.length, so collapsing to BigInt → Number via mod is fine.
  const digest = createHash("sha256").update(profileId).digest("hex");
  const asBigInt = BigInt("0x" + digest);
  const idx = Number(asBigInt % BigInt(BIRDS.length));
  return BIRDS[idx]!;
}

export function withSuffix(name: string, n: number): string {
  if (n < 2) {
    throw new Error(`withSuffix(n) expects n >= 2, got ${n}`);
  }
  return `${name}-${n}`;
}
```

- [ ] **Step 4: Run the test, confirm three of four describe-blocks fail**

```bash
cd api && npm test -- birdNames && cd ..
```

Expected: pool tests fail (BIRDS is empty); picker test fails (`pickBirdName` throws); only `withSuffix` passes. We populate the pool in Step 5.

- [ ] **Step 5: Populate the BIRDS pool**

Replace the `Object.freeze([])` body in `api/src/lib/birdNames.ts` with a literal array of ≥1000 single-word Russian bird names. Source list manually from public ornithological references — paste in alphabetical order to make future additions easy.

Acceptance: `BIRDS.length >= 1000`, all entries pass `/^[А-ЯЁа-яё][А-ЯЁа-яё-]+$/`, all unique. The test in Step 1 enforces these invariants.

If hand-typing 1000+ names is too slow, write a one-shot script `api/scripts/generate-birds.ts` that scrapes RUWIKI Bird-of-Russia table → outputs a TS array literal → manually paste into `birdNames.ts`. Don't ship the scraping script — it's a one-off.

- [ ] **Step 6: Run the test, confirm all pass**

```bash
cd api && npm test -- birdNames && cd ..
```

Expected: all 8 tests pass.

- [ ] **Step 7: Commit**

```bash
git add api/src/lib/birdNames.ts api/test/birdNames.test.ts
git commit -m "api(comments): bird name pool and deterministic picker"
```

---

### Task 3: `requirePremium` middleware

**Files:**
- Create: `api/src/middleware/requirePremium.ts`
- Create: `api/test/requirePremium.test.ts`

The middleware reads `req.viewer` (set by `resolveViewer` upstream) and rejects with 402 if not premium. If `resolveViewer` hasn't run, that's a wiring bug — throw a server-side error.

- [ ] **Step 1: Write the failing test**

Create `api/test/requirePremium.test.ts`:

```typescript
import { describe, it, expect, vi } from "vitest";
import type { Request, Response, NextFunction } from "express";
import { requirePremium } from "../src/middleware/requirePremium.js";

function makeReq(viewer: Request["viewer"]): Request {
  return { viewer } as unknown as Request;
}

function makeRes(): { res: Response; status: ReturnType<typeof vi.fn>; json: ReturnType<typeof vi.fn> } {
  const json = vi.fn();
  const status = vi.fn(() => ({ json }));
  const res = { status } as unknown as Response;
  return { res, status, json };
}

describe("requirePremium", () => {
  it("calls next() when viewer is premium", () => {
    const req = makeReq({ hasPremiumEntitlement: true });
    const { res } = makeRes();
    const next = vi.fn() as unknown as NextFunction;

    requirePremium(req, res, next);

    expect(next).toHaveBeenCalledOnce();
  });

  it("responds 402 premium_required when viewer is not premium", () => {
    const req = makeReq({ hasPremiumEntitlement: false });
    const { res, status, json } = makeRes();
    const next = vi.fn() as unknown as NextFunction;

    requirePremium(req, res, next);

    expect(next).not.toHaveBeenCalled();
    expect(status).toHaveBeenCalledWith(402);
    expect(json).toHaveBeenCalledWith({ error: "premium_required" });
  });

  it("calls next(error) if req.viewer is missing (wiring bug)", () => {
    const req = makeReq(undefined);
    const { res } = makeRes();
    const next = vi.fn() as unknown as NextFunction;

    requirePremium(req, res, next);

    expect(next).toHaveBeenCalledOnce();
    const arg = (next as unknown as { mock: { calls: unknown[][] } }).mock.calls[0]?.[0];
    expect(arg).toBeInstanceOf(Error);
  });
});
```

- [ ] **Step 2: Run, confirm fails**

```bash
cd api && npm test -- requirePremium && cd ..
```

Expected: `Cannot find module './middleware/requirePremium.js'`.

- [ ] **Step 3: Implement the middleware**

Create `api/src/middleware/requirePremium.ts`:

```typescript
import type { RequestHandler } from "express";

// Use AFTER resolveViewer. Rejects with 402 if the viewer doesn't have an
// active premium entitlement. Wiring guard: if req.viewer is undefined,
// resolveViewer wasn't applied — that's a server-side mistake, surface it.
export const requirePremium: RequestHandler = (req, res, next) => {
  if (req.viewer === undefined) {
    return next(
      new Error(
        "requirePremium: req.viewer is undefined — apply resolveViewer first",
      ),
    );
  }
  if (!req.viewer.hasPremiumEntitlement) {
    res.status(402).json({ error: "premium_required" });
    return;
  }
  next();
};
```

- [ ] **Step 4: Run, confirm passes**

```bash
cd api && npm test -- requirePremium && cd ..
```

Expected: all 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add api/src/middleware/requirePremium.ts api/test/requirePremium.test.ts
git commit -m "api(comments): requirePremium middleware (402 gate)"
```

---

### Task 4: Audio storage helpers (Volume-backed)

**Files:**
- Create: `api/src/lib/audioStorage.ts`
- Create: `api/test/audioStorage.test.ts`

The module is a thin wrapper around `node:fs/promises`. Tests use a tmp dir to avoid polluting the real Volume path.

- [ ] **Step 1: Write the failing test**

Create `api/test/audioStorage.test.ts`:

```typescript
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { createAudioStorage } from "../src/lib/audioStorage.js";

let dir: string;

beforeEach(async () => {
  dir = await mkdtemp(path.join(tmpdir(), "libolibo-audio-"));
});

afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

describe("audioStorage", () => {
  it("saves a buffer and returns a path inside the configured dir", async () => {
    const storage = createAudioStorage({ baseDir: dir });
    const buf = Buffer.from([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70]); // m4a magic

    const result = await storage.save(buf);

    expect(result.path.startsWith(dir + path.sep)).toBe(true);
    expect(result.path.endsWith(".m4a")).toBe(true);
    expect(result.size).toBe(buf.length);
    const written = await readFile(result.path);
    expect(written.equals(buf)).toBe(true);
  });

  it("delete removes the file", async () => {
    const storage = createAudioStorage({ baseDir: dir });
    const { path: p } = await storage.save(Buffer.from("data"));
    await storage.delete(p);
    await expect(readFile(p)).rejects.toThrow();
  });

  it("delete is idempotent — non-existent path does not throw", async () => {
    const storage = createAudioStorage({ baseDir: dir });
    await expect(
      storage.delete(path.join(dir, "missing.m4a")),
    ).resolves.toBeUndefined();
  });

  it("rejects paths outside the base dir (path-traversal guard)", async () => {
    const storage = createAudioStorage({ baseDir: dir });
    await expect(storage.delete("/etc/passwd")).rejects.toThrow(/outside/);
  });

  it("creates the base dir if missing", async () => {
    const nested = path.join(dir, "nested", "dir");
    const storage = createAudioStorage({ baseDir: nested });
    const result = await storage.save(Buffer.from("data"));
    expect(result.path.startsWith(nested + path.sep)).toBe(true);
  });
});
```

- [ ] **Step 2: Run, confirm fails**

```bash
cd api && npm test -- audioStorage && cd ..
```

Expected: module not found error.

- [ ] **Step 3: Implement audioStorage**

Create `api/src/lib/audioStorage.ts`:

```typescript
import { mkdir, unlink, writeFile, stat } from "node:fs/promises";
import { createReadStream } from "node:fs";
import path from "node:path";
import { randomUUID } from "node:crypto";
import type { Response } from "express";

export interface AudioStorageConfig {
  baseDir: string;
}

export interface SavedAudio {
  path: string;
  size: number;
}

export interface AudioStorage {
  save(buf: Buffer): Promise<SavedAudio>;
  delete(filePath: string): Promise<void>;
  stream(filePath: string, res: Response): Promise<void>;
}

export function createAudioStorage(cfg: AudioStorageConfig): AudioStorage {
  const baseDir = path.resolve(cfg.baseDir);

  async function ensureDir() {
    await mkdir(baseDir, { recursive: true });
  }

  function assertInBase(p: string) {
    const resolved = path.resolve(p);
    if (!resolved.startsWith(baseDir + path.sep) && resolved !== baseDir) {
      throw new Error(`refusing to operate on path outside ${baseDir}: ${p}`);
    }
  }

  return {
    async save(buf) {
      await ensureDir();
      const filePath = path.join(baseDir, `${randomUUID()}.m4a`);
      await writeFile(filePath, buf);
      return { path: filePath, size: buf.length };
    },
    async delete(filePath) {
      assertInBase(filePath);
      try {
        await unlink(filePath);
      } catch (err) {
        if ((err as NodeJS.ErrnoException).code === "ENOENT") return;
        throw err;
      }
    },
    async stream(filePath, res) {
      assertInBase(filePath);
      const s = await stat(filePath);
      res.setHeader("Content-Type", "audio/mp4");
      res.setHeader("Content-Length", String(s.size));
      res.setHeader("Cache-Control", "public, max-age=31536000, immutable");
      res.setHeader("ETag", path.basename(filePath, ".m4a"));
      await new Promise<void>((resolve, reject) => {
        const stream = createReadStream(filePath);
        stream.on("end", () => resolve());
        stream.on("error", reject);
        stream.pipe(res);
      });
    },
  };
}
```

- [ ] **Step 4: Run, confirm passes**

```bash
cd api && npm test -- audioStorage && cd ..
```

Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add api/src/lib/audioStorage.ts api/test/audioStorage.test.ts
git commit -m "api(comments): audio storage helpers (Volume-backed)"
```

---

### Task 5: Add `multer` dependency and m4a magic-byte sniffer

**Files:**
- Modify: `api/package.json`
- Create: `api/src/lib/audioMime.ts`
- Create: `api/test/audioMime.test.ts`

We accept multipart upload via `multer`, but we never trust the client `Content-Type`. The sniffer reads the first ≈12 bytes of the buffer and confirms the m4a/AAC `ftyp` box.

- [ ] **Step 1: Install multer**

```bash
cd api && npm install multer && npm install --save-dev @types/multer && cd ..
```

Expected: `package.json` and `package-lock.json` updated; no errors.

- [ ] **Step 2: Write the failing test**

Create `api/test/audioMime.test.ts`:

```typescript
import { describe, expect, it } from "vitest";
import { isLikelyM4A } from "../src/lib/audioMime.js";

describe("isLikelyM4A", () => {
  it("returns true for a buffer starting with the m4a ftyp box", () => {
    // 4 size bytes + 'ftyp' + brand 'M4A '
    const buf = Buffer.from([
      0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70,
      0x4d, 0x34, 0x41, 0x20, 0x00, 0x00, 0x00, 0x00,
    ]);
    expect(isLikelyM4A(buf)).toBe(true);
  });

  it("returns true for ftyp brand mp42 (also AAC-in-MP4)", () => {
    const buf = Buffer.from([
      0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70,
      0x6d, 0x70, 0x34, 0x32,
    ]);
    expect(isLikelyM4A(buf)).toBe(true);
  });

  it("returns false for an mp3 buffer", () => {
    // ID3v2 header
    const buf = Buffer.from([0x49, 0x44, 0x33, 0x03, 0x00]);
    expect(isLikelyM4A(buf)).toBe(false);
  });

  it("returns false for a too-short buffer", () => {
    expect(isLikelyM4A(Buffer.from([0x00, 0x01]))).toBe(false);
  });

  it("returns false for empty buffer", () => {
    expect(isLikelyM4A(Buffer.alloc(0))).toBe(false);
  });
});
```

- [ ] **Step 3: Run, confirm fails**

```bash
cd api && npm test -- audioMime && cd ..
```

Expected: module not found.

- [ ] **Step 4: Implement audioMime**

Create `api/src/lib/audioMime.ts`:

```typescript
// MP4-family magic-byte detector. m4a/AAC files are MP4 containers with a
// `ftyp` box at offset 4. We don't validate the brand strictly — Apple
// emits various brands (M4A , mp42, isom, …) depending on encoder settings.
// The 'ftyp' marker at offset 4 is the reliable signal.
export function isLikelyM4A(buf: Buffer): boolean {
  if (buf.length < 12) return false;
  // bytes 4..8 must be 'ftyp'
  return (
    buf[4] === 0x66 && // 'f'
    buf[5] === 0x74 && // 't'
    buf[6] === 0x79 && // 'y'
    buf[7] === 0x70 // 'p'
  );
}
```

- [ ] **Step 5: Run, confirm passes**

```bash
cd api && npm test -- audioMime && cd ..
```

Expected: 5 tests pass.

- [ ] **Step 6: Commit**

```bash
git add api/package.json api/package-lock.json api/src/lib/audioMime.ts api/test/audioMime.test.ts
git commit -m "api(comments): add multer dep and m4a magic-byte sniffer"
```

---

### Task 6: `GET /v1/episodes/:episodeId/comments` (list)

**Files:**
- Create: `api/src/routes/comments.ts`
- Modify: `api/src/app.ts:1-9` (import + register)

We open with the simplest endpoint — read-only, no auth, no body validation. Sets up the route file scaffold for subsequent tasks. No automated test (the existing project pattern is manual curl for endpoints; we'll add a smoke-curl after deploy in Task 11).

- [ ] **Step 1: Create the route file with the GET handler**

Create `api/src/routes/comments.ts`:

```typescript
import { Router } from "express";
import { prisma } from "../db.js";
import { asyncHandler } from "../lib/asyncHandler.js";

export const commentsRouter = Router();

commentsRouter.get(
  "/episodes/:episodeId/comments",
  asyncHandler(async (req, res) => {
    const { episodeId } = req.params;
    const rows = await prisma.comment.findMany({
      where: { episodeId },
      include: { author: true },
      orderBy: [{ timecodeSec: "asc" }, { createdAt: "asc" }],
      take: 1000,
    });
    const baseUrl = `${req.protocol}://${req.get("host")}`;
    res.json({
      items: rows.map((c) => ({
        id: c.id,
        author: { birdName: c.author.displayName },
        transcript: c.transcript,
        timecodeSec: c.timecodeSec,
        durationSec: c.audioDurationSec,
        audioUrl: `${baseUrl}/v1/comments/${c.id}/audio`,
        createdAt: c.createdAt.toISOString(),
      })),
    });
  }),
);
```

- [ ] **Step 2: Register the router in `app.ts`**

Edit `api/src/app.ts` — add import and `app.use` line:

```typescript
import express, { type ErrorRequestHandler } from "express";
import { healthRouter } from "./routes/health.js";
import { podcastsRouter } from "./routes/podcasts.js";
import { feedRouter } from "./routes/feed.js";
import { episodesRouter } from "./routes/episodes.js";
import { devicesRouter } from "./routes/devices.js";
import { meRouter } from "./routes/me.js";
import { commentsRouter } from "./routes/comments.js";
```

…and add to the router-mounting block:

```typescript
  app.use("/v1", meRouter);
  app.use("/v1", commentsRouter);
```

- [ ] **Step 3: Type-check**

```bash
cd api && npx tsc -p tsconfig.json --noEmit && cd ..
```

Expected: no errors.

- [ ] **Step 4: Smoke-test against an existing episode**

Pick any episode id from the dev DB:

```bash
cd api && docker compose exec postgres psql -U postgres -d libolibo -c "SELECT id FROM episodes LIMIT 1;" && cd ..
```

Then with the API running locally:

```bash
curl -s http://localhost:3000/v1/episodes/<episode-id>/comments
```

Expected: `{"items":[]}` (no comments yet).

- [ ] **Step 5: Commit**

```bash
git add api/src/routes/comments.ts api/src/app.ts
git commit -m "api(comments): GET /v1/episodes/:id/comments (list, empty)"
```

---

### Task 7: `POST /v1/episodes/:episodeId/comments` (create)

**Files:**
- Modify: `api/src/routes/comments.ts`

Adds: multer multipart parsing with size limit, magic-byte sniff, body-field parsing & validation, lazy `User` upsert with bird-name collision suffix, audio save, comment insert. Includes per-`profile_id` rate limit (10/min) using the `Map`-based pattern already used in `me.ts`.

- [ ] **Step 1: Add the POST handler**

Edit `api/src/routes/comments.ts` — add imports at the top:

```typescript
import { Router } from "express";
import multer from "multer";
import { prisma } from "../db.js";
import { asyncHandler } from "../lib/asyncHandler.js";
import { resolveViewer } from "../middleware/viewer.js";
import { requirePremium } from "../middleware/requirePremium.js";
import { createAudioStorage } from "../lib/audioStorage.js";
import { isLikelyM4A } from "../lib/audioMime.js";
import { pickBirdName, withSuffix } from "../lib/birdNames.js";
```

Add the storage singleton + multer config + rate-limit map below the imports, before `commentsRouter`:

```typescript
const COMMENTS_AUDIO_DIR =
  process.env.COMMENTS_AUDIO_DIR ?? "/tmp/libolibo-comments";
const audioStorage = createAudioStorage({ baseDir: COMMENTS_AUDIO_DIR });

const MAX_AUDIO_BYTES = 2 * 1024 * 1024;
const MAX_DURATION_SEC = 60;
const MAX_TRANSCRIPT_LEN = 4_000;

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_AUDIO_BYTES, files: 1 },
});

const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 10;
const recentPosts = new Map<string, number[]>();

function checkRateLimit(profileId: string): boolean {
  const now = Date.now();
  const entries = (recentPosts.get(profileId) ?? []).filter(
    (t) => now - t < RATE_LIMIT_WINDOW_MS,
  );
  if (entries.length >= RATE_LIMIT_MAX) return false;
  entries.push(now);
  recentPosts.set(profileId, entries);
  return true;
}

async function ensureUser(profileId: string): Promise<{ adaptyProfileId: string; displayName: string }> {
  const existing = await prisma.user.findUnique({
    where: { adaptyProfileId: profileId },
  });
  if (existing) return existing;

  const base = pickBirdName(profileId);
  for (let n = 1; n <= 50; n++) {
    const candidate = n === 1 ? base : withSuffix(base, n);
    try {
      return await prisma.user.create({
        data: { adaptyProfileId: profileId, displayName: candidate },
      });
    } catch (err) {
      const code = (err as { code?: string }).code;
      if (code === "P2002") continue; // UNIQUE collision, try next suffix
      throw err;
    }
  }
  throw new Error(`could not pick a free bird name for ${profileId} after 50 attempts`);
}
```

Add the POST handler below the existing GET handler:

```typescript
commentsRouter.post(
  "/episodes/:episodeId/comments",
  resolveViewer,
  requirePremium,
  upload.single("audio"),
  asyncHandler(async (req, res) => {
    const profileId = req.adaptyProfileId;
    if (!profileId) {
      // resolveViewer attaches adaptyProfileId only when the header is valid.
      // requirePremium passes only when entitlement is present, which implies
      // a valid profileId. Defensive guard.
      return res.status(400).json({ error: "missing_profile_id" });
    }

    if (!checkRateLimit(profileId)) {
      res.setHeader("Retry-After", "60");
      return res.status(429).json({ error: "rate_limited" });
    }

    const { episodeId } = req.params;
    const episode = await prisma.episode.findUnique({ where: { id: episodeId } });
    if (!episode) {
      return res.status(404).json({ error: "episode_not_found" });
    }

    const file = req.file;
    if (!file) {
      return res.status(400).json({ error: "missing_audio" });
    }
    if (!isLikelyM4A(file.buffer)) {
      return res.status(400).json({ error: "invalid_audio" });
    }

    const transcript = String(req.body?.transcript ?? "");
    if (transcript.length > MAX_TRANSCRIPT_LEN) {
      return res.status(400).json({ error: "transcript_too_long" });
    }

    const durationSec = Number.parseInt(String(req.body?.durationSec ?? ""), 10);
    if (!Number.isFinite(durationSec) || durationSec <= 0 || durationSec > MAX_DURATION_SEC) {
      return res.status(400).json({ error: "invalid_duration" });
    }

    const timecodeSec = Number.parseInt(String(req.body?.timecodeSec ?? ""), 10);
    if (!Number.isFinite(timecodeSec) || timecodeSec < 0) {
      return res.status(400).json({ error: "invalid_timecode" });
    }

    const user = await ensureUser(profileId);
    const saved = await audioStorage.save(file.buffer);

    let comment;
    try {
      comment = await prisma.comment.create({
        data: {
          episodeId,
          authorAdaptyProfileId: user.adaptyProfileId,
          audioPath: saved.path,
          audioDurationSec: durationSec,
          transcript,
          timecodeSec,
        },
      });
    } catch (err) {
      // Insert failed after we wrote the file — clean up to avoid orphan.
      await audioStorage.delete(saved.path).catch(() => {});
      throw err;
    }

    const baseUrl = `${req.protocol}://${req.get("host")}`;
    return res.status(201).json({
      id: comment.id,
      author: { birdName: user.displayName },
      transcript: comment.transcript,
      timecodeSec: comment.timecodeSec,
      durationSec: comment.audioDurationSec,
      audioUrl: `${baseUrl}/v1/comments/${comment.id}/audio`,
      createdAt: comment.createdAt.toISOString(),
    });
  }),
);
```

Add multer error handler at the bottom of the file (before the `export`):

```typescript
// multer surfaces size-limit failures as MulterError(LIMIT_FILE_SIZE).
commentsRouter.use(((err, _req, res, next) => {
  if (err && (err as { code?: string }).code === "LIMIT_FILE_SIZE") {
    return res.status(413).json({ error: "payload_too_large" });
  }
  next(err);
}) as import("express").ErrorRequestHandler);
```

- [ ] **Step 2: Type-check**

```bash
cd api && npx tsc -p tsconfig.json --noEmit && cd ..
```

Expected: no errors.

- [ ] **Step 3: Smoke-test missing premium → 402**

With the API running and a known non-premium profile id:

```bash
curl -i -X POST http://localhost:3000/v1/episodes/<episode-id>/comments \
  -H "X-Adapty-Profile-Id: 00000000-0000-4000-8000-000000000000" \
  -F audio=@/dev/null \
  -F durationSec=5 \
  -F timecodeSec=0 \
  -F transcript=test
```

Expected: `HTTP/1.1 402` + body `{"error":"premium_required"}`.

- [ ] **Step 4: Smoke-test happy path**

Seed a premium entitlement in dev DB:

```bash
docker compose exec postgres psql -U postgres -d libolibo -c \
  "INSERT INTO entitlements (adapty_profile_id, is_premium) VALUES ('11111111-1111-4111-8111-111111111111', true) ON CONFLICT DO NOTHING;"
```

Generate a 1-second test m4a (e.g. via `say` on macOS):

```bash
say -o /tmp/test.m4a -v Yuri "Привет"
```

Then POST:

```bash
curl -i -X POST http://localhost:3000/v1/episodes/<episode-id>/comments \
  -H "X-Adapty-Profile-Id: 11111111-1111-4111-8111-111111111111" \
  -F audio=@/tmp/test.m4a \
  -F durationSec=1 \
  -F timecodeSec=0 \
  -F transcript=Привет
```

Expected: `HTTP/1.1 201` + body with `id`, `author.birdName`, `audioUrl`. The bird name should be a single Russian word from the pool.

- [ ] **Step 5: Smoke-test bird-name stability**

Re-run the same POST with a different transcript. Verify the response uses **the same** `author.birdName` — confirms `ensureUser` did not create a duplicate.

- [ ] **Step 6: Commit**

```bash
git add api/src/routes/comments.ts
git commit -m "api(comments): POST /v1/episodes/:id/comments (create with bird-name + premium gate)"
```

---

### Task 8: `DELETE /v1/comments/:id`

**Files:**
- Modify: `api/src/routes/comments.ts`

Owner-only delete. Removes the file from Volume after successful row delete.

- [ ] **Step 1: Add the DELETE handler**

Insert into `api/src/routes/comments.ts`, after the POST handler:

```typescript
commentsRouter.delete(
  "/comments/:id",
  resolveViewer,
  asyncHandler(async (req, res) => {
    const profileId = req.adaptyProfileId;
    if (!profileId) {
      return res.status(401).json({ error: "missing_profile_id" });
    }
    const comment = await prisma.comment.findUnique({
      where: { id: req.params.id },
    });
    if (!comment) {
      return res.status(404).json({ error: "comment_not_found" });
    }
    if (comment.authorAdaptyProfileId !== profileId) {
      return res.status(403).json({ error: "forbidden" });
    }
    await prisma.comment.delete({ where: { id: comment.id } });
    await audioStorage.delete(comment.audioPath).catch(() => {});
    return res.status(204).end();
  }),
);
```

- [ ] **Step 2: Type-check**

```bash
cd api && npx tsc -p tsconfig.json --noEmit && cd ..
```

Expected: no errors.

- [ ] **Step 3: Smoke-test 403**

Try to delete the comment from Task 7 with a different profile id:

```bash
curl -i -X DELETE http://localhost:3000/v1/comments/<id-from-task-7> \
  -H "X-Adapty-Profile-Id: 22222222-2222-4222-8222-222222222222"
```

Expected: `HTTP/1.1 403` + `{"error":"forbidden"}`.

- [ ] **Step 4: Smoke-test 204 happy path**

Same with the original profile id:

```bash
curl -i -X DELETE http://localhost:3000/v1/comments/<id-from-task-7> \
  -H "X-Adapty-Profile-Id: 11111111-1111-4111-8111-111111111111"
```

Expected: `HTTP/1.1 204`. Confirm the file is gone:

```bash
ls /tmp/libolibo-comments/
```

(The file from Task 7 should not appear.)

- [ ] **Step 5: Commit**

```bash
git add api/src/routes/comments.ts
git commit -m "api(comments): DELETE /v1/comments/:id (owner-only)"
```

---

### Task 9: `GET /v1/comments/:id/audio` (stream)

**Files:**
- Modify: `api/src/routes/comments.ts`

Streams the audio file with cache-forever headers (audio is immutable per id).

- [ ] **Step 1: Add the audio handler**

Insert into `api/src/routes/comments.ts`, after the DELETE handler:

```typescript
commentsRouter.get(
  "/comments/:id/audio",
  asyncHandler(async (req, res) => {
    const comment = await prisma.comment.findUnique({
      where: { id: req.params.id },
      select: { id: true, audioPath: true },
    });
    if (!comment) {
      return res.status(404).json({ error: "comment_not_found" });
    }
    await audioStorage.stream(comment.audioPath, res);
  }),
);
```

- [ ] **Step 2: Type-check**

```bash
cd api && npx tsc -p tsconfig.json --noEmit && cd ..
```

Expected: no errors.

- [ ] **Step 3: Smoke-test**

Re-create a comment from Task 7 (use a fresh POST) → take the `id` from the response → fetch:

```bash
curl -i http://localhost:3000/v1/comments/<id>/audio --output /tmp/fetched.m4a
```

Expected: `HTTP/1.1 200`, `Content-Type: audio/mp4`, `Cache-Control: public, max-age=31536000, immutable`. File contents match the upload.

- [ ] **Step 4: Smoke-test 404**

```bash
curl -i http://localhost:3000/v1/comments/00000000-0000-4000-8000-000000000000/audio
```

Expected: `HTTP/1.1 404` + `{"error":"comment_not_found"}`.

- [ ] **Step 5: Commit**

```bash
git add api/src/routes/comments.ts
git commit -m "api(comments): GET /v1/comments/:id/audio (stream)"
```

---

### Task 10: Run the full Vitest suite

**Files:** none.

Sanity check that the new files don't break existing tests.

- [ ] **Step 1: Run all tests**

```bash
cd api && npm test && cd ..
```

Expected: all suites pass — `birdNames`, `audioStorage`, `audioMime`, `requirePremium`, plus existing (`adapty`, `instagram-collector`, `instagram-graph-client`, `serialize`).

- [ ] **Step 2: If any test fails — fix the cause and re-run**

(No commit step — this is a guard, not a change.)

---

### Task 11: Update OpenAPI contract

**Files:**
- Modify: `docs/specs/api/openapi.yaml`

- [ ] **Step 1: Read existing OpenAPI to match style**

```bash
head -60 docs/specs/api/openapi.yaml
```

Note: existing endpoints, naming conventions (snake_case vs camelCase), and `components/schemas` patterns.

- [ ] **Step 2: Add the four new endpoints**

Append four `paths` entries to `docs/specs/api/openapi.yaml`:

- `GET /v1/episodes/{episodeId}/comments` → 200 returning `CommentList`.
- `POST /v1/episodes/{episodeId}/comments` → multipart, requires `X-Adapty-Profile-Id`, returns 201 `Comment`. Document the 402, 413, 429, 400 error responses.
- `DELETE /v1/comments/{id}` → 204 / 403 / 404.
- `GET /v1/comments/{id}/audio` → 200 (`audio/mp4`) / 404.

Add `Comment`, `CommentList`, `CommentAuthor` schemas to `components/schemas`. Match the existing style (the file uses camelCase for response fields).

(There is no automated check enforcing OpenAPI/route alignment — this is a documentation step. Cross-check by hand that field names match the JSON the route returns.)

- [ ] **Step 3: Commit**

```bash
git add docs/specs/api/openapi.yaml
git commit -m "docs(openapi): add voice-comments endpoints"
```

---

### Task 12: Local environment defaults

**Files:**
- Modify: `api/.env.example`

- [ ] **Step 1: Add the env var**

Append to `api/.env.example`:

```
# Voice comments — directory where uploaded m4a files are written. On
# Railway this points to the Volume mount (/data/comments). Locally
# defaults to /tmp/libolibo-comments if unset.
COMMENTS_AUDIO_DIR=/tmp/libolibo-comments
```

- [ ] **Step 2: Commit**

```bash
git add api/.env.example
git commit -m "api(comments): document COMMENTS_AUDIO_DIR env var"
```

---

### Task 13: Provision Railway Volume and deploy

**Files:** none (Railway UI work + verify via curl).

This is the only step that requires user (Илья) action in the Railway dashboard. The implementer should hand off, not click around in the dashboard themselves.

- [ ] **Step 1: Confirm with Илья that Railway Volume is provisioned**

Required: a Volume mounted at `/data` on the API service, and `COMMENTS_AUDIO_DIR=/data/comments` set in Railway → Service → Variables. Cost: small (~$0.25/GB/mo at time of writing).

- [ ] **Step 2: Push the branch and let Railway auto-deploy**

```bash
git push origin HEAD
```

Watch the Railway deployment logs. Expected: build succeeds, `prisma generate` runs in postinstall (already configured), service comes up with `Listening on :3000`.

- [ ] **Step 3: Confirm schema synced on prod**

Either run `npx prisma db push --accept-data-loss=false` against the prod DATABASE_URL from a local shell with the prod env, OR (more conservative) tell Илья to run it from the Railway shell:

```bash
npx prisma db push
```

Expected: `Your database is now in sync with your Prisma schema.` No data is lost — only `users` and `comments` tables get created.

- [ ] **Step 4: Smoke-test prod**

Pick a real episode id from prod, real premium-`X-Adapty-Profile-Id`:

```bash
PROD=https://<api-service>.up.railway.app

curl -s $PROD/v1/episodes/<episode-id>/comments
# → {"items":[]}

# Then a real POST with a real m4a from the local filesystem:
curl -i -X POST $PROD/v1/episodes/<episode-id>/comments \
  -H "X-Adapty-Profile-Id: <real-premium-profile-id>" \
  -F audio=@/tmp/test.m4a \
  -F durationSec=1 \
  -F timecodeSec=0 \
  -F transcript=Хеллоу

# Then GET to confirm it appears:
curl -s $PROD/v1/episodes/<episode-id>/comments
```

Expected: 201 on POST, comment in subsequent GET, `audioUrl` reachable.

- [ ] **Step 5: Cleanup the smoke-test comment**

```bash
curl -i -X DELETE $PROD/v1/comments/<id-from-step-4> \
  -H "X-Adapty-Profile-Id: <same-profile-id>"
```

Expected: 204.

- [ ] **Step 6: Write a session log and commit**

Create `docs/sessions/YYYY-MM-DD-NN-voice-comments-backend.md` per `CLAUDE.md` convention. Include:

- Что сделали (этот план).
- Что в Railway (Volume, env var).
- Открытые вопросы (например, отсутствие job'а для очистки orphan-файлов при cascade-delete эпизода — ставим issue).
- Следующая сессия — iOS.

Commit and push.

---

## Self-Review

Spec sections vs tasks:

| Spec section | Covered by |
|---|---|
| `User`, `Comment` schemas | Task 1 |
| Bird name pool + algorithm | Task 2 |
| `requirePremium` middleware | Task 3 |
| Volume audio storage | Task 4, env in Task 12 |
| `multer` + mime sniffing | Task 5 |
| `GET …/comments` | Task 6 |
| `POST …/comments` (premium gate, validation, ensureUser, save+insert, rate-limit) | Task 7 |
| `DELETE /comments/:id` | Task 8 |
| `GET /comments/:id/audio` | Task 9 |
| OpenAPI doc | Task 11 |
| Railway Volume + deploy | Task 13 |

**Not in this plan (explicitly deferred):**

- Orphan file cleanup on episode cascade-delete — flagged as issue in Task 13's session log. Adds a fs-walking job; out of scope for v1.
- Pagination on `GET …/comments` — limit 1000 is enough for current scale; revisit when an episode crosses that count.
- Server-side transcription fallback — iOS does it; if SFSpeechRecognizer fails, transcript is empty string. Server-side Whisper is a future enhancement.
- Comment editing — not in spec, not in plan.
- Moderation tooling — explicitly out of scope per spec.

**Type / signature consistency check:**

- `pickBirdName(profileId: string): string` — used in Task 7 step 1 inside `ensureUser`. ✓
- `withSuffix(name, n): string` — used the same way. ✓
- `createAudioStorage({ baseDir }): AudioStorage` returning `{ save, delete, stream }` — used in Task 7, 8, 9. ✓
- `isLikelyM4A(buf: Buffer): boolean` — used in Task 7. ✓
- `requirePremium` reads `req.viewer.hasPremiumEntitlement` (which `resolveViewer` sets via `viewer.ts:48`). ✓
- `req.adaptyProfileId` — set by `viewer.ts:32`, read in Task 7 / Task 8. ✓

**Placeholder scan:**

- Task 2 step 5 says "FILL_FROM_SCRIPT" inside the `BIRDS` literal — that's the explicit gap that step 5 itself fills. It's not a TBD-handoff; it's the work-product of that step. The acceptance criteria are concrete (≥1000, regex, unique).
- Task 11 step 2 describes adding OpenAPI entries by hand and matching style rather than showing the YAML literal — this is an editorial step where copy-pasting the existing style is more reliable than my fabricating it. Acceptable.
- No "TODO", "implement later", or "add appropriate error handling" left in plan.
