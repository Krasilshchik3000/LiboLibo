import { Router, type ErrorRequestHandler } from "express";
import multer from "multer";
import { prisma } from "../db.js";
import { asyncHandler } from "../lib/asyncHandler.js";
import { resolveViewer } from "../middleware/viewer.js";
import { requirePremium } from "../middleware/requirePremium.js";
import { createAudioStorage } from "../lib/audioStorage.js";
import { isLikelyM4A } from "../lib/audioMime.js";
import { pickBirdName, withSuffix } from "../lib/birdNames.js";

export const commentsRouter = Router();

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

// Per-profile rate limit (10/min). Mirrors the in-memory pattern used by
// /me/entitlement/refresh in routes/me.ts. Single-process; if we ever scale
// horizontally, swap for Redis or a token-bucket middleware.
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

// Lazy user creation. Bird name is deterministic from profile_id; on UNIQUE
// collision, append -2/-3/... until success. P2002 is Prisma's UNIQUE
// constraint violation code.
async function ensureUser(
  profileId: string,
): Promise<{ adaptyProfileId: string; displayName: string }> {
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
      if (code === "P2002") continue;
      throw err;
    }
  }
  throw new Error(
    `could not pick a free bird name for ${profileId} after 50 attempts`,
  );
}

commentsRouter.get(
  "/episodes/:episodeId/comments",
  asyncHandler(async (req, res) => {
    const episodeId = req.params.episodeId;
    if (typeof episodeId !== "string" || episodeId.length === 0) {
      return res.status(404).json({ error: "episode_not_found" });
    }
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
      // a valid profileId. Defensive guard for misconfigured middleware order.
      return res.status(400).json({ error: "missing_profile_id" });
    }

    if (!checkRateLimit(profileId)) {
      res.setHeader("Retry-After", "60");
      return res.status(429).json({ error: "rate_limited" });
    }

    const episodeId = req.params.episodeId;
    if (typeof episodeId !== "string" || episodeId.length === 0) {
      return res.status(404).json({ error: "episode_not_found" });
    }
    const episode = await prisma.episode.findUnique({
      where: { id: episodeId },
    });
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

    const durationSec = Number.parseInt(
      String(req.body?.durationSec ?? ""),
      10,
    );
    if (
      !Number.isFinite(durationSec) ||
      durationSec <= 0 ||
      durationSec > MAX_DURATION_SEC
    ) {
      return res.status(400).json({ error: "invalid_duration" });
    }

    const timecodeSec = Number.parseInt(
      String(req.body?.timecodeSec ?? ""),
      10,
    );
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

commentsRouter.delete(
  "/comments/:id",
  resolveViewer,
  asyncHandler(async (req, res) => {
    const profileId = req.adaptyProfileId;
    if (!profileId) {
      return res.status(401).json({ error: "missing_profile_id" });
    }
    const id = req.params.id;
    if (typeof id !== "string" || id.length === 0) {
      return res.status(404).json({ error: "comment_not_found" });
    }
    const comment = await prisma.comment.findUnique({ where: { id } });
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

commentsRouter.get(
  "/comments/:id/audio",
  asyncHandler(async (req, res) => {
    const id = req.params.id;
    if (typeof id !== "string" || id.length === 0) {
      return res.status(404).json({ error: "comment_not_found" });
    }
    const comment = await prisma.comment.findUnique({
      where: { id },
      select: { id: true, audioPath: true },
    });
    if (!comment) {
      return res.status(404).json({ error: "comment_not_found" });
    }
    await audioStorage.stream(comment.audioPath, res);
  }),
);

// multer surfaces size-limit failures as MulterError(LIMIT_FILE_SIZE) — keep
// it a route-scoped error handler so the global handler doesn't return 500.
const multerErrorHandler: ErrorRequestHandler = (err, _req, res, next) => {
  if (err && (err as { code?: string }).code === "LIMIT_FILE_SIZE") {
    return res.status(413).json({ error: "payload_too_large" });
  }
  next(err);
};
commentsRouter.use(multerErrorHandler);
